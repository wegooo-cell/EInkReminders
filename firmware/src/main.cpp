#include <Arduino.h>
#include <ArduinoJson.h>
#include <GxEPD2_BW.h>
#include <Preferences.h>
#include <SPI.h>
#include <WebServer.h>
#include <WiFi.h>
#include <WiFiManager.h>
#include <ESPmDNS.h>
#include <LittleFS.h>
#include <algorithm>
#include <vector>

#include "BoardConfig.h"

using Panel = GxEPD2_583_T8;
// Keep only 64 display rows in the GxEPD2 page buffer. The received 1-bit frame
// already occupies 38,880 bytes, and a second full-screen buffer exceeds the
// usable internal DRAM of WROOM-32E boards without PSRAM.
GxEPD2_BW<Panel, 64> display(Panel(PIN_EPD_CS, PIN_EPD_DC, PIN_EPD_RST, PIN_EPD_BUSY));

WebServer server(80);
Preferences preferences;
WiFiManager wifiManager;

constexpr char FIRMWARE_VERSION[] = "0.1.7";
constexpr uint32_t MIN_BUTTON_PRESS_MS = 25;
constexpr uint32_t CLICK_SEQUENCE_TIMEOUT_MS = 600;

// WiFiManager 2.0.17 has no bundled Simplified Chinese locale. This small
// browser-side dictionary keeps the captive portal itself in Chinese while
// retaining the library's proven Wi-Fi scanning and connection behavior.
const char CONFIG_PORTAL_CHINESE_HEAD[] PROGMEM = R"HTML(
<script>
document.addEventListener('DOMContentLoaded',function(){
  document.documentElement.lang='zh-CN';
  var pairs=[
    ['Configure WiFi (No scan)','配置 Wi-Fi（不扫描）'],
    ['Configure WiFi','配置 Wi-Fi'],
    ['Credentials saved','Wi-Fi 已保存'],
    ['Settings saved','设置已保存'],
    ['Saving Credentials','正在保存 Wi-Fi'],
    ['Trying to connect ESP to network.','设备正在连接 Wi-Fi。'],
    ['If it fails reconnect to AP to try again','如果连接失败，请重新连接设备热点后再试。'],
    ['No networks found. Refresh to scan again.','没有发现 Wi-Fi，请重新扫描。'],
    ['Show Password','显示密码'],
    ['Password','Wi-Fi 密码'],
    ['Refresh','重新扫描'],
    ['Save','保存并连接'],
    ['Connected','已连接'],
    ['Not connected','未连接'],
    ['Authentication failure','密码验证失败'],
    ['AP not found','找不到 Wi-Fi'],
    ['Could not connect','连接失败'],
    ['No AP set','尚未配置 Wi-Fi'],
    ['Module will reset in a few seconds.','设备将在几秒后重启。'],
    ['You can close the page, portal will continue to run','可以关闭此页面，配网服务会继续运行。'],
    ['An error occured','发生错误'],
    ['File not found','页面不存在'],
    ['Config ESP','配置设备 Wi-Fi'],
    ['Info','设备信息'],
    ['Setup','设置'],
    ['Close','关闭页面'],
    ['Restart','重启设备'],
    ['Exit','退出配网'],
    ['Erase WiFi config','清除 Wi-Fi 配置'],
    ['Erase','清除配置'],
    ['Update','更新固件'],
    ['Back','返回'],
    ['Yes','是'],
    ['No','否'],
    ['Unknown','未知']
  ];
  var walker=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT);
  var nodes=[];
  while(walker.nextNode())nodes.push(walker.currentNode);
  nodes.forEach(function(node){
    var value=node.nodeValue;
    pairs.forEach(function(pair){value=value.split(pair[0]).join(pair[1]);});
    node.nodeValue=value;
  });
});
</script>
)HTML";

struct Operation {
  uint64_t sequence = 0;
  String type;
  String syncId;
  String title;
  bool completed = false;
};

std::vector<Operation> operations;
uint8_t frameBuffer[DISPLAY_BYTES] = {};
std::vector<String> reminderIds;
size_t selectedIndex = 0;
uint64_t snapshotRevision = 0;
uint64_t nextSequence = 1;
bool buttonDown = false;
bool longPressHandled = false;
uint32_t buttonDownAt = 0;
uint8_t pendingClicks = 0;
uint32_t lastClickAt = 0;

enum class DisplayUploadError {
  none,
  invalidLength,
  invalidIndex,
  storage
};

File displayUploadFile;
DisplayUploadError displayUploadError = DisplayUploadError::none;
size_t displayUploadBytes = 0;
int displayUploadIndex = -1;

void renderFrame();

String newSyncId() {
  uint64_t chip = ESP.getEfuseMac();
  uint32_t randomPart = esp_random();
  char value[48];
  snprintf(value, sizeof(value), "%08lx-%08lx-%08lx",
           static_cast<unsigned long>(chip >> 32),
           static_cast<unsigned long>(chip),
           static_cast<unsigned long>(randomPart));
  return String(value);
}

void saveOperations() {
  JsonDocument doc;
  JsonArray array = doc.to<JsonArray>();
  for (const auto &operation : operations) {
    JsonObject item = array.add<JsonObject>();
    item["sequence"] = operation.sequence;
    item["type"] = operation.type;
    item["syncId"] = operation.syncId;
    if (operation.title.length()) item["title"] = operation.title;
    if (operation.type == "setCompleted") item["completed"] = operation.completed;
  }
  String encoded;
  serializeJson(doc, encoded);
  preferences.putString("operations", encoded);
  preferences.putULong64("nextSeq", nextSequence);
}

void loadOperations() {
  nextSequence = preferences.getULong64("nextSeq", 1);
  String encoded = preferences.getString("operations", "[]");
  JsonDocument doc;
  if (deserializeJson(doc, encoded)) return;
  for (JsonObject item : doc.as<JsonArray>()) {
    Operation operation;
    operation.sequence = item["sequence"] | 0;
    operation.type = String(item["type"] | "");
    operation.syncId = String(item["syncId"] | "");
    operation.title = String(item["title"] | "");
    operation.completed = item["completed"] | false;
    operations.push_back(operation);
  }
}

void queueCreate(const String &title) {
  Operation operation;
  operation.sequence = nextSequence++;
  operation.type = "create";
  operation.syncId = newSyncId();
  operation.title = title;
  operations.push_back(operation);
  saveOperations();
}

String framePath(size_t index) {
  return "/frame" + String(index) + ".bin";
}

bool renderStoredFrame(size_t index) {
  File file = LittleFS.open(framePath(index), "r");
  if (!file || file.size() != DISPLAY_BYTES) return false;
  if (file.read(frameBuffer, DISPLAY_BYTES) != DISPLAY_BYTES) {
    file.close();
    return false;
  }
  file.close();
  renderFrame();
  return true;
}

void selectNextReminder() {
  if (reminderIds.size() < 2) return;
  selectedIndex = (selectedIndex + 1) % reminderIds.size();
  renderStoredFrame(selectedIndex);
}

void queueCompleteSelectedReminder() {
  if (reminderIds.empty() || selectedIndex >= reminderIds.size()) {
    Serial.println("BOOT double click ignored: no selected reminder");
    return;
  }
  Operation operation;
  operation.sequence = nextSequence++;
  operation.type = "setCompleted";
  operation.syncId = reminderIds[selectedIndex];
  operation.completed = true;
  operations.push_back(operation);
  saveOperations();
  Serial.printf("BOOT double click queued completion: %s\n", operation.syncId.c_str());
  if (reminderIds.size() > 1) {
    selectedIndex = (selectedIndex + 1) % reminderIds.size();
    renderStoredFrame(selectedIndex);
  }
}

void renderFrame() {
  display.setRotation(0);
  display.setFullWindow();
  display.firstPage();
  do {
    display.fillScreen(GxEPD_WHITE);
    // Protocol uses 1=black. Adafruit_GFX drawBitmap draws set bits in the supplied color.
    display.drawBitmap(0, 0, frameBuffer, DISPLAY_WIDTH, DISPLAY_HEIGHT, GxEPD_BLACK);
  } while (display.nextPage());
  display.hibernate();
}

void renderMessage(const String &line1, const String &line2 = "") {
  display.setRotation(0);
  display.setTextColor(GxEPD_BLACK);
  display.setFullWindow();
  display.firstPage();
  do {
    display.fillScreen(GxEPD_WHITE);
    display.setTextSize(3);
    display.setCursor(36, 100);
    display.print(line1);
    display.setTextSize(2);
    display.setCursor(36, 160);
    display.print(line2);
  } while (display.nextPage());
  display.hibernate();
}

String homePage() {
  String html = F("<!doctype html><html lang='zh-CN'><meta charset='utf-8'>"
                  "<meta name='viewport' content='width=device-width,initial-scale=1'>"
                  "<title>墨水屏提醒事项</title><style>body{font:17px -apple-system,sans-serif;"
                  "max-width:560px;margin:40px auto;padding:0 20px}input,button{box-sizing:border-box;"
                  "width:100%;font:inherit;padding:14px;margin:8px 0;border-radius:10px;border:1px solid #888}"
                  "button{background:#111;color:white}</style><h1>新增提醒事项</h1><form method='post' action='/new'>"
                  "<input name='title' maxlength='120' required placeholder='要提醒什么？'>"
                  "<button type='submit'>添加到 Apple 提醒事项</button></form><p>等待同步：");
  html += String(operations.size());
  html += F(" 项</p><p><a href='/api/status'>设备状态</a></p></html>");
  return html;
}

void configureRoutes() {
  const char *headerKeys[] = {"X-Page-Index"};
  server.collectHeaders(headerKeys, 1);

  server.on("/", HTTP_GET, [] { server.send(200, "text/html; charset=utf-8", homePage()); });
  server.on("/new", HTTP_POST, [] {
    String title = server.arg("title");
    title.trim();
    if (!title.length()) {
      server.send(400, "text/plain; charset=utf-8", "标题不能为空");
      return;
    }
    queueCreate(title);
    server.sendHeader("Location", "/");
    server.send(303);
  });

  server.on("/api/status", HTTP_GET, [] {
    JsonDocument doc;
    char id[17];
    snprintf(id, sizeof(id), "%016llx", ESP.getEfuseMac());
    doc["deviceId"] = id;
    doc["firmwareVersion"] = FIRMWARE_VERSION;
    doc["revision"] = snapshotRevision;
    doc["operationCount"] = operations.size();
    doc["selectedIndex"] = selectedIndex;
    doc["pageCount"] = reminderIds.size();
    doc["width"] = DISPLAY_WIDTH;
    doc["height"] = DISPLAY_HEIGHT;
    String body;
    serializeJson(doc, body);
    server.send(200, "application/json", body);
  });

  server.on("/api/snapshot", HTTP_POST, [] {
    JsonDocument doc;
    DeserializationError error = deserializeJson(doc, server.arg("plain"));
    if (error) {
      server.send(400, "application/json", "{\"error\":\"invalid_json\"}");
      return;
    }
    snapshotRevision = doc["revision"] | 0;
    reminderIds.clear();
    selectedIndex = 0;
    for (JsonObject reminder : doc["reminders"].as<JsonArray>()) {
      if (!(reminder["completed"] | false) && reminderIds.size() < 5)
        reminderIds.push_back(String(reminder["syncId"] | ""));
    }
    server.send(204);
  });

  server.on("/api/display", HTTP_POST, [] {
    if (displayUploadFile) displayUploadFile.close();
    if (displayUploadError == DisplayUploadError::invalidLength) {
      server.send(400, "application/json", "{\"error\":\"expected_38880_bytes\"}");
      return;
    }
    if (displayUploadError == DisplayUploadError::invalidIndex) {
      server.send(400, "application/json", "{\"error\":\"invalid_page_index\"}");
      return;
    }
    if (displayUploadError == DisplayUploadError::storage) {
      server.send(507, "application/json", "{\"error\":\"frame_storage_failed\"}");
      return;
    }
    if (displayUploadBytes != DISPLAY_BYTES) {
      server.send(400, "application/json", "{\"error\":\"expected_38880_bytes\"}");
      return;
    }
    server.send(202, "application/json", "{\"accepted\":true}");
    if (displayUploadIndex == 0) renderStoredFrame(0);
  }, [] {
    HTTPRaw &raw = server.raw();
    switch (raw.status) {
      case RAW_START: {
        if (displayUploadFile) displayUploadFile.close();
        displayUploadError = DisplayUploadError::none;
        displayUploadBytes = 0;
        displayUploadIndex = -1;

        if (server.clientContentLength() != DISPLAY_BYTES) {
          displayUploadError = DisplayUploadError::invalidLength;
          return;
        }
        if (!server.hasHeader("X-Page-Index")) {
          displayUploadError = DisplayUploadError::invalidIndex;
          return;
        }
        displayUploadIndex = server.header("X-Page-Index").toInt();
        if (displayUploadIndex < 0 || displayUploadIndex >= 5) {
          displayUploadError = DisplayUploadError::invalidIndex;
          return;
        }
        displayUploadFile = LittleFS.open(framePath(displayUploadIndex), "w");
        if (!displayUploadFile) displayUploadError = DisplayUploadError::storage;
        break;
      }
      case RAW_WRITE:
        if (displayUploadError != DisplayUploadError::none) return;
        if (!displayUploadFile || displayUploadFile.write(raw.buf, raw.currentSize) != raw.currentSize) {
          displayUploadError = DisplayUploadError::storage;
          return;
        }
        displayUploadBytes += raw.currentSize;
        break;
      case RAW_END:
        if (displayUploadFile) displayUploadFile.close();
        break;
      case RAW_ABORTED:
        if (displayUploadFile) displayUploadFile.close();
        displayUploadError = DisplayUploadError::storage;
        break;
    }
  });

  server.on("/api/operations", HTTP_GET, [] {
    const uint64_t after = strtoull(server.arg("after").c_str(), nullptr, 10);
    JsonDocument doc;
    JsonArray array = doc["operations"].to<JsonArray>();
    for (const auto &operation : operations) {
      if (operation.sequence <= after) continue;
      JsonObject item = array.add<JsonObject>();
      item["sequence"] = operation.sequence;
      item["type"] = operation.type;
      item["syncId"] = operation.syncId;
      if (operation.title.length()) item["title"] = operation.title;
      if (operation.type == "setCompleted") item["completed"] = operation.completed;
    }
    String body;
    serializeJson(doc, body);
    server.send(200, "application/json", body);
  });

  server.on("/api/operations/ack", HTTP_POST, [] {
    JsonDocument doc;
    if (deserializeJson(doc, server.arg("plain"))) {
      server.send(400, "application/json", "{\"error\":\"invalid_json\"}");
      return;
    }
    const uint64_t through = doc["through"] | 0;
    operations.erase(
      std::remove_if(operations.begin(), operations.end(), [through](const Operation &item) {
        return item.sequence <= through;
      }),
      operations.end()
    );
    saveOperations();
    server.send(204);
  });
}

void startConfigPortal() {
  renderMessage("Wi-Fi", "192.168.4.1");
  String apName = "EInk-Reminders-" + String(static_cast<uint32_t>(ESP.getEfuseMac()), HEX);
  wifiManager.startConfigPortal(apName.c_str());
  if (WiFi.status() == WL_CONNECTED) {
    renderMessage("Wi-Fi OK", WiFi.localIP().toString());
  }
}

void handleButton() {
  const bool pressed = digitalRead(PIN_BOOT_BUTTON) == LOW;
  const uint32_t now = millis();
  if (pressed && !buttonDown) {
    buttonDown = true;
    longPressHandled = false;
    buttonDownAt = now;
  }
  if (pressed && buttonDown && !longPressHandled && now - buttonDownAt >= 1200) {
    longPressHandled = true;
    pendingClicks = 0;
  }
  if (!pressed && buttonDown) {
    if (!longPressHandled && now - buttonDownAt >= MIN_BUTTON_PRESS_MS) {
      pendingClicks++;
      lastClickAt = now;
      if (pendingClicks > 3) pendingClicks = 3;
    }
    buttonDown = false;
  }
  if (!buttonDown && pendingClicks > 0 && now - lastClickAt > CLICK_SEQUENCE_TIMEOUT_MS) {
    const uint8_t clickCount = pendingClicks;
    pendingClicks = 0;
    if (clickCount == 1) selectNextReminder();
    else if (clickCount == 2) queueCompleteSelectedReminder();
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(PIN_BOOT_BUTTON, INPUT_PULLUP);
  preferences.begin("eink-reminders", false);
  loadOperations();
  if (!LittleFS.begin(true)) Serial.println("LittleFS mount failed");

  SPI.begin(PIN_EPD_SCK, -1, PIN_EPD_MOSI, PIN_EPD_CS);
  display.init(115200, true, 2, false);

  wifiManager.setTitle("墨水屏提醒事项");
  wifiManager.setCustomHeadElement(CONFIG_PORTAL_CHINESE_HEAD);
  wifiManager.setConfigPortalTimeout(180);
  String apName = "EInk-Reminders-" + String(static_cast<uint32_t>(ESP.getEfuseMac()), HEX);
  if (!wifiManager.autoConnect(apName.c_str())) {
    renderMessage("Wi-Fi", "192.168.4.1");
  } else {
    renderMessage("Wi-Fi OK", WiFi.localIP().toString());
  }

  MDNS.begin("reminder");
  MDNS.addService("http", "tcp", 80);
  configureRoutes();
  server.begin();
}

void loop() {
  server.handleClient();
  handleButton();
  delay(10);
}
