#include <algorithm>
#include <array>
#include <atomic>
#include <cctype>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

#include "cJSON.h"
#include "audio_codec.h"
#include "captive_dns.h"
#include "esp_event.h"
#include "esp_http_server.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_netif.h"
#include "esp_pm.h"
#include "esp_spiffs.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "mbedtls/base64.h"
#include "lwip/inet.h"
#include "lwip/sockets.h"
#include "nvs.h"
#include "nvs_flash.h"
#include "qrcode.h"
#include "zectrix_board.h"
#include "zectrix_demo_ui.h"
#include "zectrix_epd.h"
#include "zectrix_nfc.h"

namespace {

constexpr char kTag[] = "eink_reminders";
constexpr char kFirmwareVersion[] = "1.1.0-note4-view-test";
constexpr char kNfcRemindersUrl[] = "https://www.icloud.com.cn/reminders/";
constexpr uint8_t kNfcUrlVersion = 2;
constexpr int kAlertWidth = 280;
constexpr int kAlertHeight = 78;
constexpr size_t kAlertBytes = kAlertWidth * kAlertHeight / 8;
constexpr int kStandbyTextWidth = 112;
constexpr int kStandbyTextHeight = 22;
constexpr size_t kStandbyTextBytes = kStandbyTextWidth * kStandbyTextHeight / 8;
constexpr int kPhotoWidth = 184;
constexpr int kPhotoHeight = 216;
constexpr size_t kPhotoBytes = kPhotoWidth * kPhotoHeight / 8;
constexpr int kWeatherWidth = 190;
constexpr int kWeatherHeight = 140;
constexpr size_t kWeatherBytes = kWeatherWidth * kWeatherHeight / 8;
constexpr int kPhotoReminderWidth = 184;
constexpr int kPhotoReminderHeight = 22;
constexpr size_t kPhotoReminderBytes = kPhotoReminderWidth * kPhotoReminderHeight / 8;
constexpr int kSnoozeMenuWidth = 96;
constexpr int kSnoozeMenuHeight = 128;
constexpr size_t kSnoozeMenuFrameBytes = kSnoozeMenuWidth * kSnoozeMenuHeight / 8;
constexpr std::array<int, 5> kSnoozeMinutes = {5, 10, 15, 30, 60};
constexpr size_t kMaxBodyBytes = 512 * 1024;
constexpr size_t kInvalidIndex = static_cast<size_t>(-1);
constexpr char kNamespace[] = "eink-reminders";
constexpr TickType_t kSettingsTimeout = pdMS_TO_TICKS(30000);
constexpr TickType_t kSelectionTimeout = pdMS_TO_TICKS(30000);
constexpr size_t kPartialRefreshLimit = 8;
constexpr size_t kSettingsFrameCount = 50;
constexpr size_t kSettingsMenuCount = 12;
constexpr size_t kSettingsReturnFrame = 48;
constexpr size_t kSettingsStandbyInvertedFrame = 49;
constexpr size_t kViewPickerFrame = 11;
constexpr size_t kReminderPickerFrame = 39;
constexpr size_t kStandbySecondsFrame = 43;
constexpr size_t kStandbyHoursFrame = 45;
constexpr size_t kCalendarFrame = 47;
constexpr size_t kSyncDetailFrame = 15;
constexpr size_t kNetworkDetailFrame = 16;
constexpr size_t kDeviceDetailFrame = 17;
constexpr size_t kSyncRequestedFrame = 18;
constexpr size_t kRefreshCompleteFrame = 19;
constexpr size_t kCacheClearedFrame = 20;
constexpr size_t kSwitchingViewFrame = 21;
constexpr size_t kWifiConfirmFrame = 22;
constexpr size_t kRestartConfirmFrame = 24;
constexpr size_t kClearCacheConfirmFrame = 26;
constexpr size_t kFactoryResetConfirmFrame = 28;
constexpr size_t kWifiSetupFrame = 30;
constexpr size_t kWifiConnectingFrame = 31;
constexpr size_t kWifiConnectedFrame = 32;
constexpr size_t kNetworkReconfigureFrame = 33;
constexpr size_t kWifiReconnectingFrame = 34;
constexpr size_t kWifiReconnectSuccessFrame = 35;
constexpr size_t kWifiReconnectFailedFrame = 36;
constexpr size_t kWaitingForMacFrame = 37;
constexpr size_t kSwitchingNotesFrame = 38;
constexpr int kMoofDogWidth = 104;
constexpr int kMoofDogHeight = 83;
constexpr size_t kMoofDogFrameBytes = kMoofDogWidth * kMoofDogHeight / 8;
constexpr size_t kMoofDogFrameCount = 6;
constexpr TickType_t kMoofDogFrameInterval = pdMS_TO_TICKS(650);
constexpr size_t kEasterEggAnimationCount = 5;
constexpr size_t kAppleAnimationFrameCount = 6;
constexpr size_t kFullScreenFrameBytes = ZECTRIX_EPD_1BPP_FRAME_BYTES;
constexpr size_t kBigDigitFrameBytes = 80 * 176 / 8;
constexpr size_t kSmallDigitFrameBytes = 64 * 256 / 8;
constexpr TickType_t kAppleAnimationFrameInterval = pdMS_TO_TICKS(550);
constexpr char kCaptivePortalUri[] = "http://192.168.4.1/";

extern const uint8_t settings_frames_bin_start[] asm("_binary_settings_frames_bin_start");
extern const uint8_t settings_frames_bin_end[] asm("_binary_settings_frames_bin_end");
extern const uint8_t standby_digits_bin_start[] asm("_binary_standby_digits_bin_start");
extern const uint8_t standby_digits_bin_end[] asm("_binary_standby_digits_bin_end");
extern const uint8_t standby_clock_masks_bin_start[] asm("_binary_standby_clock_masks_bin_start");
extern const uint8_t standby_clock_masks_bin_end[] asm("_binary_standby_clock_masks_bin_end");
extern const uint8_t alert_sound_wav_start[] asm("_binary_alert_sound_wav_start");
extern const uint8_t alert_sound_wav_end[] asm("_binary_alert_sound_wav_end");
extern const uint8_t moof_dog_frames_bin_start[] asm("_binary_moof_dog_frames_bin_start");
extern const uint8_t moof_dog_frames_bin_end[] asm("_binary_moof_dog_frames_bin_end");
extern const uint8_t easter_egg_frames_bin_start[] asm("_binary_easter_egg_frames_bin_start");
extern const uint8_t easter_egg_frames_bin_end[] asm("_binary_easter_egg_frames_bin_end");
extern const uint8_t snooze_menu_frames_bin_start[] asm("_binary_snooze_menu_frames_bin_start");
extern const uint8_t snooze_menu_frames_bin_end[] asm("_binary_snooze_menu_frames_bin_end");
extern const uint8_t standby_default_photo_bin_start[] asm("_binary_standby_default_photo_bin_start");
extern const uint8_t standby_default_photo_bin_end[] asm("_binary_standby_default_photo_bin_end");

enum class UiMode : uint8_t {
    kReminders, kMenu, kViewPicker, kReminderPicker, kStandby, kCalendar,
    kNetworkMenu, kDetail, kMessage, kConfirm,
    kDogCow, kAlert
};
enum class ConfirmAction : uint8_t { kWifi, kRestart, kClearCache, kFactoryReset };
enum class ReminderView : uint8_t { kToday = 0, kNotes, kAll, kCompleted, kPlanned, kCalendar };
enum class WebAction : int {
    kNone = 0, kSync, kRefresh, kSetView, kReconnectWifi,
    kReconfigureWifi, kClearCache, kRestart, kFactoryReset
};

constexpr std::array<const char*, 6> kReminderViewNames = {
    "today", "notes", "all", "completed", "planned", "calendar"
};
constexpr std::array<ReminderView, 4> kReminderPickerViews = {
    ReminderView::kToday, ReminderView::kAll, ReminderView::kPlanned, ReminderView::kCompleted
};

struct Operation {
    uint64_t sequence = 0;
    std::string type;
    std::string sync_id;
    std::string apple_id;
    bool completed = false;
    int64_t due_at_epoch_ms = 0;
};

struct DueAlert {
    std::string sync_id;
    std::string apple_id;
    int64_t due_at_epoch_ms = 0;
    std::vector<uint8_t> bitmap;
    std::vector<uint8_t> standby_title_bitmap;
    std::vector<uint8_t> standby_due_bitmap;
    std::vector<uint8_t> photo_reminder_bitmap;
};

class ReminderApp {
public:
    void Run() {
        ESP_ERROR_CHECK(InitStorage());
        // Reliability takes precedence on NOTE4: keep the original always-on
        // CPU/button behaviour instead of dynamic frequency scaling or
        // automatic light sleep.
        // RTC is unused. NFC is powered only long enough to provision its
        // persistent passive tag, then both NFC and the shared audio/I2C rail
        // are switched off for standby.
        ESP_ERROR_CHECK(board_.Init(false, true));
        ConfigureNfcRemindersLink();
        zectrix_epd_config_t config = {};
        zectrix_epd_get_default_config(&config);
        ESP_ERROR_CHECK(zectrix_epd_new(&config, &epd_));
        ui_.SetEpd(epd_);
        LoadState();
        ConnectOrStartPortal();
        StartServer();
        if (!portal_active_ && !RenderIdleFrame()) RenderStoredFrame(0);

        ESP_LOGI(kTag, "ready: UP previous, DOWN next, OK complete, hold UP settings");
        while (true) {
            HandlePendingWebAction();
            MaintainWifiConnection();
            SendPendingMacWake();
            ZectrixButtonEvent event;
            if (!board_.WaitButton(&event, pdMS_TO_TICKS(500))) {
                CheckDueAlerts();
                if (ui_mode_ == UiMode::kDogCow) AdvanceDogCow();
                if (ui_mode_ == UiMode::kStandby) AdvanceStandby();
                if (ui_mode_ != UiMode::kReminders && ui_mode_ != UiMode::kAlert &&
                    ui_mode_ != UiMode::kDogCow && ui_mode_ != UiMode::kStandby &&
                    ui_mode_ != UiMode::kCalendar &&
                    xTaskGetTickCount() - settings_last_activity_ >= kSettingsTimeout) {
                    ExitSettings();
                }
                else if (ui_mode_ == UiMode::kReminders) HideSelectionIfIdle();
                continue;
            }
            if (event.button == ZectrixButton::kUp &&
                event.action == ZectrixButtonAction::kLongPress) {
                if (ui_mode_ == UiMode::kAlert) {
                    if (alert_delay_menu_open_) {
                        alert_delay_menu_open_ = false;
                        RenderAlertFrame();
                    }
                } else HandleSettingsBack();
                continue;
            }
            if (event.button == ZectrixButton::kOk &&
                event.action == ZectrixButtonAction::kLongPress &&
                active_view_ == ReminderView::kCalendar &&
                (ui_mode_ == UiMode::kReminders || ui_mode_ == UiMode::kCalendar)) {
                JumpCalendarToToday();
                continue;
            }
            // The QR setup screen ignores ordinary clicks, but settings must
            // remain reachable so a saved network can be retried without
            // scanning the code again. Once inside settings, normal button
            // navigation continues even while the captive portal is active.
            if (portal_active_ && ui_mode_ == UiMode::kReminders) continue;
            if (event.action != ZectrixButtonAction::kClick) continue;
            if (ui_mode_ == UiMode::kAlert) HandleAlertClick(event.button);
            else if (ui_mode_ != UiMode::kReminders) HandleSettingsClick(event.button);
            else HandleReminderClick(event.button);
        }
    }

private:
    void ConfigureNfcRemindersLink() {
        ZectrixNfc* nfc = board_.nfc();
        if (nfc == nullptr) {
            board_.SetAudioPower(false);
            return;
        }

        uint8_t stored_version = 0;
        nvs_handle_t nvs;
        const bool nvs_opened = nvs_open(kNamespace, NVS_READWRITE, &nvs) == ESP_OK;
        if (nvs_opened) nvs_get_u8(nvs, "nfcUrlV", &stored_version);
        if (stored_version != kNfcUrlVersion) {
            const esp_err_t result = nfc->WriteUriNdef(kNfcRemindersUrl);
            if (result == ESP_OK) {
                ESP_LOGI(kTag, "NFC link written: %s", kNfcRemindersUrl);
                if (nvs_opened) {
                    nvs_set_u8(nvs, "nfcUrlV", kNfcUrlVersion);
                    nvs_commit(nvs);
                }
            } else {
                ESP_LOGW(kTag, "could not write NFC reminder link: %s",
                         esp_err_to_name(result));
            }
        }
        if (nvs_opened) nvs_close(nvs);
        nfc->PowerOff();
        board_.SetAudioPower(false);
    }

    static ReminderApp* Instance(httpd_req_t* req) {
        return static_cast<ReminderApp*>(req->user_ctx);
    }
    static esp_err_t StatusHandler(httpd_req_t* req) { Instance(req)->MarkClientActivity(); return Instance(req)->SendStatus(req); }
    static esp_err_t SnapshotHandler(httpd_req_t* req) { Instance(req)->MarkClientActivity(); return Instance(req)->ReceiveSnapshot(req); }
    static esp_err_t DisplayHandler(httpd_req_t* req) { Instance(req)->MarkClientActivity(); return Instance(req)->ReceiveDisplay(req); }
    static esp_err_t OperationsHandler(httpd_req_t* req) { Instance(req)->MarkClientActivity(); return Instance(req)->SendOperations(req); }
    static esp_err_t AckHandler(httpd_req_t* req) { Instance(req)->MarkClientActivity(); return Instance(req)->Acknowledge(req); }
    static esp_err_t SyncAckHandler(httpd_req_t* req) { Instance(req)->MarkClientActivity(); return Instance(req)->AcknowledgeSync(req); }
    static esp_err_t HomeHandler(httpd_req_t* req) { return Instance(req)->SendHome(req); }
    static esp_err_t WifiHandler(httpd_req_t* req) { return Instance(req)->SaveWifi(req); }
    static esp_err_t WifiScanHandler(httpd_req_t* req) { return Instance(req)->ScanWifi(req); }
    static esp_err_t DeviceSettingsHandler(httpd_req_t* req) { return Instance(req)->SendDeviceSettings(req); }
    static esp_err_t DeviceActionHandler(httpd_req_t* req) { return Instance(req)->ReceiveDeviceAction(req); }
    static esp_err_t StandbyPhotoHandler(httpd_req_t* req) { return Instance(req)->ReceiveStandbyPhoto(req); }
    static esp_err_t StandbyLocationHandler(httpd_req_t* req) { return Instance(req)->ReceiveWeatherLocation(req); }
    static esp_err_t StandbyWeatherHandler(httpd_req_t* req) { return Instance(req)->ReceiveWeatherPatch(req); }
    static esp_err_t CaptiveRedirectHandler(httpd_req_t* req, httpd_err_code_t) {
        httpd_resp_set_status(req, "303 See Other");
        httpd_resp_set_hdr(req, "Location", kCaptivePortalUri);
        httpd_resp_set_type(req, "text/plain; charset=utf-8");
        return httpd_resp_sendstr(req, "正在打开 NOTE4 中文配网页面…");
    }
    static void RestartSoonTask(void*) {
        vTaskDelay(pdMS_TO_TICKS(4500));
        esp_restart();
    }

    static void AlertSoundTask(void* context) {
        auto* app = static_cast<ReminderApp*>(context);
        app->PlayEmbeddedAlertSound();
        app->alert_sound_playing_ = false;
        vTaskDelete(nullptr);
    }

    esp_err_t InitStorage() {
        esp_err_t err = nvs_flash_init();
        if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
            ESP_ERROR_CHECK(nvs_flash_erase());
            err = nvs_flash_init();
        }
        if (err != ESP_OK) return err;
        const esp_vfs_spiffs_conf_t config = {
            .base_path = "/spiffs", .partition_label = "storage",
            .max_files = 8, .format_if_mount_failed = true,
        };
        err = esp_vfs_spiffs_register(&config);
        if (err == ESP_OK) std::remove("/spiffs/upload.tmp");
        if (err == ESP_OK) {
            std::remove("/spiffs/photo.tmp");
            std::remove("/spiffs/weather.tmp");
        }
        return err;
    }

    static std::vector<uint8_t> ReadExactFile(const char* path, size_t length) {
        FILE* file = std::fopen(path, "rb");
        if (!file) return {};
        std::vector<uint8_t> bytes(length);
        const bool valid = std::fread(bytes.data(), 1, length, file) == length &&
            std::fgetc(file) == EOF;
        std::fclose(file);
        if (!valid) bytes.clear();
        return bytes;
    }

    static bool WriteExactFile(const char* temporary, const char* destination,
                               const std::vector<uint8_t>& bytes) {
        FILE* file = std::fopen(temporary, "wb");
        if (!file) return false;
        const bool written = std::fwrite(bytes.data(), 1, bytes.size(), file) == bytes.size() &&
            std::fflush(file) == 0;
        const bool closed = std::fclose(file) == 0;
        if (!written || !closed) { std::remove(temporary); return false; }
        // SPIFFS cannot replace an existing path with rename(). Keep the
        // previous complete image available until the replacement succeeds.
        const std::string backup = std::string(destination) + ".bak";
        std::remove(backup.c_str());
        const bool had_old = std::rename(destination, backup.c_str()) == 0;
        if (std::rename(temporary, destination) != 0) {
            if (had_old) std::rename(backup.c_str(), destination);
            std::remove(temporary);
            return false;
        }
        if (had_old) std::remove(backup.c_str());
        return true;
    }

    void LoadState() {
        photo_bitmap_ = ReadExactFile("/spiffs/photo.bin", kPhotoBytes);
        if (photo_bitmap_.empty())
            photo_bitmap_ = ReadExactFile("/spiffs/photo.bin.bak", kPhotoBytes);
        weather_bitmap_ = ReadExactFile("/spiffs/weather.bin", kWeatherBytes);
        if (weather_bitmap_.empty())
            weather_bitmap_ = ReadExactFile("/spiffs/weather.bin.bak", kWeatherBytes);
        // 重启后内存中的事项列表、到点提醒和时钟都已清空，屏幕却照常显示缓存的空闲画面。
        // 启动即请求同步，让 Mac 立即重建这些状态，而不是等到下一个同步周期。
        {
            std::lock_guard<std::mutex> lock(mutex_);
            MarkSyncRequestedLocked(0);
        }

        nvs_handle_t nvs;
        if (nvs_open(kNamespace, NVS_READONLY, &nvs) != ESP_OK) return;
        nvs_get_u64(nvs, "nextSeq", &next_sequence_);
        uint8_t view = 0;
        if (nvs_get_u8(nvs, "viewMode", &view) == ESP_OK && view < kReminderViewNames.size()) {
            active_view_ = static_cast<ReminderView>(view);
        }
        uint8_t standby_inverted = 0;
        if (nvs_get_u8(nvs, "standbyInvert", &standby_inverted) == ESP_OK) {
            standby_inverted_ = standby_inverted != 0;
        }
        char city[32] = {};
        size_t city_length = sizeof(city);
        if (nvs_get_str(nvs, "weatherCity", city, &city_length) == ESP_OK && city[0]) {
            weather_city_ = city;
        }
        nvs_get_i32(nvs, "weatherLat", &weather_latitude_e6_);
        nvs_get_i32(nvs, "weatherLon", &weather_longitude_e6_);
        nvs_get_u32(nvs, "weatherVer", &weather_location_version_);

        // 操作队列存在 blob "opsQueue"；没有时读取旧版本存下的 "operations" 字符串，
        // 下一次保存队列时迁移为 blob。两种读取都补上结尾的 '\0' 再交给 cJSON。
        std::vector<char> json;
        size_t length = 0;
        if (nvs_get_blob(nvs, "opsQueue", nullptr, &length) == ESP_OK && length > 0) {
            json.assign(length + 1, '\0');
            if (nvs_get_blob(nvs, "opsQueue", json.data(), &length) != ESP_OK) json.clear();
        } else if (nvs_get_str(nvs, "operations", nullptr, &length) == ESP_OK && length > 1) {
            json.assign(length, '\0');
            if (nvs_get_str(nvs, "operations", json.data(), &length) != ESP_OK) json.clear();
        }

        if (!json.empty()) {
            cJSON* root = cJSON_Parse(json.data());
            cJSON* item = nullptr;
            cJSON_ArrayForEach(item, root) {
                Operation operation;
                operation.sequence = Number(item, "sequence");
                operation.type = String(item, "type");
                operation.sync_id = String(item, "syncId");
                operation.apple_id = String(item, "appleId");
                operation.completed = Bool(item, "completed");
                operation.due_at_epoch_ms = static_cast<int64_t>(Number(item, "dueAtEpochMs"));
                if (!operation.type.empty() && !operation.sync_id.empty()) {
                    operations_.push_back(std::move(operation));
                }
            }
            cJSON_Delete(root);
        }

        nvs_close(nvs);
        if (next_sequence_ == 0) next_sequence_ = 1;
        LoadCachedItems();
    }

    void LoadCachedItems() {
        reminder_ids_.clear();
        reminder_apple_ids_.clear();
        FILE* file = std::fopen(CachedItemsPath().c_str(), "rb");
        if (!file) return;
        std::fseek(file, 0, SEEK_END);
        const long length = std::ftell(file);
        std::rewind(file);
        if (length <= 0 || length > 256 * 1024) { std::fclose(file); return; }
        std::vector<char> json(static_cast<size_t>(length) + 1, '\0');
        const bool loaded = std::fread(json.data(), 1, static_cast<size_t>(length), file) == static_cast<size_t>(length);
        std::fclose(file);
        if (!loaded) return;
        cJSON* root = cJSON_Parse(json.data());
        if (!cJSON_IsObject(root) || Number(root, "view") != static_cast<double>(active_view_)) {
            cJSON_Delete(root); return;
        }
        cJSON* items = cJSON_GetObjectItemCaseSensitive(root, "items");
        cJSON* item = nullptr;
        cJSON_ArrayForEach(item, items) {
            std::string id = String(item, "id");
            if (id.empty()) continue;
            reminder_ids_.push_back(std::move(id));
            reminder_apple_ids_.push_back(String(item, "apple"));
        }
        cJSON_Delete(root);
    }

    void SaveCachedItemsLocked() {
        cJSON* root = cJSON_CreateObject();
        cJSON_AddNumberToObject(root, "view", static_cast<int>(active_view_));
        cJSON* items = cJSON_AddArrayToObject(root, "items");
        for (size_t index = 0; index < reminder_ids_.size(); ++index) {
            cJSON* item = cJSON_CreateObject();
            cJSON_AddStringToObject(item, "id", reminder_ids_[index].c_str());
            if (index < reminder_apple_ids_.size() && !reminder_apple_ids_[index].empty())
                cJSON_AddStringToObject(item, "apple", reminder_apple_ids_[index].c_str());
            cJSON_AddItemToArray(items, item);
        }
        char* json = cJSON_PrintUnformatted(root);
        cJSON_Delete(root);
        if (!json) return;
        FILE* file = std::fopen(CachedItemsPath().c_str(), "wb");
        if (file) { std::fwrite(json, 1, std::strlen(json), file); std::fclose(file); }
        cJSON_free(json);
    }

    // 记录一次同步请求。每次请求分配新的序号，Mac 确认时只能清除自己读到的那一次。
    void MarkSyncRequestedLocked(int64_t requested_at_us) {
        sync_requested_ = true;
        sync_requested_at_us_ = requested_at_us;
        ++sync_request_id_;
        mac_wake_pending_.store(true);
    }

    void RequestMacWakeLocked() { mac_wake_pending_.store(true); }

    void SendPendingMacWake() {
        if (!mac_wake_pending_.exchange(false) || portal_active_) return;
        wifi_ap_record_t access_point = {};
        if (esp_wifi_sta_get_ap_info(&access_point) != ESP_OK) {
            // Keep the signal pending; MaintainWifiConnection will retry Wi-Fi.
            mac_wake_pending_.store(true);
            return;
        }
        const int socket_fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_IP);
        if (socket_fd < 0) return;
        int enabled = 1;
        setsockopt(socket_fd, SOL_SOCKET, SO_BROADCAST, &enabled, sizeof(enabled));
        sockaddr_in destination = {};
        destination.sin_family = AF_INET;
        destination.sin_port = htons(48271);
        destination.sin_addr.s_addr = htonl(INADDR_BROADCAST);
        constexpr char message[] = "EINK_NOTE4_EVENT v1.1";
        // Duplicate datagrams make a button event robust on sleepy Wi-Fi; the
        // Mac listener coalesces them via its single-flight guard.
        for (int attempt = 0; attempt < 2; ++attempt) {
            sendto(socket_fd, message, sizeof(message) - 1, 0,
                   reinterpret_cast<sockaddr*>(&destination), sizeof(destination));
            if (attempt == 0) vTaskDelay(pdMS_TO_TICKS(60));
        }
        close(socket_fd);
    }

    // 把操作队列写入 NVS，任何一步失败都返回 false。
    bool SaveOperationsLocked() {
        cJSON* root = cJSON_CreateArray();
        for (const auto& operation : operations_) {
            cJSON* item = cJSON_CreateObject();
            cJSON_AddNumberToObject(item, "sequence", static_cast<double>(operation.sequence));
            cJSON_AddStringToObject(item, "type", operation.type.c_str());
            cJSON_AddStringToObject(item, "syncId", operation.sync_id.c_str());
            if (!operation.apple_id.empty()) cJSON_AddStringToObject(item, "appleId", operation.apple_id.c_str());
            if (operation.type == "setCompleted") cJSON_AddBoolToObject(item, "completed", operation.completed);
            if (operation.type == "setDueAt") cJSON_AddNumberToObject(item, "dueAtEpochMs", static_cast<double>(operation.due_at_epoch_ms));
            cJSON_AddItemToArray(root, item);
        }
        char* json = cJSON_PrintUnformatted(root);
        cJSON_Delete(root);
        if (json == nullptr) return false;

        // 队列整体存为 blob：NVS 字符串上限 4000 字节，队列变长后会超出。
        // blob 首次写入成功后删除旧版本的 "operations" 字符串。
        nvs_handle_t nvs;
        esp_err_t err = nvs_open(kNamespace, NVS_READWRITE, &nvs);
        if (err == ESP_OK) {
            err = nvs_set_blob(nvs, "opsQueue", json, std::strlen(json));
            if (err == ESP_OK) err = nvs_set_u64(nvs, "nextSeq", next_sequence_);
            if (err == ESP_OK) {
                nvs_erase_key(nvs, "operations");
                err = nvs_commit(nvs);
            }
            nvs_close(nvs);
        }
        cJSON_free(json);

        if (err != ESP_OK) {
            ESP_LOGE(kTag, "could not save %u queued operations: %s",
                     static_cast<unsigned>(operations_.size()), esp_err_to_name(err));
        }
        return err == ESP_OK;
    }

    bool LoadWifi(std::string* ssid, std::string* password) {
        nvs_handle_t nvs;
        if (nvs_open(kNamespace, NVS_READONLY, &nvs) != ESP_OK) return false;
        std::array<char, 33> ssid_buffer = {};
        std::array<char, 65> password_buffer = {};
        size_t ssid_length = ssid_buffer.size();
        size_t password_length = password_buffer.size();
        const bool ok = nvs_get_str(nvs, "ssid", ssid_buffer.data(), &ssid_length) == ESP_OK;
        nvs_get_str(nvs, "password", password_buffer.data(), &password_length);
        nvs_close(nvs);
        if (!ok || ssid_buffer[0] == '\0') return false;
        *ssid = ssid_buffer.data();
        *password = password_buffer.data();
        return true;
    }

    bool ForcePortalRequested() {
        nvs_handle_t nvs;
        if (nvs_open(kNamespace, NVS_READONLY, &nvs) != ESP_OK) return false;
        uint8_t value = 0;
        nvs_get_u8(nvs, "forcePortal", &value);
        nvs_close(nvs);
        return value != 0;
    }

    bool SaveWifiCredentials(const std::string& ssid, const std::string& password) {
        nvs_handle_t nvs;
        if (nvs_open(kNamespace, NVS_READWRITE, &nvs) != ESP_OK) return false;
        const bool values_saved = nvs_set_str(nvs, "ssid", ssid.c_str()) == ESP_OK &&
            nvs_set_str(nvs, "password", password.c_str()) == ESP_OK;
        nvs_erase_key(nvs, "forcePortal");
        const bool saved = values_saved && nvs_commit(nvs) == ESP_OK;
        nvs_close(nvs);
        return saved;
    }

    bool WaitForStationAddress(char* address, size_t address_size, int attempts = 50) {
        for (int attempt = 0; attempt < attempts; ++attempt) {
            wifi_ap_record_t record = {};
            esp_netif_ip_info_t ip = {};
            if (esp_wifi_sta_get_ap_info(&record) == ESP_OK && station_netif_ &&
                esp_netif_get_ip_info(station_netif_, &ip) == ESP_OK && ip.ip.addr != 0) {
                std::snprintf(address, address_size, IPSTR, IP2STR(&ip.ip));
                return true;
            }
            vTaskDelay(pdMS_TO_TICKS(200));
        }
        return false;
    }

    void ConfigureCaptivePortalDiscovery() {
        if (!portal_netif_) return;
        const esp_err_t stopped = esp_netif_dhcps_stop(portal_netif_);
        if (stopped != ESP_OK && stopped != ESP_ERR_ESP_NETIF_DHCP_ALREADY_STOPPED) {
            ESP_LOGW(kTag, "could not pause DHCP server: %s", esp_err_to_name(stopped));
        }
        const esp_err_t option = esp_netif_dhcps_option(
            portal_netif_, ESP_NETIF_OP_SET, ESP_NETIF_CAPTIVEPORTAL_URI,
            const_cast<char*>(kCaptivePortalUri), std::strlen(kCaptivePortalUri));
        if (option != ESP_OK) {
            ESP_LOGW(kTag, "could not advertise captive portal: %s", esp_err_to_name(option));
        }
        const esp_err_t started = esp_netif_dhcps_start(portal_netif_);
        if (started != ESP_OK && started != ESP_ERR_ESP_NETIF_DHCP_ALREADY_STARTED) {
            ESP_LOGW(kTag, "could not restart DHCP server: %s", esp_err_to_name(started));
        }
        start_captive_dns_server("WIFI_AP_DEF");
    }

    void ConnectOrStartPortal() {
        ESP_ERROR_CHECK(esp_netif_init());
        const esp_err_t loop_error = esp_event_loop_create_default();
        if (loop_error != ESP_OK && loop_error != ESP_ERR_INVALID_STATE) ESP_ERROR_CHECK(loop_error);
        wifi_init_config_t init = WIFI_INIT_CONFIG_DEFAULT();
        ESP_ERROR_CHECK(esp_wifi_init(&init));
        std::string ssid;
        std::string password;
        const bool has_saved_wifi = LoadWifi(&ssid, &password);
        if (has_saved_wifi && !ForcePortalRequested()) {
            station_netif_ = esp_netif_create_default_wifi_sta();
            wifi_config_t station = {};
            std::strncpy(reinterpret_cast<char*>(station.sta.ssid), ssid.c_str(), sizeof(station.sta.ssid) - 1);
            std::strncpy(reinterpret_cast<char*>(station.sta.password), password.c_str(), sizeof(station.sta.password) - 1);
            station.sta.threshold.authmode = WIFI_AUTH_OPEN;
            ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
            ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &station));
            ESP_ERROR_CHECK(esp_wifi_start());
            // Modem sleep preserves the local HTTP bridge while allowing the
            // radio to rest between Mac polls and reminder uploads.
            ESP_ERROR_CHECK(esp_wifi_set_ps(WIFI_PS_MAX_MODEM));
            ESP_ERROR_CHECK(esp_wifi_connect());
            char address[20] = {};
            if (WaitForStationAddress(address, sizeof(address))) {
                ESP_LOGI(kTag, "Wi-Fi connected to %s at %s", ssid.c_str(), address);
                ShowWifiConnectedScreen(address);
                vTaskDelay(pdMS_TO_TICKS(1200));
                return;
            }
            // A saved network being temporarily unavailable is not a request
            // to provision again. Keep the previous reminder frame on screen
            // and retry in the background. The portal is reserved for first
            // boot or an explicit "重新配网" action from settings.
            wifi_recovery_pending_ = true;
            wifi_retry_delay_ms_ = 10000;
            wifi_retry_at_ = xTaskGetTickCount() + pdMS_TO_TICKS(wifi_retry_delay_ms_);
            ESP_LOGW(kTag, "saved Wi-Fi %s unavailable; retrying in background", ssid.c_str());
            RenderSettingsFrame(kWifiReconnectFailedFrame);
            return;
        }
        // AP+STA keeps the setup hotspot available while the station radio
        // scans nearby networks for the Chinese configuration page.
        if (station_netif_ == nullptr) station_netif_ = esp_netif_create_default_wifi_sta();
        portal_netif_ = esp_netif_create_default_wifi_ap();
        wifi_config_t access_point = {};
        uint8_t mac[6];
        esp_read_mac(mac, ESP_MAC_WIFI_SOFTAP);
        std::snprintf(reinterpret_cast<char*>(access_point.ap.ssid), sizeof(access_point.ap.ssid),
                      "EInk-Note4-%02X%02X", mac[4], mac[5]);
        access_point.ap.ssid_len = std::strlen(reinterpret_cast<char*>(access_point.ap.ssid));
        access_point.ap.channel = 1;
        access_point.ap.max_connection = 4;
        access_point.ap.authmode = WIFI_AUTH_OPEN;
        ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_APSTA));
        ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_AP, &access_point));
        ESP_ERROR_CHECK(esp_wifi_start());
        ESP_ERROR_CHECK(esp_wifi_set_ps(WIFI_PS_NONE));
        portal_active_ = true;
        portal_ssid_ = reinterpret_cast<const char*>(access_point.ap.ssid);
        ConfigureCaptivePortalDiscovery();
        ESP_LOGI(kTag, "configuration hotspot: %s / http://192.168.4.1",
                 reinterpret_cast<const char*>(access_point.ap.ssid));
        ShowWifiSetupScreen();
    }

    void MaintainWifiConnection() {
        if (portal_active_ || station_netif_ == nullptr) return;
        wifi_ap_record_t access_point = {};
        if (esp_wifi_sta_get_ap_info(&access_point) == ESP_OK) {
            if (!wifi_recovery_pending_) return;
            wifi_recovery_pending_ = false;
            wifi_retry_at_ = 0;
            wifi_retry_delay_ms_ = 10000;
            ESP_LOGI(kTag, "saved Wi-Fi reconnected in background");
            {
                std::lock_guard<std::mutex> lock(mutex_);
                MarkSyncRequestedLocked(0);
            }
            if (ui_mode_ == UiMode::kReminders && !RenderIdleFrame()) {
                RenderSettingsFrame(kSyncRequestedFrame);
            }
            return;
        }

        wifi_recovery_pending_ = true;
        const TickType_t now = xTaskGetTickCount();
        if (wifi_retry_at_ != 0 &&
            static_cast<int32_t>(now - wifi_retry_at_) < 0) return;
        const esp_err_t result = esp_wifi_connect();
        if (result != ESP_OK) {
            ESP_LOGD(kTag, "background Wi-Fi retry pending: %s", esp_err_to_name(result));
        }
        wifi_retry_at_ = now + pdMS_TO_TICKS(wifi_retry_delay_ms_);
        wifi_retry_delay_ms_ = std::min<uint32_t>(wifi_retry_delay_ms_ * 2, 300000);
    }

    void StartServer() {
        httpd_config_t config = HTTPD_DEFAULT_CONFIG();
        config.max_uri_handlers = 20;
        config.stack_size = 8192;
        ESP_ERROR_CHECK(httpd_start(&server_, &config));
        Register("/", HTTP_GET, HomeHandler);
        Register("/wifi", HTTP_POST, WifiHandler);
        Register("/api/wifi/scan", HTTP_GET, WifiScanHandler);
        Register("/api/device/settings", HTTP_GET, DeviceSettingsHandler);
        Register("/api/device/action", HTTP_POST, DeviceActionHandler);
        Register("/api/standby/photo", HTTP_POST, StandbyPhotoHandler);
        Register("/api/standby/location", HTTP_POST, StandbyLocationHandler);
        Register("/api/standby/weather", HTTP_POST, StandbyWeatherHandler);
        Register("/api/status", HTTP_GET, StatusHandler);
        Register("/api/snapshot", HTTP_POST, SnapshotHandler);
        Register("/api/display", HTTP_POST, DisplayHandler);
        Register("/api/operations", HTTP_GET, OperationsHandler);
        Register("/api/operations/ack", HTTP_POST, AckHandler);
        Register("/api/sync/ack", HTTP_POST, SyncAckHandler);
        ESP_ERROR_CHECK(httpd_register_err_handler(
            server_, HTTPD_404_NOT_FOUND, CaptiveRedirectHandler));
    }

    void Register(const char* uri, httpd_method_t method, esp_err_t (*handler)(httpd_req_t*)) {
        httpd_uri_t route = {};
        route.uri = uri; route.method = method; route.handler = handler; route.user_ctx = this;
        ESP_ERROR_CHECK(httpd_register_uri_handler(server_, &route));
    }

    esp_err_t SendHome(httpd_req_t* req) {
        if (!portal_active_) return SendControlHome(req);

        // 配网时通配 DNS 会把任意域名指向设备。用域名打开的配网页提交 Wi-Fi 时会被写接口的 Host 校验拒绝，
        // 先跳转到 IP 地址再显示页面。
        if (!HostIsIpv4(req)) return CaptiveRedirectHandler(req, HTTPD_404_NOT_FOUND);

        static constexpr char kPage[] = R"HTML(<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><meta name="theme-color" content="#f5f5f7"><title>墨水屏提醒事项 · 网络设置</title>
<style>
:root{color-scheme:light;font-family:-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif;color:#1d1d1f;background:#f5f5f7}*{box-sizing:border-box}body{max-width:520px;margin:0 auto;padding:calc(24px + env(safe-area-inset-top)) 16px calc(24px + env(safe-area-inset-bottom))}main{padding:24px;background:#fff;border-radius:22px;box-shadow:0 12px 38px #00000012}.brand{display:flex;align-items:center;gap:12px}.mark{width:46px;height:46px;padding:8px;border:1px solid #d2d2d7;border-radius:13px;background:#fff}.mark i{display:block;height:3px;margin:5px 0 0 15px;border-radius:2px;background:#1d1d1f}.mark i:before{content:'';display:block;width:7px;height:7px;margin-left:-14px;border:2px solid #1d1d1f;border-radius:50%}.mark i:nth-child(2):before{background:#1d1d1f;box-shadow:inset 0 0 0 2px #fff}h1{margin:0;font-size:27px;letter-spacing:-.02em}.intro{margin:9px 0 22px;color:#6e6e73;line-height:1.55}.step{margin:22px 0 10px;font-size:15px;font-weight:700}.networks{display:grid;gap:8px}.network,.secondary,.primary{width:100%;min-height:52px;border-radius:13px;font:inherit}.network{display:flex;justify-content:space-between;align-items:center;padding:0 14px;border:1px solid #d2d2d7;background:#fff;text-align:left}.network.selected{border:2px solid #1d1d1f;padding:0 13px;background:#f5f5f7}.network small{color:#6e6e73}.secondary{margin-top:10px;border:1px solid #d2d2d7;background:#fff;color:#1d1d1f;font-weight:600}.field{margin-top:18px}.field label{display:block;margin-bottom:7px;font-size:14px;font-weight:650}.password-row{position:relative}.password-row input{width:100%;height:52px;padding:0 76px 0 14px;border:1px solid #c7c7cc;border-radius:13px;font:inherit;font-size:16px}.reveal{position:absolute;right:5px;top:5px;width:66px;height:42px;border:0;background:transparent;color:#0066cc;font:inherit}.primary{margin-top:22px;border:0;background:#1d1d1f;color:#fff;font-weight:700}.primary:disabled,.secondary:disabled{opacity:.45}.status{min-height:22px;margin:12px 0 0;color:#6e6e73;font-size:14px;line-height:1.45}.error{color:#c5221f}.note{display:block;margin-top:20px;color:#86868b;font-size:12px;line-height:1.55}.success{text-align:center;padding:42px 0}.success h2{font-size:28px}.address{margin:20px 0;padding:14px;border-radius:12px;background:#f5f5f7;font:600 20px ui-monospace,SFMono-Regular,monospace}@media(max-width:360px){main{padding:20px}h1{font-size:24px}}
</style></head><body><main id="app"><div class="brand"><span class="mark" aria-hidden="true"><i></i><i></i><i></i></span><h1>墨水屏提醒事项</h1></div><p class="intro">为设备选择家里的 2.4 GHz Wi-Fi。连接成功后，即可通过 Mac 与 iPhone 上的 Apple 提醒事项双向联动。</p><form id="form"><div class="step">1　选择无线网络</div><div id="networks" class="networks" aria-live="polite"></div><button id="rescan" class="secondary" type="button">重新扫描</button><p id="scan-status" class="status">正在扫描附近网络…</p><input id="ssid" name="ssid" type="hidden"><div id="password-field" class="field" hidden><label for="password">2　输入 Wi-Fi 密码</label><div class="password-row"><input id="password" name="password" type="password" maxlength="64" autocomplete="current-password" placeholder="请输入密码"><button id="reveal" class="reveal" type="button">显示</button></div></div><button id="save" class="primary" type="submit" disabled>连接此 Wi-Fi</button><p id="result" class="status" role="status"></p></form><small class="note">只支持 2.4 GHz Wi-Fi。连接失败不会覆盖之前保存的网络，可以直接修改后重试。</small></main>
<script>
const app=document.querySelector('#app'),form=document.querySelector('#form'),networks=document.querySelector('#networks'),ssid=document.querySelector('#ssid'),passwordField=document.querySelector('#password-field'),password=document.querySelector('#password'),save=document.querySelector('#save'),rescan=document.querySelector('#rescan'),scanStatus=document.querySelector('#scan-status'),result=document.querySelector('#result'),reveal=document.querySelector('#reveal');let selectedSecure=false;
const strength=rssi=>rssi>=-55?'信号强':rssi>=-68?'信号良好':'信号较弱';
function selectNetwork(button,network){document.querySelectorAll('.network').forEach(item=>item.classList.remove('selected'));button.classList.add('selected');ssid.value=network.ssid;selectedSecure=network.secure;passwordField.hidden=!selectedSecure;password.required=selectedSecure;if(!selectedSecure)password.value='';save.disabled=false;result.textContent='';}
async function scan(){rescan.disabled=true;save.disabled=true;ssid.value='';passwordField.hidden=true;networks.replaceChildren();scanStatus.classList.remove('error');scanStatus.textContent='正在扫描附近网络…';try{const response=await fetch('/api/wifi/scan',{cache:'no-store'});if(!response.ok)throw new Error();const data=await response.json();for(const network of data.networks){const button=document.createElement('button');button.type='button';button.className='network';const name=document.createElement('span');name.textContent=network.ssid;const detail=document.createElement('small');detail.textContent=(network.secure?'需要密码 · ':'开放网络 · ')+strength(network.rssi);button.append(name,detail);button.addEventListener('click',()=>selectNetwork(button,network));networks.append(button)}scanStatus.textContent=data.networks.length?'找到 '+data.networks.length+' 个网络，请选择一个。':'没有找到网络，请靠近路由器后重新扫描。';}catch(error){scanStatus.classList.add('error');scanStatus.textContent='扫描失败，请点击“重新扫描”。';}finally{rescan.disabled=false}}
reveal.addEventListener('click',()=>{const showing=password.type==='text';password.type=showing?'password':'text';reveal.textContent=showing?'显示':'隐藏'});rescan.addEventListener('click',scan);
form.addEventListener('submit',async event=>{event.preventDefault();if(!ssid.value)return;save.disabled=true;rescan.disabled=true;result.classList.remove('error');result.textContent='正在验证网络和密码，请稍候…';try{const body=new URLSearchParams({ssid:ssid.value,password:selectedSecure?password.value:''});const response=await fetch('/wifi',{
method:'POST',
headers:{'Content-Type':'application/x-www-form-urlencoded','X-EInk-Reminders':'1'},
body
});const data=await response.json();if(!response.ok||!data.ok)throw new Error(data.message||'连接失败');app.innerHTML='<section class="success"><h2>Wi-Fi 已连接</h2><p>墨水屏提醒事项已成功连接家庭网络。</p><div class="address">'+data.ip+'</div><p>请在“墨水屏提醒事项”Mac App 中使用这个设备地址。设备即将自动重启。</p></section>';}catch(error){result.classList.add('error');result.textContent=error.message||'连接失败，请检查密码后重试。';save.disabled=false;rescan.disabled=false;}});
scan();
</script></body></html>)HTML";
        httpd_resp_set_type(req, "text/html; charset=utf-8");
        httpd_resp_set_hdr(req, "Cache-Control", "no-store");
        return httpd_resp_send(req, kPage, HTTPD_RESP_USE_STRLEN);
    }

    esp_err_t SendControlHome(httpd_req_t* req) {
        static constexpr char kPage[] = R"HTML(<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover,user-scalable=no"><meta name="theme-color" content="#f5f5f7"><title>墨水屏提醒事项</title>
<style>
:root{color-scheme:light;font-family:-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif;color:#1d1d1f;background:#f5f5f7}*{box-sizing:border-box}body{max-width:560px;margin:0 auto;padding:calc(18px + env(safe-area-inset-top)) 16px calc(30px + env(safe-area-inset-bottom))}header{display:flex;align-items:flex-end;justify-content:space-between;padding:8px 4px 22px}.identity{display:flex;align-items:center;gap:12px}.mini-mark{width:48px;height:48px;padding:7px;border:1px solid #d2d2d7;border-radius:14px;background:#fff}.mini-mark i{display:block;height:3px;margin:6px 0 0 16px;border-radius:2px;background:#1d1d1f}.mini-mark i:before{content:'';display:block;width:8px;height:8px;margin-left:-15px;border:2px solid #1d1d1f;border-radius:50%}.mini-mark i:nth-child(2):before{background:#1d1d1f;box-shadow:inset 0 0 0 2px #fff}h1{margin:0;font-size:30px;letter-spacing:-.04em}.connection{display:flex;align-items:center;gap:7px;color:#6e6e73;font-size:13px}.dot{width:9px;height:9px;border-radius:50%;background:#34c759}.dot.offline{background:#ff3b30}.card{margin-bottom:14px;padding:18px;background:#fff;border-radius:20px;box-shadow:0 5px 24px #0000000a}.card h2{margin:0 0 14px;font-size:17px}.views{display:grid;grid-template-columns:1fr 1fr;gap:10px}.view{position:relative;min-height:88px;padding:14px;border:1.5px solid transparent;border-radius:16px;background:#f2f2f7;color:#1d1d1f;text-align:left;font:inherit;font-weight:700}.view.active{border-color:#1d1d1f;background:#fff}.view strong{display:block;font-size:26px}.view span{font-size:15px}.rows{margin:-5px 0}.row{display:flex;align-items:center;justify-content:space-between;width:100%;min-height:52px;padding:0;border:0;border-bottom:1px solid #e5e5ea;background:transparent;color:#1d1d1f;text-align:left;font:inherit}.row:last-child{border-bottom:0}.row span:last-child{color:#6e6e73;font-size:13px}.row.danger{color:#d70015}.primary{display:block;width:100%;min-height:50px;margin-top:14px;padding:15px;border:0;border-radius:14px;background:#1d1d1f;color:#fff;text-align:center;text-decoration:none;font:inherit;font-weight:700}.primary:disabled,.row:disabled,.view:disabled{opacity:.42}.hint{margin:10px 0 0;color:#6e6e73;font-size:13px;line-height:1.5}.steps{margin:14px 0 0;padding-left:22px;color:#3a3a3c;font-size:14px;line-height:1.65}.toast{position:fixed;left:50%;bottom:calc(22px + env(safe-area-inset-bottom));transform:translateX(-50%) translateY(20px);padding:10px 16px;border-radius:99px;background:#1d1d1fee;color:#fff;font-size:14px;opacity:0;pointer-events:none;transition:.2s}.toast.show{opacity:1;transform:translateX(-50%) translateY(0)}@media(max-width:360px){.card{padding:15px}.view{min-height:80px}h1{font-size:25px}}
 .weather-form{display:flex;gap:8px}.weather-form input{min-width:0;flex:1;padding:12px;border:1px solid #d2d2d7;border-radius:10px;font:inherit}.weather-form button,.choice{padding:10px 14px;border:1px solid #d2d2d7;border-radius:10px;background:#fff;font:inherit}.choices{display:grid;gap:6px;margin-top:10px}.choice{text-align:left}.photo-input{display:block;width:100%;margin-top:14px;font:inherit}.photo-preview{display:none;width:184px;height:216px;margin:14px 0 0;border-radius:18px;background:#000;image-rendering:pixelated}
</style></head><body><header><div class="identity"><span class="mini-mark" aria-hidden="true"><i></i><i></i><i></i></span><div><h1>墨水屏提醒事项</h1><div id="address" class="hint">NOTE4 · 正在读取设备…</div></div></div><div class="connection"><i id="dot" class="dot"></i><span id="connection">已连接</span></div></header>
<main><section class="card"><h2>切换视图</h2><div class="views"><button class="view" data-view="today"><strong id="count-today">—</strong><span>今天</span></button><button class="view" data-view="notes"><strong id="count-notes">—</strong><span>备忘录</span></button><button class="view" data-view="all"><strong id="count-all">—</strong><span>全部</span></button><button class="view" data-view="planned"><strong id="count-planned">—</strong><span>计划</span></button><button class="view" data-view="completed"><strong>✓</strong><span>完成</span></button></div><button class="primary" data-action="sync">立即同步</button><p class="hint">切换后只读取当前视图；备忘录仅在进入时读取。</p></section>
<section class="card"><h2>屏幕与网络</h2><div class="rows"><button class="row" data-action="refresh"><span>刷新屏幕</span><span>全刷一次</span></button><button class="row" data-action="reconnectWifi"><span>重连 Wi-Fi</span><span id="wifi">—</span></button><button class="row" data-action="reconfigureWifi" data-confirm="设备将重启并显示配网二维码，继续吗？"><span>重新配网</span><span>保留旧密码</span></button></div></section>
<section class="card"><h2>第三款待机显示</h2><p class="hint">当前城市：<span id="weather-city">广州</span>。天气由 Mac App 获取，断网时保留上次成功的温度。</p><div class="weather-form"><input id="city-search" type="search" placeholder="搜索城市，例如广州" maxlength="40" aria-label="搜索天气城市"><button id="city-find" type="button">搜索</button></div><div id="city-choices" class="choices"></div><p class="hint">照片在手机上裁切并转为黑白点阵，原图不会上传。</p><input id="photo-input" class="photo-input" type="file" accept="image/*" aria-label="选择待机照片"><canvas id="photo-preview" class="photo-preview" width="184" height="216"></canvas><button id="photo-upload" class="primary" type="button" disabled>上传待机照片</button><p id="photo-state" class="hint">未选择图片</p><p class="hint">天气数据：<a href="https://open-meteo.com/" target="_blank" rel="noopener">Open-Meteo</a></p></section>
<section class="card"><h2>iPhone NFC 快捷设置</h2><p class="hint">先把配套指令添加到这台 iPhone，再用自己的 NOTE4 建立 NFC 自动化。</p><ol class="steps"><li>点下面按钮，在系统页面确认添加快捷指令。</li><li>进入“快捷指令 → 自动化”，新建“NFC”。</li><li>扫描这台 NOTE4；每台设备的 NFC 标识都不同。</li><li>选择“运行快捷指令”，选中刚添加的指令并设为“立即运行”。</li></ol><a class="primary" href="https://www.icloud.com/shortcuts/9e1448851dcd4903a9839d11b73126bf" target="_blank" rel="noopener">一键添加到 iPhone</a></section>
<section class="card"><h2>设备</h2><div class="rows"><div class="row"><span>固件版本</span><span id="firmware">—</span></div><div class="row"><span>电量</span><span id="battery">—</span></div><div class="row"><span>Mac 同步</span><span id="mac">—</span></div><button class="row" data-action="clearCache" data-confirm="清除画面缓存并重新同步吗？"><span>清除画面缓存</span><span>重新生成</span></button><button class="row" data-action="restart" data-confirm="确定要重启 NOTE4 吗？"><span>重启设备</span><span>约 10 秒</span></button><button class="row danger" data-action="factoryReset" data-confirm="这会清除 Wi-Fi、缓存和待同步操作，确定恢复出厂设置吗？"><span>恢复出厂设置</span><span>清除数据</span></button></div></section></main>
<div id="toast" class="toast" role="status"></div>
<script>
const q=s=>document.querySelector(s),qa=s=>document.querySelectorAll(s),toast=q('#toast');let toastTimer;
function say(message){toast.textContent=message;toast.classList.add('show');clearTimeout(toastTimer);toastTimer=setTimeout(()=>toast.classList.remove('show'),2200)}
function busy(value){qa('button[data-action],button[data-view]').forEach(button=>button.disabled=value)}
async function status(){try{const response=await fetch('/api/device/settings',{cache:'no-store'});if(!response.ok)throw new Error();const data=await response.json();q('#dot').classList.remove('offline');q('#connection').textContent='已连接';q('#address').textContent=data.ip||location.host;for(const name of ['today','notes','all','planned'])q('#count-'+name).textContent=data.viewCounts[name]??0;qa('[data-view]').forEach(button=>button.classList.toggle('active',button.dataset.view===data.view));q('#wifi').textContent=data.wifiConnected?(data.ssid+' · '+data.rssi+' dBm'):'未连接';q('#firmware').textContent=data.firmwareVersion;q('#battery').textContent=data.batteryValid?(data.batteryPercent+'%'):'读取中';q('#mac').textContent=data.macOnline?'在线':'未连接';}catch(error){q('#dot').classList.add('offline');q('#connection').textContent='连接中断'}}
async function act(action,view){busy(true);try{const response=await fetch('/api/device/action',{
method:'POST',
headers:{'Content-Type':'application/json','X-EInk-Reminders':'1'},
body:JSON.stringify({action,view})
});const data=await response.json();if(!response.ok)throw new Error(data.message||'操作失败');say(data.message||'操作已发送');setTimeout(status,900)}catch(error){say(error.message||'设备无响应')}finally{setTimeout(()=>busy(false),700)}}
qa('[data-view]').forEach(button=>button.addEventListener('click',()=>act('setView',button.dataset.view)));qa('[data-action]').forEach(button=>button.addEventListener('click',()=>{if(button.dataset.confirm&&!confirm(button.dataset.confirm))return;act(button.dataset.action)}));status();setInterval(()=>{if(!document.hidden)status()},15000);
async function standbyStatus(){try{const response=await fetch('/api/device/settings',{cache:'no-store'});const data=await response.json();q('#weather-city').textContent=data.weatherCity||'广州';if(!q('#photo-input').files.length)q('#photo-state').textContent=data.standbyPhotoCustomized?'已使用自定义照片':'使用内置默认图片'}catch(error){}}
standbyStatus();setInterval(()=>{if(!document.hidden)standbyStatus()},15000);
q('#city-find').addEventListener('click',async()=>{
const name=q('#city-search').value.trim();if(name.length<2){say('请输入至少两个字');return}
q('#city-choices').textContent='正在查找城市…';
try{const url='https://geocoding-api.open-meteo.com/v1/search?name='+encodeURIComponent(name)+'&count=5&language=zh&format=json';
const response=await fetch(url);if(!response.ok)throw new Error('城市搜索失败');const data=await response.json();q('#city-choices').replaceChildren();
for(const place of data.results||[]){const button=document.createElement('button');button.type='button';button.className='choice';button.textContent=[place.name,place.admin1,place.country].filter(Boolean).join(' · ');
button.addEventListener('click',async()=>{button.disabled=true;try{const saved=await fetch('/api/standby/location',{method:'POST',headers:{'Content-Type':'application/json','X-EInk-Reminders':'1'},body:JSON.stringify({city:place.name,latitude:place.latitude,longitude:place.longitude})});if(!saved.ok)throw new Error('保存城市失败');q('#city-choices').replaceChildren();say('已保存城市，等待 Mac 更新天气');standbyStatus()}catch(error){say(error.message)}finally{button.disabled=false}});q('#city-choices').append(button)}
if(!q('#city-choices').children.length)q('#city-choices').textContent='没有找到城市，请换个名称'}catch(error){q('#city-choices').textContent=error.message||'搜索失败，请检查手机网络'}});
let photoBytes=null;const photoCanvas=q('#photo-preview'),photoContext=photoCanvas.getContext('2d',{willReadFrequently:true});const matrix=[0,8,2,10,12,4,14,6,3,11,1,9,15,7,13,5];
q('#photo-input').addEventListener('change',async()=>{const file=q('#photo-input').files[0];q('#photo-upload').disabled=true;photoBytes=null;if(!file)return;
try{const url=URL.createObjectURL(file),image=new Image();image.src=url;await image.decode();const w=184,h=216,scale=Math.max(w/image.width,h/image.height),dw=image.width*scale,dh=image.height*scale;
photoContext.fillStyle='#000';photoContext.fillRect(0,0,w,h);photoContext.drawImage(image,(w-dw)/2,(h-dh)/2,dw,dh);URL.revokeObjectURL(url);
const pixels=photoContext.getImageData(0,0,w,h),bytes=new Uint8Array(w*h/8);
for(let y=0;y<h;y++)for(let x=0;x<w;x++){const i=y*w+x,j=i*4,cx=x<18?18:w-19,cy=y<18?18:h-19,inside=x>=18&&x<w-18||y>=18&&y<h-18||Math.hypot(x-cx,y-cy)<18;
let white=false;if(inside){const luminance=.2126*pixels.data[j]+.7152*pixels.data[j+1]+.0722*pixels.data[j+2],contrast=Math.max(0,Math.min(255,(luminance-105)*2.3));white=contrast>=(matrix[(y%4)*4+x%4]+.5)*16}
if(white)bytes[i>>3]|=128>>(i&7);pixels.data[j]=pixels.data[j+1]=pixels.data[j+2]=white?255:0;pixels.data[j+3]=255}
photoContext.putImageData(pixels,0,0);photoCanvas.style.display='block';photoBytes=bytes;q('#photo-upload').disabled=false;q('#photo-state').textContent='已转换为设备可用的黑白照片'}catch(error){q('#photo-state').textContent='图片处理失败，请换一张图片'}});
q('#photo-upload').addEventListener('click',async()=>{if(!photoBytes)return;q('#photo-upload').disabled=true;try{const response=await fetch('/api/standby/photo',{method:'POST',headers:{'Content-Type':'application/octet-stream','X-EInk-Reminders':'1'},body:photoBytes});if(!response.ok)throw new Error('上传失败');q('#photo-state').textContent='照片已保存到设备';say('待机照片已更新')}catch(error){say(error.message||'上传失败')}finally{q('#photo-upload').disabled=false}});
</script></body></html>)HTML";
        httpd_resp_set_type(req, "text/html; charset=utf-8");
        httpd_resp_set_hdr(req, "Cache-Control", "no-store");
        return httpd_resp_send(req, kPage, HTTPD_RESP_USE_STRLEN);
    }

    esp_err_t SendDeviceSettings(httpd_req_t* req) {
        if (portal_active_) return SendError(req, 409, "setup_portal_active");
        wifi_ap_record_t access_point = {};
        const bool wifi_connected = esp_wifi_sta_get_ap_info(&access_point) == ESP_OK;
        char address[20] = {};
        esp_netif_ip_info_t ip = {};
        if (station_netif_ && esp_netif_get_ip_info(station_netif_, &ip) == ESP_OK && ip.ip.addr != 0) {
            std::snprintf(address, sizeof(address), IPSTR, IP2STR(&ip.ip));
        }
        const ZectrixPowerSnapshot power = board_.ReadPowerSnapshot();
        const bool mac_online = IsMacOnline();

        std::lock_guard<std::mutex> lock(mutex_);
        cJSON* root = cJSON_CreateObject();
        cJSON_AddStringToObject(root, "firmwareVersion", kFirmwareVersion);
        cJSON_AddStringToObject(root, "view", kReminderViewNames[static_cast<size_t>(active_view_)]);
        cJSON* counts = cJSON_AddObjectToObject(root, "viewCounts");
        for (size_t index = 0; index < kReminderViewNames.size(); ++index) {
            cJSON_AddNumberToObject(counts, kReminderViewNames[index], view_counts_[index]);
        }
        cJSON_AddBoolToObject(root, "wifiConnected", wifi_connected);
        cJSON_AddStringToObject(root, "ssid", wifi_connected
            ? reinterpret_cast<const char*>(access_point.ssid) : "");
        cJSON_AddNumberToObject(root, "rssi", wifi_connected ? access_point.rssi : 0);
        cJSON_AddStringToObject(root, "ip", address);
        cJSON_AddBoolToObject(root, "batteryValid", power.battery_valid);
        cJSON_AddNumberToObject(root, "batteryPercent", power.battery_percent);
        cJSON_AddBoolToObject(root, "macOnline", mac_online);
        cJSON_AddStringToObject(root, "weatherCity", weather_city_.c_str());
        cJSON_AddNumberToObject(root, "weatherLatitude", weather_latitude_e6_ / 1000000.0);
        cJSON_AddNumberToObject(root, "weatherLongitude", weather_longitude_e6_ / 1000000.0);
        cJSON_AddNumberToObject(root, "weatherLocationVersion", weather_location_version_);
        cJSON_AddBoolToObject(root, "standbyPhotoCustomized", photo_bitmap_.size() == kPhotoBytes);
        cJSON_AddNumberToObject(root, "pendingOperations", operations_.size());
        cJSON_AddBoolToObject(root, "syncRequested", sync_requested_);
        httpd_resp_set_hdr(req, "Cache-Control", "no-store");
        return SendJson(req, root);
    }

    esp_err_t ReceiveStandbyPhoto(httpd_req_t* req) {
        if (!AcceptsWrite(req)) return SendError(req, 403, "forbidden");
        if (portal_active_) return SendError(req, 409, "setup_portal_active");
        if (req->content_len != kPhotoBytes) return SendError(req, 400, "expected_4968_bytes");
        std::string body;
        if (!ReadBody(req, &body, kPhotoBytes)) return SendError(req, 400, "upload_incomplete");
        std::vector<uint8_t> bitmap(body.begin(), body.end());
        if (!WriteExactFile("/spiffs/photo.tmp", "/spiffs/photo.bin", bitmap))
            return SendError(req, 507, "photo_storage_failed");
        {
            std::lock_guard<std::mutex> lock(mutex_);
            photo_bitmap_ = std::move(bitmap);
        }
        httpd_resp_set_type(req, "application/json");
        const esp_err_t sent = httpd_resp_sendstr(req, "{\"ok\":true}");
        if (ui_mode_ == UiMode::kStandby && standby_style_ == 2) RenderStandby(true);
        return sent;
    }

    esp_err_t ReceiveWeatherLocation(httpd_req_t* req) {
        if (!AcceptsWrite(req)) return SendError(req, 403, "forbidden");
        if (portal_active_) return SendError(req, 409, "setup_portal_active");
        std::string body;
        if (!ReadBody(req, &body, 256)) return SendError(req, 400, "invalid_location");
        cJSON* root = cJSON_ParseWithLength(body.data(), body.size());
        if (!cJSON_IsObject(root)) {
            cJSON_Delete(root);
            return SendError(req, 400, "invalid_location");
        }
        const std::string city = String(root, "city");
        const cJSON* lat = cJSON_GetObjectItemCaseSensitive(root, "latitude");
        const cJSON* lon = cJSON_GetObjectItemCaseSensitive(root, "longitude");
        if (city.empty() || city.size() > 30 || !cJSON_IsNumber(lat) || !cJSON_IsNumber(lon) ||
            !std::isfinite(lat->valuedouble) || !std::isfinite(lon->valuedouble) ||
            lat->valuedouble < -90 || lat->valuedouble > 90 ||
            lon->valuedouble < -180 || lon->valuedouble > 180) {
            cJSON_Delete(root);
            return SendError(req, 400, "invalid_location");
        }
        const int32_t latitude = static_cast<int32_t>(std::lround(lat->valuedouble * 1000000));
        const int32_t longitude = static_cast<int32_t>(std::lround(lon->valuedouble * 1000000));
        cJSON_Delete(root);
        nvs_handle_t nvs;
        if (nvs_open(kNamespace, NVS_READWRITE, &nvs) != ESP_OK)
            return SendError(req, 507, "location_storage_failed");
        const uint32_t version = weather_location_version_ + 1;
        const bool saved = nvs_set_str(nvs, "weatherCity", city.c_str()) == ESP_OK &&
            nvs_set_i32(nvs, "weatherLat", latitude) == ESP_OK &&
            nvs_set_i32(nvs, "weatherLon", longitude) == ESP_OK &&
            nvs_set_u32(nvs, "weatherVer", version) == ESP_OK &&
            nvs_commit(nvs) == ESP_OK;
        nvs_close(nvs);
        if (!saved) return SendError(req, 507, "location_storage_failed");
        {
            std::lock_guard<std::mutex> lock(mutex_);
            weather_city_ = city;
            weather_latitude_e6_ = latitude;
            weather_longitude_e6_ = longitude;
            weather_location_version_ = version;
            weather_bitmap_.clear();
            MarkSyncRequestedLocked(0);
        }
        std::remove("/spiffs/weather.bin");
        httpd_resp_set_type(req, "application/json");
        const esp_err_t sent = httpd_resp_sendstr(req, "{\"ok\":true}");
        if (ui_mode_ == UiMode::kStandby && standby_style_ == 2) RenderStandby(true);
        return sent;
    }

    esp_err_t ReceiveWeatherPatch(httpd_req_t* req) {
        if (!AcceptsWrite(req)) return SendError(req, 403, "forbidden");
        if (req->content_len != kWeatherBytes) return SendError(req, 400, "expected_3325_bytes");
        char version_text[16] = {};
        if (httpd_req_get_hdr_value_str(req, "X-Weather-Location-Version", version_text,
                                         sizeof(version_text)) != ESP_OK)
            return SendError(req, 400, "missing_location_version");
        const uint32_t version = static_cast<uint32_t>(std::strtoul(version_text, nullptr, 10));
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (version != weather_location_version_) return SendError(req, 409, "location_changed");
        }
        std::string body;
        if (!ReadBody(req, &body, kWeatherBytes)) return SendError(req, 400, "upload_incomplete");
        std::vector<uint8_t> bitmap(body.begin(), body.end());
        if (!WriteExactFile("/spiffs/weather.tmp", "/spiffs/weather.bin", bitmap))
            return SendError(req, 507, "weather_storage_failed");
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (version != weather_location_version_) return SendError(req, 409, "location_changed");
            weather_bitmap_ = std::move(bitmap);
        }
        httpd_resp_set_status(req, "204 No Content");
        const esp_err_t sent = httpd_resp_send(req, nullptr, 0);
        if (ui_mode_ == UiMode::kStandby && standby_style_ == 2) RenderStandby(true);
        return sent;
    }

    esp_err_t ReceiveDeviceAction(httpd_req_t* req) {
        if (!AcceptsWrite(req)) return SendError(req, 403, "forbidden");
        if (portal_active_) return SendError(req, 409, "setup_portal_active");
        std::string body;
        if (!ReadBody(req, &body, 768)) return SendError(req, 400, "invalid_json");
        cJSON* root = cJSON_ParseWithLength(body.data(), body.size());
        if (!cJSON_IsObject(root)) { cJSON_Delete(root); return SendError(req, 400, "invalid_json"); }
        const std::string action = String(root, "action");
        const std::string view = String(root, "view");
        WebAction requested = WebAction::kNone;
        const char* message = "操作已发送";
        if (action == "sync") { requested = WebAction::kSync; message = "正在同步"; }
        else if (action == "refresh") { requested = WebAction::kRefresh; message = "正在刷新屏幕"; }
        else if (action == "reconnectWifi") { requested = WebAction::kReconnectWifi; message = "正在重连 Wi-Fi"; }
        else if (action == "reconfigureWifi") { requested = WebAction::kReconfigureWifi; message = "正在进入配网模式"; }
        else if (action == "clearCache") { requested = WebAction::kClearCache; message = "正在清除缓存"; }
        else if (action == "restart") { requested = WebAction::kRestart; message = "正在重启设备"; }
        else if (action == "factoryReset") { requested = WebAction::kFactoryReset; message = "正在恢复出厂设置"; }
        else if (action == "setView") {
            requested = WebAction::kSetView;
            size_t index = 0;
            for (; index < kReminderViewNames.size(); ++index) {
                if (view == kReminderViewNames[index]) break;
            }
            if (index >= kReminderViewNames.size()) {
                cJSON_Delete(root);
                return SendError(req, 400, "invalid_view");
            }
            pending_web_view_ = static_cast<int>(index);
            message = index == static_cast<size_t>(ReminderView::kNotes)
                ? "正在切换备忘录" : "正在切换提醒事项";
        } else {
            cJSON_Delete(root);
            return SendError(req, 400, "invalid_action");
        }
        cJSON_Delete(root);
        int expected = static_cast<int>(WebAction::kNone);
        if (!pending_web_action_.compare_exchange_strong(expected, static_cast<int>(requested))) {
            httpd_resp_set_status(req, "409 Conflict");
            httpd_resp_set_type(req, "application/json; charset=utf-8");
            return httpd_resp_sendstr(req, "{\"ok\":false,\"message\":\"设备正在处理上一项操作\"}");
        }
        char response[128];
        std::snprintf(response, sizeof(response), "{\"ok\":true,\"message\":\"%s\"}", message);
        httpd_resp_set_status(req, "202 Accepted");
        httpd_resp_set_type(req, "application/json; charset=utf-8");
        httpd_resp_set_hdr(req, "Cache-Control", "no-store");
        return httpd_resp_sendstr(req, response);
    }

    esp_err_t ScanWifi(httpd_req_t* req) {
        if (!portal_active_ || portal_netif_ == nullptr) return SendError(req, 409, "setup_portal_inactive");
        wifi_scan_config_t scan = {};
        scan.show_hidden = false;
        scan.scan_type = WIFI_SCAN_TYPE_ACTIVE;
        const esp_err_t started = esp_wifi_scan_start(&scan, true);
        if (started != ESP_OK) return SendError(req, 503, "wifi_scan_failed");

        uint16_t count = 0;
        if (esp_wifi_scan_get_ap_num(&count) != ESP_OK) return SendError(req, 503, "wifi_scan_failed");
        count = std::min<uint16_t>(count, 24);
        std::vector<wifi_ap_record_t> records(count);
        if (count > 0 && esp_wifi_scan_get_ap_records(&count, records.data()) != ESP_OK) {
            return SendError(req, 503, "wifi_scan_failed");
        }
        std::sort(records.begin(), records.begin() + count,
                  [](const wifi_ap_record_t& lhs, const wifi_ap_record_t& rhs) {
                      return lhs.rssi > rhs.rssi;
                  });
        cJSON* root = cJSON_CreateObject();
        cJSON* networks = cJSON_AddArrayToObject(root, "networks");
        std::vector<std::string> seen;
        for (uint16_t index = 0; index < count; ++index) {
            const char* value = reinterpret_cast<const char*>(records[index].ssid);
            if (value[0] == '\0' || std::find(seen.begin(), seen.end(), value) != seen.end()) continue;
            seen.emplace_back(value);
            cJSON* network = cJSON_CreateObject();
            cJSON_AddStringToObject(network, "ssid", value);
            cJSON_AddNumberToObject(network, "rssi", records[index].rssi);
            cJSON_AddBoolToObject(network, "secure", records[index].authmode != WIFI_AUTH_OPEN);
            cJSON_AddItemToArray(networks, network);
        }
        httpd_resp_set_hdr(req, "Cache-Control", "no-store");
        return SendJson(req, root);
    }

    esp_err_t SaveWifi(httpd_req_t* req) {
        if (!AcceptsWrite(req)) return SendError(req, 403, "forbidden");
        if (!portal_active_ || station_netif_ == nullptr) {
            return SendError(req, 409, "setup_portal_inactive");
        }
        std::string body;
        if (!ReadBody(req, &body, 512)) return SendError(req, 400, "invalid_body");
        const std::string ssid = FormValue(body, "ssid");
        const std::string password = FormValue(body, "password");
        if (ssid.empty() || ssid.size() > 32 || password.size() > 64) return SendError(req, 400, "invalid_wifi_credentials");
        ShowWifiConnectingScreen(ssid.c_str());
        wifi_config_t station = {};
        std::strncpy(reinterpret_cast<char*>(station.sta.ssid), ssid.c_str(), sizeof(station.sta.ssid) - 1);
        std::strncpy(reinterpret_cast<char*>(station.sta.password), password.c_str(), sizeof(station.sta.password) - 1);
        station.sta.threshold.authmode = WIFI_AUTH_OPEN;
        esp_wifi_disconnect();
        vTaskDelay(pdMS_TO_TICKS(100));
        if (esp_wifi_set_config(WIFI_IF_STA, &station) != ESP_OK || esp_wifi_connect() != ESP_OK) {
            httpd_resp_set_status(req, "503 Service Unavailable");
            httpd_resp_set_type(req, "application/json; charset=utf-8");
            const esp_err_t sent = httpd_resp_sendstr(req, "{\"ok\":false,\"message\":\"无法开始连接，请重新扫描后再试。\"}");
            ShowWifiSetupScreen();
            return sent;
        }
        char address[20] = {};
        if (!WaitForStationAddress(address, sizeof(address), 40)) {
            esp_wifi_disconnect();
            httpd_resp_set_status(req, "422 Unprocessable Content");
            httpd_resp_set_type(req, "application/json; charset=utf-8");
            const esp_err_t sent = httpd_resp_sendstr(req, "{\"ok\":false,\"message\":\"连接失败，请检查 Wi-Fi 密码和信号。\"}");
            ShowWifiSetupScreen();
            return sent;
        }
        if (!SaveWifiCredentials(ssid, password)) {
            httpd_resp_set_status(req, "500 Internal Server Error");
            httpd_resp_set_type(req, "application/json; charset=utf-8");
            const esp_err_t sent = httpd_resp_sendstr(req, "{\"ok\":false,\"message\":\"网络已连接，但保存配置失败，请重试。\"}");
            ShowWifiSetupScreen();
            return sent;
        }
        char json[80];
        std::snprintf(json, sizeof(json), "{\"ok\":true,\"ip\":\"%s\"}", address);
        httpd_resp_set_type(req, "application/json; charset=utf-8");
        httpd_resp_set_hdr(req, "Cache-Control", "no-store");
        const esp_err_t sent = httpd_resp_sendstr(req, json);
        ShowWifiConnectedScreen(address);
        xTaskCreate(RestartSoonTask, "wifi_restart", 2048, nullptr, 5, nullptr);
        return sent;
    }

    esp_err_t SendStatus(httpd_req_t* req) {
        std::lock_guard<std::mutex> lock(mutex_);
        cJSON* root = cJSON_CreateObject();
        uint8_t mac[6];
        esp_read_mac(mac, ESP_MAC_WIFI_STA);
        char id[18];
        std::snprintf(id, sizeof(id), "%02x%02x%02x%02x%02x%02x", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
        cJSON_AddStringToObject(root, "deviceId", id);
        cJSON_AddStringToObject(root, "firmwareVersion", kFirmwareVersion);
        cJSON_AddNumberToObject(root, "revision", static_cast<double>(snapshot_revision_));
        cJSON_AddNumberToObject(root, "operationCount", operations_.size());
        cJSON_AddNumberToObject(root, "selectedIndex", selected_index_);
        cJSON_AddNumberToObject(root, "pageCount", reminder_ids_.size());
        cJSON_AddBoolToObject(root, "localCompletionPending", completion_latched_);
        cJSON_AddBoolToObject(root, "syncRequested", sync_requested_);
        cJSON_AddNumberToObject(root, "syncRequestId", static_cast<double>(sync_request_id_));
        cJSON_AddBoolToObject(root, "displayRequested", display_requested_);
        cJSON_AddBoolToObject(root, "noteDetail", note_detail_);
        cJSON_AddBoolToObject(root, "noteOpenRequested", note_open_requested_);
        cJSON_AddNumberToObject(root, "notePage", note_page_);
        cJSON_AddNumberToObject(root, "calendarMonthOffset", calendar_month_offset_);
        cJSON_AddNumberToObject(root, "calendarSelectedDay", calendar_selected_day_);
        cJSON_AddBoolToObject(root, "calendarSelectingDay", calendar_selecting_day_);
        cJSON_AddBoolToObject(root, "calendarDayDetail", calendar_day_detail_);
        cJSON_AddNumberToObject(root, "calendarDetailPage", calendar_detail_page_);
        cJSON_AddStringToObject(
            root, "view", kReminderViewNames[static_cast<size_t>(active_view_)]);
        const int64_t request_age_ms = sync_requested_ && sync_requested_at_us_ > 0
            ? std::max<int64_t>(0, (esp_timer_get_time() - sync_requested_at_us_) / 1000)
            : (sync_requested_ ? 900 : 0);
        cJSON_AddNumberToObject(root, "syncRequestAgeMs", static_cast<double>(request_age_ms));
        cJSON_AddNumberToObject(root, "width", ZECTRIX_EPD_PANEL_WIDTH);
        cJSON_AddNumberToObject(root, "height", ZECTRIX_EPD_PANEL_HEIGHT);
        cJSON_AddStringToObject(root, "pixelFormat", "1bpp-msb-1white");
        cJSON_AddStringToObject(root, "weatherCity", weather_city_.c_str());
        cJSON_AddNumberToObject(root, "weatherLatitude", weather_latitude_e6_ / 1000000.0);
        cJSON_AddNumberToObject(root, "weatherLongitude", weather_longitude_e6_ / 1000000.0);
        cJSON_AddNumberToObject(root, "weatherLocationVersion", weather_location_version_);
        return SendJson(req, root);
    }

    esp_err_t ReceiveSnapshot(httpd_req_t* req) {
        if (!AcceptsWrite(req)) return SendError(req, 403, "forbidden");
        std::string body;
        if (!ReadBody(req, &body, kMaxBodyBytes)) return SendError(req, 400, "invalid_json");
        cJSON* root = cJSON_ParseWithLength(body.data(), body.size());
        if (!cJSON_IsObject(root)) { cJSON_Delete(root); return SendError(req, 400, "invalid_json"); }
        const bool replace_display = Bool(root, "replaceDisplay");
        std::vector<DueAlert> incoming_alerts;
        cJSON* alert_items = cJSON_GetObjectItemCaseSensitive(root, "alerts");
        cJSON* alert_item = nullptr;
        cJSON_ArrayForEach(alert_item, alert_items) {
            if (incoming_alerts.size() >= 32) break;
            DueAlert alert;
            alert.sync_id = String(alert_item, "syncId");
            alert.apple_id = String(alert_item, "appleId");
            alert.due_at_epoch_ms = static_cast<int64_t>(Number(alert_item, "dueAtEpochMs"));
            const std::string encoded = String(alert_item, "bitmap");
            if (alert.sync_id.empty() || alert.due_at_epoch_ms <= 0 || encoded.empty()) continue;
            alert.bitmap.resize(kAlertBytes);
            size_t decoded = 0;
            if (mbedtls_base64_decode(alert.bitmap.data(), alert.bitmap.size(), &decoded,
                    reinterpret_cast<const unsigned char*>(encoded.data()), encoded.size()) != 0 ||
                decoded != kAlertBytes) continue;
            for (const auto& field : {
                    std::pair<const char*, std::vector<uint8_t>*>{"standbyTitleBitmap", &alert.standby_title_bitmap},
                    {"standbyDueBitmap", &alert.standby_due_bitmap}}) {
                const std::string label = String(alert_item, field.first);
                if (label.empty()) continue;
                field.second->resize(kStandbyTextBytes);
                size_t label_bytes = 0;
                if (mbedtls_base64_decode(field.second->data(), field.second->size(), &label_bytes,
                        reinterpret_cast<const unsigned char*>(label.data()), label.size()) != 0 ||
                    label_bytes != kStandbyTextBytes) field.second->clear();
            }
            const std::string photo_label = String(alert_item, "photoReminderBitmap");
            if (!photo_label.empty()) {
                alert.photo_reminder_bitmap.resize(kPhotoReminderBytes);
                size_t decoded_bytes = 0;
                if (mbedtls_base64_decode(alert.photo_reminder_bitmap.data(),
                        alert.photo_reminder_bitmap.size(), &decoded_bytes,
                        reinterpret_cast<const unsigned char*>(photo_label.data()),
                        photo_label.size()) != 0 || decoded_bytes != kPhotoReminderBytes)
                    alert.photo_reminder_bitmap.clear();
            }
            incoming_alerts.push_back(std::move(alert));
        }
        std::unique_lock<std::mutex> lock(mutex_);

        // 快照必须属于设备当前的视图：同步期间在设备上切换了视图时，拒绝旧视图的快照，
        // 否则旧视图的事项会被当作新视图显示。
        if (String(root, "view") != kReminderViewNames[static_cast<size_t>(active_view_)]) {
            cJSON_Delete(root);
            return SendError(req, 409, "view_mismatch");
        }

        bool refresh_standby = false;
        if (cJSON_IsArray(alert_items)) {
            refresh_standby = ui_mode_ == UiMode::kStandby &&
                !SameStandbyAlertContent(alerts_, incoming_alerts);
            alerts_ = std::move(incoming_alerts);
        }
        const int64_t sent_at_epoch_ms = static_cast<int64_t>(Number(root, "sentAtEpochMs"));
        if (sent_at_epoch_ms > 0) {
            clock_epoch_ms_ = sent_at_epoch_ms;
            clock_anchor_us_ = esp_timer_get_time();
        }
        if (cJSON_GetObjectItemCaseSensitive(root, "timeZoneOffsetMinutes")) {
            const int offset = static_cast<int>(Number(root, "timeZoneOffsetMinutes"));
            if (offset >= -840 && offset <= 840) time_zone_offset_minutes_ = offset;
        }
        const int day = static_cast<int>(Number(root, "todayDay"));
        if (day >= 1 && day <= 31) today_calendar_day_ = day;
        const int month = static_cast<int>(Number(root, "todayMonth"));
        const int year = static_cast<int>(Number(root, "todayYear"));
        if (month >= 1 && month <= 12 && year >= 2000 && year <= 2100) {
            today_calendar_month_ = month;
            today_calendar_year_ = year;
        }
        if (const cJSON* dates = cJSON_GetObjectItemCaseSensitive(root, "calendarDateKeys")) {
            if (cJSON_IsArray(dates)) {
                calendar_date_keys_.clear();
                cJSON* value = nullptr;
                cJSON_ArrayForEach(value, dates) {
                    if (calendar_date_keys_.size() >= 256) break;
                    if (cJSON_IsNumber(value)) calendar_date_keys_.push_back(value->valueint);
                }
            }
        }
        snapshot_revision_ = Number(root, "revision");
        if (const cJSON* counts = cJSON_GetObjectItemCaseSensitive(root, "viewCounts")) {
            view_counts_[0] = Number(counts, "today");
            view_counts_[1] = Number(counts, "notes");
            view_counts_[2] = Number(counts, "all");
            view_counts_[3] = Number(counts, "completed");
            view_counts_[4] = Number(counts, "planned");
        }
        if (cJSON_HasObjectItem(root, "currentViewCount")) {
            view_counts_[static_cast<size_t>(active_view_)] = Number(root, "currentViewCount");
        }
        reminder_ids_.clear();
        reminder_apple_ids_.clear();
        cJSON* reminders = cJSON_GetObjectItemCaseSensitive(root, "reminders");
        cJSON* item = nullptr;
        cJSON_ArrayForEach(item, reminders) {
            const bool completed = Bool(item, "completed");
            if (active_view_ != ReminderView::kNotes &&
                ((active_view_ == ReminderView::kCompleted) != completed)) continue;
            std::string id = String(item, "syncId");
            if (!id.empty()) {
                reminder_ids_.push_back(std::move(id));
                reminder_apple_ids_.push_back(String(item, "appleId"));
            }
        }
        SaveCachedItemsLocked();

        // 只有本轮会重传画面时才重置选中状态和帧缓存。只更新提醒或同步请求的快照不会重绘，
        // 屏幕上的选中背景和已缓存的帧仍然有效，重置会让下一次按键跳回第一项。
        if (replace_display) {
            selected_index_ = 0;
            selection_visible_ = false;
            idle_frame_received_since_snapshot_ = false;
            cached_frame_index_ = kInvalidIndex;
            confirmation_frame_index_ = kInvalidIndex;
            display_requested_ = !reminder_ids_.empty();
            note_detail_ = false;
            note_open_requested_ = false;
            note_page_ = 0;
            note_page_count_ = 1;
            std::remove(IdleFramePath().c_str());
            std::remove(FramePath().c_str());
            std::remove(ConfirmationFramePath().c_str());
        }
        lock.unlock();
        cJSON_Delete(root);
        httpd_resp_set_status(req, "204 No Content");
        const esp_err_t response = httpd_resp_send(req, nullptr, 0);
        if (refresh_standby) {
            bool still_standby = false;
            {
                std::lock_guard<std::mutex> mode_lock(mutex_);
                still_standby = ui_mode_ == UiMode::kStandby;
            }
            if (still_standby) RenderStandby(true);
        }
        return response;
    }

    esp_err_t ReceiveDisplay(httpd_req_t* req) {
        if (!AcceptsWrite(req)) return SendError(req, 403, "forbidden");
        if (req->content_len != ZECTRIX_EPD_1BPP_FRAME_BYTES) return SendError(req, 400, "expected_15000_bytes");
        char query[160] = {};
        char index_text[8] = {};
        char state_text[16] = {};
        char page_text[8] = {};
        char pages_text[8] = {};
        if (httpd_req_get_url_query_str(req, query, sizeof(query)) != ESP_OK ||
            httpd_query_key_value(query, "index", index_text, sizeof(index_text)) != ESP_OK) return SendError(req, 400, "invalid_page_index");
        const int index = std::atoi(index_text);
        if (index < 0) return SendError(req, 400, "invalid_page_index");
        const bool confirmation_state =
            httpd_query_key_value(query, "state", state_text, sizeof(state_text)) == ESP_OK &&
            (std::strcmp(state_text, "confirm") == 0 || std::strcmp(state_text, "local") == 0);
        const bool idle_state =
            httpd_query_key_value(query, "state", state_text, sizeof(state_text)) == ESP_OK &&
            std::strcmp(state_text, "idle") == 0;
        const bool note_state =
            httpd_query_key_value(query, "state", state_text, sizeof(state_text)) == ESP_OK &&
            std::strcmp(state_text, "note") == 0;
        const int note_page = httpd_query_key_value(query, "page", page_text, sizeof(page_text)) == ESP_OK
            ? std::max(0, std::atoi(page_text)) : 0;
        const int note_pages = httpd_query_key_value(query, "pages", pages_text, sizeof(pages_text)) == ESP_OK
            ? std::max(1, std::atoi(pages_text)) : 1;
        std::vector<uint8_t> frame(ZECTRIX_EPD_1BPP_FRAME_BYTES);
        size_t received = 0;
        while (received < frame.size()) {
            const int count = httpd_req_recv(req, reinterpret_cast<char*>(frame.data() + received), frame.size() - received);
            if (count <= 0) return SendError(req, 400, "upload_incomplete");
            received += count;
        }
        const std::string final_path = note_state ? NoteFramePath() :
            (idle_state ? IdleFramePath() :
            (confirmation_state ? ConfirmationFramePath() : FramePath()));
        // The complete frame is already buffered in RAM, so write it directly.
        // ESP-IDF SPIFFS may reject rename() even after the destination is
        // removed; that produced the repeated HTTP 507 on completed previews.
        FILE* file = std::fopen(final_path.c_str(), "wb");
        if (!file) {
            // Prefer truncating in place: deleting first can require a fresh
            // SPIFFS directory entry and fail on a fragmented nearly-full
            // volume. Retry once after removing the exact destination.
            std::remove(final_path.c_str());
            file = std::fopen(final_path.c_str(), "wb");
        }
        if (!file) return SendError(req, 507, "frame_storage_failed");
        const bool saved = std::fwrite(frame.data(), 1, frame.size(), file) == frame.size();
        std::fclose(file);
        if (!saved) {
            std::remove(final_path.c_str());
            return SendError(req, 507, "frame_storage_failed");
        }
        httpd_resp_set_status(req, "202 Accepted");
        httpd_resp_set_type(req, "application/json");
        httpd_resp_sendstr(req, "{\"accepted\":true}");
        if (note_state) {
            bool show_note = false;
            {
                std::lock_guard<std::mutex> lock(mutex_);
                note_detail_ = true;
                note_open_requested_ = false;
                note_page_ = static_cast<size_t>(note_page);
                note_page_count_ = static_cast<size_t>(note_pages);
                display_requested_ = false;
                show_note = ui_mode_ == UiMode::kReminders && active_view_ == ReminderView::kNotes;
            }
            if (show_note) RenderNoteFrame();
        } else if (idle_state) {
            bool show_reminders = false;
            {
                std::lock_guard<std::mutex> lock(mutex_);
                completion_latched_ = false;
                selection_visible_ = false;
                idle_frame_received_since_snapshot_ = true;
                show_reminders = ui_mode_ == UiMode::kReminders;
            }
            if (show_reminders) RenderIdleFrame();
        } else if (confirmation_state) {
            std::lock_guard<std::mutex> lock(mutex_);
            confirmation_frame_index_ = static_cast<size_t>(index);
        } else {
            bool show_frame = false;
            {
                std::lock_guard<std::mutex> lock(mutex_);
                cached_frame_index_ = static_cast<size_t>(index);
                if (selected_index_ == cached_frame_index_) display_requested_ = false;
                show_frame = ui_mode_ == UiMode::kReminders && selection_visible_ &&
                    selected_index_ == cached_frame_index_;
            }
            if (show_frame) RenderStoredFrame(static_cast<size_t>(index));
        }
        return ESP_OK;
    }

    esp_err_t SendOperations(httpd_req_t* req) {
        uint64_t after = 0;
        char query[64] = {};
        char after_text[24] = {};
        if (httpd_req_get_url_query_str(req, query, sizeof(query)) == ESP_OK &&
            httpd_query_key_value(query, "after", after_text, sizeof(after_text)) == ESP_OK) after = std::strtoull(after_text, nullptr, 10);
        std::lock_guard<std::mutex> lock(mutex_);
        cJSON* root = cJSON_CreateObject();
        cJSON* array = cJSON_AddArrayToObject(root, "operations");
        for (const auto& operation : operations_) {
            if (operation.sequence <= after) continue;
            cJSON* item = cJSON_CreateObject();
            cJSON_AddNumberToObject(item, "sequence", static_cast<double>(operation.sequence));
            cJSON_AddStringToObject(item, "type", operation.type.c_str());
            cJSON_AddStringToObject(item, "syncId", operation.sync_id.c_str());
            if (!operation.apple_id.empty()) cJSON_AddStringToObject(item, "appleId", operation.apple_id.c_str());
            cJSON_AddBoolToObject(item, "completed", operation.completed);
            if (operation.type == "setDueAt") cJSON_AddNumberToObject(item, "dueAtEpochMs", static_cast<double>(operation.due_at_epoch_ms));
            cJSON_AddItemToArray(array, item);
        }
        return SendJson(req, root);
    }

    esp_err_t Acknowledge(httpd_req_t* req) {
        if (!AcceptsWrite(req)) return SendError(req, 403, "forbidden");
        std::string body;
        if (!ReadBody(req, &body, 1024)) return SendError(req, 400, "invalid_json");
        cJSON* root = cJSON_ParseWithLength(body.data(), body.size());
        if (!cJSON_IsObject(root)) { cJSON_Delete(root); return SendError(req, 400, "invalid_json"); }
        const uint64_t through = Number(root, "through");
        cJSON_Delete(root);
        std::lock_guard<std::mutex> lock(mutex_);
        const bool acknowledged_completion = std::any_of(
            operations_.begin(), operations_.end(),
            [through](const Operation& item) {
                return item.sequence <= through && item.type == "setCompleted" && item.completed;
            });
        operations_.erase(std::remove_if(operations_.begin(), operations_.end(),
                          [through](const Operation& item) { return item.sequence <= through; }), operations_.end());
        if (acknowledged_completion) completion_latched_ = false;
        SaveOperationsLocked();
        httpd_resp_set_status(req, "204 No Content");
        return httpd_resp_send(req, nullptr, 0);
    }

    esp_err_t AcknowledgeSync(httpd_req_t* req) {
        if (!AcceptsWrite(req)) return SendError(req, 403, "forbidden");

        std::string body;
        if (!ReadBody(req, &body, 256)) return SendError(req, 400, "invalid_json");
        cJSON* root = cJSON_ParseWithLength(body.data(), body.size());
        if (!cJSON_IsObject(root)) {
            cJSON_Delete(root);
            return SendError(req, 400, "invalid_json");
        }
        const uint64_t request_id = Number(root, "requestId");
        cJSON_Delete(root);

        {
            // 只清除 Mac 同步开始时读到的那一次请求；同步期间设备产生的新请求序号更大，必须保留。
            std::lock_guard<std::mutex> lock(mutex_);
            if (request_id == sync_request_id_) {
                sync_requested_ = false;
                sync_requested_at_us_ = 0;
            }
        }
        httpd_resp_set_status(req, "204 No Content");
        return httpd_resp_send(req, nullptr, 0);
    }

    int64_t NowEpochMsLocked() const {
        return clock_epoch_ms_ > 0
            ? clock_epoch_ms_ + (esp_timer_get_time() - clock_anchor_us_) / 1000 : 0;
    }

    static std::string AlertKey(const DueAlert& alert) {
        return alert.sync_id + ":" + std::to_string(alert.due_at_epoch_ms);
    }

    static bool SameStandbyAlertContent(const std::vector<DueAlert>& left,
                                        const std::vector<DueAlert>& right) {
        return left.size() == right.size() &&
            std::equal(left.begin(), left.end(), right.begin(),
                [](const DueAlert& a, const DueAlert& b) {
                    return a.sync_id == b.sync_id &&
                        a.due_at_epoch_ms == b.due_at_epoch_ms &&
                        a.standby_title_bitmap == b.standby_title_bitmap &&
                        a.standby_due_bitmap == b.standby_due_bitmap &&
                        a.photo_reminder_bitmap == b.photo_reminder_bitmap;
                });
    }

    void CheckDueAlerts() {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (portal_active_ || (ui_mode_ != UiMode::kReminders &&
                ui_mode_ != UiMode::kStandby && ui_mode_ != UiMode::kCalendar)) return;
            const int64_t now = NowEpochMsLocked();
            if (now <= 0) return;
            for (const auto& alert : alerts_) {
                if (alert.due_at_epoch_ms > now ||
                    std::find(handled_alert_keys_.begin(), handled_alert_keys_.end(), AlertKey(alert)) != handled_alert_keys_.end()) continue;
                active_alert_ = alert;
                handled_alert_keys_.push_back(AlertKey(alert));
                if (handled_alert_keys_.size() > 64) handled_alert_keys_.erase(handled_alert_keys_.begin());
                alert_action_index_ = 0;
                alert_delay_menu_open_ = false;
                alert_delay_option_ = 0;
                alert_return_mode_ = ui_mode_;
                ui_mode_ = UiMode::kAlert;
                break;
            }
            if (ui_mode_ != UiMode::kAlert) return;
        }
        {
            std::lock_guard<std::mutex> display_lock(display_mutex_);
            alert_base_frame_ = current_frame_;
        }
        RenderAlertFrame();
        StartAlertSound();
    }

    static uint32_t ReadLe32(const uint8_t* value) {
        return static_cast<uint32_t>(value[0]) |
            (static_cast<uint32_t>(value[1]) << 8) |
            (static_cast<uint32_t>(value[2]) << 16) |
            (static_cast<uint32_t>(value[3]) << 24);
    }

    void StartAlertSound() {
        if (alert_sound_playing_.exchange(true)) return;
        if (xTaskCreate(AlertSoundTask, "reminder_sound", 4096, this, 4, nullptr) != pdPASS) {
            alert_sound_playing_ = false;
            ESP_LOGE(kTag, "could not start reminder sound task");
        }
    }

    void PlayEmbeddedAlertSound() {
        const uint8_t* wav = alert_sound_wav_start;
        const size_t wav_size = static_cast<size_t>(alert_sound_wav_end - alert_sound_wav_start);
        if (wav_size < 44 || std::memcmp(wav, "RIFF", 4) != 0 ||
            std::memcmp(wav + 8, "WAVE", 4) != 0) {
            ESP_LOGE(kTag, "embedded reminder sound is not PCM WAV");
            return;
        }
        const uint8_t* pcm = nullptr;
        size_t pcm_bytes = 0;
        for (size_t offset = 12; offset + 8 <= wav_size;) {
            const uint32_t chunk_size = ReadLe32(wav + offset + 4);
            const size_t data_offset = offset + 8;
            if (data_offset + chunk_size > wav_size) break;
            if (std::memcmp(wav + offset, "data", 4) == 0) {
                pcm = wav + data_offset;
                pcm_bytes = chunk_size;
                break;
            }
            offset = data_offset + chunk_size + (chunk_size & 1U);
        }
        if (pcm == nullptr || pcm_bytes < sizeof(int16_t)) {
            ESP_LOGE(kTag, "embedded reminder sound has no PCM payload");
            return;
        }

        AudioCodec* codec = board_.PrepareAudio();
        if (codec == nullptr || !codec->valid() || codec->output_sample_rate() != 16000) {
            ESP_LOGE(kTag, "NOTE4 audio codec is unavailable");
            board_.ReleaseAudio();
            return;
        }
        codec->SetOutputVolume(80);
        // Start() initializes duplex I2S for this board, but reminder playback
        // never needs the microphone/ADC path.
        codec->EnableInput(false);
        codec->EnableOutput(true);
        constexpr size_t kChunkSamples = 512;
        std::vector<int16_t> samples(kChunkSamples);
        size_t position = 0;
        while (position + sizeof(int16_t) <= pcm_bytes) {
            const size_t count = std::min(kChunkSamples, (pcm_bytes - position) / sizeof(int16_t));
            std::memcpy(samples.data(), pcm + position, count * sizeof(int16_t));
            if (count != samples.size()) samples.resize(count);
            // +10 dB = 3.162x amplitude. Saturation avoids integer wrap and
            // turns unavoidable peaks into controlled clipping rather than a
            // harsh digital overflow.
            constexpr float kAlertGain = 3.16227766f;
            for (int16_t& sample : samples) {
                const int32_t boosted = static_cast<int32_t>(static_cast<float>(sample) * kAlertGain);
                sample = static_cast<int16_t>(std::clamp<int32_t>(boosted, -32768, 32767));
            }
            codec->OutputData(samples);
            position += count * sizeof(int16_t);
        }
        vTaskDelay(pdMS_TO_TICKS(80));
        board_.ReleaseAudio();
        ESP_LOGI(kTag, "reminder sound played (%u samples)",
                 static_cast<unsigned>(pcm_bytes / sizeof(int16_t)));
    }

    void RenderAlertFrame() {
        DueAlert alert;
        size_t action = 0;
        bool delay_menu_open = false;
        size_t delay_option = 0;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (ui_mode_ != UiMode::kAlert) return;
            alert = active_alert_;
            action = alert_action_index_;
            delay_menu_open = alert_delay_menu_open_;
            delay_option = alert_delay_option_;
        }
        if (alert.bitmap.size() != kAlertBytes) return;
        // The ESP-IDF main task has a 3.5 KB stack. A native 400x300 canvas is
        // 15 KB; keeping it as a local object overflows that stack precisely
        // when a due alert opens and causes a reboot into the setup screen.
        // Keep a preallocated working image on the heap instead, so repeated
        // popup/selection redraws do not fragment free RAM.
        std::copy(alert_base_frame_.begin(), alert_base_frame_.end(), alert_render_frame_.begin());
        const auto pixel = [this](int x, int y, bool black) {
            if (x < 0 || x >= ZECTRIX_EPD_PANEL_WIDTH ||
                y < 0 || y >= ZECTRIX_EPD_PANEL_HEIGHT) return;
            uint8_t& byte = alert_render_frame_[static_cast<size_t>(y) * (ZECTRIX_EPD_PANEL_WIDTH / 8) + x / 8];
            const uint8_t mask = static_cast<uint8_t>(0x80U >> (x & 7));
            if (black) byte &= static_cast<uint8_t>(~mask);
            else byte |= mask;
        };
        constexpr int left = (ZECTRIX_EPD_PANEL_WIDTH - kAlertWidth) / 2;
        constexpr int top = 108; // x=50%, y=49%, width=70%, height=26%
        constexpr int radius = 20; // editor radius 30 scaled to native pixels
        const auto inside = [radius](int x, int y, int inset) {
            const int w = kAlertWidth - 2 * inset;
            const int h = kAlertHeight - 2 * inset;
            const int r = radius - inset;
            x -= inset; y -= inset;
            if (x < 0 || y < 0 || x >= w || y >= h) return false;
            const int cx = std::clamp(x, r, w - r - 1);
            const int cy = std::clamp(y, r, h - r - 1);
            const int dx = x - cx, dy = y - cy;
            return dx * dx + dy * dy <= r * r;
        };
        for (int y = 0; y < kAlertHeight; ++y) {
            for (int x = 0; x < kAlertWidth; ++x) {
                if (!inside(x, y, 0)) continue;
                pixel(left + x, top + y, !inside(x, y, 2));
            }
        }
        for (int y = 0; y < kAlertHeight; ++y) {
            for (int x = 0; x < kAlertWidth; ++x) {
                const size_t offset = static_cast<size_t>(y * kAlertWidth + x);
                if ((alert.bitmap[offset / 8] & (0x80 >> (offset % 8))) == 0) {
                    pixel(left + x, top + y, true);
                }
            }
        }
        // Clear controls embedded by older Mac versions, then draw the three
        // actions locally so selection works even while the Mac is offline.
        for (int y = top + 12; y < top + 73; ++y)
            for (int x = left + 175; x < left + 276; ++x) pixel(x, y, false);
        const auto line = [&pixel](int x0, int y0, int x1, int y1) {
            const int dx = std::abs(x1 - x0), sx = x0 < x1 ? 1 : -1;
            const int dy = -std::abs(y1 - y0), sy = y0 < y1 ? 1 : -1;
            int error = dx + dy;
            while (true) {
                pixel(x0, y0, true);
                if (x0 == x1 && y0 == y1) break;
                const int twice = 2 * error;
                if (twice >= dy) { error += dy; x0 += sx; }
                if (twice <= dx) { error += dx; y0 += sy; }
            }
        };
        constexpr std::array<int, 3> centers = {188, 220, 252};
        const int cy = top + 49;
        for (size_t index = 0; index < centers.size(); ++index) {
            const int cx = left + centers[index];
            for (int y = -17; y <= 17; ++y) {
                for (int x = -17; x <= 17; ++x) {
                    const int r2 = x * x + y * y;
                    if ((r2 >= 12 * 12 && r2 <= 13 * 13) ||
                        (index == action && r2 >= 16 * 16 && r2 <= 17 * 17))
                        pixel(cx + x, cy + y, true);
                }
            }
            if (index == 0) {
                for (int y = -6; y <= 6; ++y)
                    for (int x = -6; x <= 6; ++x) {
                        const int r2 = x * x + y * y;
                        if (r2 >= 5 * 5 && r2 <= 6 * 6)
                            pixel(cx + x, cy + y, true);
                    }
                line(cx, cy, cx, cy - 4);
                line(cx, cy, cx + 3, cy + 1);
                line(cx - 7, cy - 8, cx - 4, cy - 10);
                line(cx + 4, cy - 10, cx + 7, cy - 8);
            } else if (index == 1) {
                line(cx - 5, cy - 5, cx + 5, cy + 5);
                line(cx + 5, cy - 5, cx - 5, cy + 5);
            } else {
                line(cx - 6, cy, cx - 1, cy + 5);
                line(cx - 1, cy + 5, cx + 7, cy - 6);
            }
        }
        if (delay_menu_open) {
            const size_t bytes = static_cast<size_t>(
                snooze_menu_frames_bin_end - snooze_menu_frames_bin_start);
            const size_t offset = delay_option * kSnoozeMenuFrameBytes;
            if (bytes >= offset + kSnoozeMenuFrameBytes) {
                const uint8_t* menu = snooze_menu_frames_bin_start + offset;
                for (int y = 0; y < kSnoozeMenuHeight; ++y)
                    for (int x = 0; x < kSnoozeMenuWidth; ++x) {
                        const size_t bit = static_cast<size_t>(y) * kSnoozeMenuWidth + x;
                        pixel(200 + x, 14 + y,
                              (menu[bit / 8] & (0x80 >> (bit & 7))) == 0);
                    }
            }
        }
        RefreshFrame(alert_render_frame_.data());
    }

    void HandleAlertClick(ZectrixButton button) {
        if (button == ZectrixButton::kUp || button == ZectrixButton::kDown) {
            {
                std::lock_guard<std::mutex> lock(mutex_);
                const bool forward = button == ZectrixButton::kDown;
                if (alert_delay_menu_open_) {
                    alert_delay_option_ = (alert_delay_option_ +
                        (forward ? 1 : kSnoozeMinutes.size() - 1)) % kSnoozeMinutes.size();
                } else {
                    alert_action_index_ = (alert_action_index_ +
                        (forward ? 1 : 2)) % 3;
                }
            }
            RenderAlertFrame();
            return;
        }
        if (button != ZectrixButton::kOk) return;
        bool completed = false;
        bool dismissed = false;
        int snooze_minutes = 0;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (alert_action_index_ == 0 && !alert_delay_menu_open_) {
                alert_delay_menu_open_ = true;
                alert_delay_option_ = 0;
            } else if (alert_action_index_ == 0) {
                snooze_minutes = kSnoozeMinutes[alert_delay_option_];
            } else {
                dismissed = alert_action_index_ == 1;
                completed = alert_action_index_ == 2;
            }
        }
        if (alert_delay_menu_open_ && snooze_minutes == 0) {
            RenderAlertFrame();
            return;
        }
        if (dismissed) {
            {
                std::lock_guard<std::mutex> lock(mutex_);
                ui_mode_ = alert_return_mode_;
                selection_visible_ = false;
            }
            if (ui_mode_ == UiMode::kStandby) RenderStandby(true);
            else if (ui_mode_ == UiMode::kCalendar) RenderCalendar(true);
            else if (!RenderIdleFrame()) RefreshFrame(alert_base_frame_.data());
            ESP_LOGI(kTag, "alert dismissed without changing the reminder");
            return;
        }
        {
            std::lock_guard<std::mutex> lock(mutex_);
            Operation operation = {
                next_sequence_++, completed ? "setCompleted" : "setDueAt",
                active_alert_.sync_id, active_alert_.apple_id, completed
            };

            if (!completed) {
                // Align the chosen interval to a minute so Apple Reminders
                // and the device agree on the displayed snooze time.
                const int64_t later = NowEpochMsLocked() +
                    static_cast<int64_t>(snooze_minutes) * 60'000;
                operation.due_at_epoch_ms = ((later + 59'999) / 60'000) * 60'000;
            }

            operations_.push_back(operation);

            // 操作存不进 Flash 就不接受：回滚队列并保持弹窗，请求同步让 Mac 取走已排队的操作后再试。
            if (!SaveOperationsLocked()) {
                operations_.pop_back();
                --next_sequence_;
                MarkSyncRequestedLocked(0);
                return;
            }

            if (completed) {
                alerts_.erase(std::remove_if(alerts_.begin(), alerts_.end(),
                    [this](const DueAlert& item) { return item.sync_id == active_alert_.sync_id; }), alerts_.end());
                completion_latched_ = true;
                MarkSyncRequestedLocked(esp_timer_get_time());
            } else {
                alerts_.erase(std::remove_if(alerts_.begin(), alerts_.end(),
                    [this](const DueAlert& item) { return item.sync_id == active_alert_.sync_id; }), alerts_.end());
                active_alert_.due_at_epoch_ms = operation.due_at_epoch_ms;
                // The cached patch still spells the old due time. Until the
                // Mac returns a new pixel-font patch, use the device's local
                // date/time fallback so the snoozed time is visible now.
                active_alert_.standby_due_bitmap.clear();
                alerts_.push_back(active_alert_);
                MarkSyncRequestedLocked(esp_timer_get_time() - 5'000'000);
            }
            ui_mode_ = alert_return_mode_;
            selection_visible_ = false;
        }
        if (ui_mode_ == UiMode::kStandby) RenderStandby(true);
        else if (ui_mode_ == UiMode::kCalendar) RenderCalendar(true);
        else if (!RenderIdleFrame()) RefreshFrame(alert_base_frame_.data());
        ESP_LOGI(kTag, "alert action: %s %d minutes",
                 completed ? "complete" : "snooze", snooze_minutes);
    }

    void HandleReminderClick(ZectrixButton button) {
        if (active_view_ == ReminderView::kCalendar) {
            HandleCalendarClick(button);
            return;
        }
        if (active_view_ == ReminderView::kNotes && note_detail_) {
            HandleNoteDetailClick(button);
            return;
        }
        size_t page = 0;
        bool reveal_only = false;
        bool frame_ready = false;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            selection_last_activity_ = xTaskGetTickCount();
            if (reminder_ids_.empty()) {
                // 重启后还没收到快照时列表为空，只有 Mac 能重建。Mac 不在线时提示等待，
                // 并借用选中状态的超时：无操作 30 秒后照常回到空闲画面。
                if (IsMacOnline()) return;
                selection_visible_ = true;
                reveal_only = true;
            } else if (!selection_visible_) {
                selection_visible_ = true;
                page = std::min(selected_index_, reminder_ids_.size() - 1);
                reveal_only = true;
                frame_ready = cached_frame_index_ == page;
                if (!frame_ready) { display_requested_ = true; RequestMacWakeLocked(); }
            }
        }
        if (reveal_only) {
            if (frame_ready) RenderStoredFrame(page);
            else ShowWaitingForMacIfOffline();
            return;
        }
        if (button == ZectrixButton::kUp) SelectPrevious();
        else if (button == ZectrixButton::kDown) SelectNext();
        else if (button == ZectrixButton::kOk) {
            if (active_view_ == ReminderView::kNotes) OpenSelectedNote();
            else CompleteSelected();
        }
    }

    void HandleCalendarClick(ZectrixButton button) {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (calendar_day_detail_) {
                if (button == ZectrixButton::kOk) {
                    calendar_day_detail_ = false;
                    calendar_detail_page_ = 0;
                } else {
                    calendar_detail_page_ = std::max(0, calendar_detail_page_ +
                        (button == ZectrixButton::kDown ? 1 : -1));
                }
            } else if (button == ZectrixButton::kOk) {
                calendar_day_detail_ = true;
                calendar_detail_page_ = 0;
            } else {
                int month = today_calendar_month_ + calendar_month_offset_;
                int year = today_calendar_year_;
                while (month < 1) { month += 12; --year; }
                while (month > 12) { month -= 12; ++year; }
                const int last_day = year > 0 ? DaysInMonth(year, month) : 31;
                if (button == ZectrixButton::kDown && calendar_selected_day_ >= last_day) {
                    if (calendar_month_offset_ < 120) {
                        ++calendar_month_offset_;
                        calendar_selected_day_ = 1;
                    }
                } else if (button == ZectrixButton::kUp && calendar_selected_day_ <= 1) {
                    if (calendar_month_offset_ > -120) {
                        --calendar_month_offset_;
                        if (--month < 1) { month = 12; --year; }
                        calendar_selected_day_ = year > 0 ? DaysInMonth(year, month) : 31;
                    }
                } else {
                    calendar_selected_day_ += button == ZectrixButton::kDown ? 1 : -1;
                }
                calendar_selecting_day_ = true;
            }
            MarkSyncRequestedLocked(0);
            RequestMacWakeLocked();
        }
    }

    void JumpCalendarToToday() {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            calendar_month_offset_ = 0;
            calendar_selected_day_ = today_calendar_day_ > 0 ? today_calendar_day_ : 1;
            calendar_selecting_day_ = true;
            calendar_day_detail_ = false;
            calendar_detail_page_ = 0;
            MarkSyncRequestedLocked(0);
        }
        if (ui_mode_ == UiMode::kCalendar) RenderCalendar();
    }

    void OpenSelectedNote() {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (reminder_ids_.empty() || selected_index_ >= reminder_ids_.size()) return;
            note_open_requested_ = true;
            note_page_ = 0;
            RequestMacWakeLocked();
        }
        ShowWaitingForMacIfOffline();
    }

    void HandleNoteDetailClick(ZectrixButton button) {
        bool return_to_list = false;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (button == ZectrixButton::kOk) {
                note_detail_ = false;
                note_open_requested_ = false;
                return_to_list = true;
            } else if (button == ZectrixButton::kUp || button == ZectrixButton::kDown) {
                if (note_page_count_ == 0) note_page_count_ = 1;
                if (button == ZectrixButton::kDown) note_page_ = (note_page_ + 1) % note_page_count_;
                else note_page_ = (note_page_ + note_page_count_ - 1) % note_page_count_;
                note_open_requested_ = true;
                RequestMacWakeLocked();
            }
        }
        if (return_to_list) {
            if (!RenderStoredFrame(selected_index_)) RenderIdleFrame();
        } else {
            // Keep the last cached detail visible while the next page arrives.
            RenderNoteFrame();
        }
    }

    void HideSelectionIfIdle() {
        bool should_hide = false;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            // The timeout only hides the dotted selection in a list. A note
            // detail is a reading screen and must remain visible indefinitely;
            // rendering the idle frame here used to throw the reader back to
            // the Notes directory after kSelectionTimeout.
            if (active_view_ == ReminderView::kNotes && note_detail_) return;
            if (selection_visible_ &&
                xTaskGetTickCount() - selection_last_activity_ >= kSelectionTimeout) {
                selection_visible_ = false;
                should_hide = true;
            }
        }
        if (should_hide && !RenderIdleFrame()) {
            ESP_LOGW(kTag, "idle frame unavailable; selection remains visually unchanged");
        }
    }

    // 按键需要的画面只能由 Mac 生成。Mac 不在线时显示等待提示，避免按键没有任何反馈。
    void ShowWaitingForMacIfOffline() {
        if (!IsMacOnline()) RenderSettingsFrame(kWaitingForMacFrame);
    }

    void SelectPrevious() {
        size_t page;
        bool frame_ready;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (reminder_ids_.empty()) return;
            if (!MoveToAvailableLocked(-1)) return;
            page = selected_index_;
            frame_ready = cached_frame_index_ == page;
            if (!frame_ready) { display_requested_ = true; RequestMacWakeLocked(); }
        }
        if (frame_ready) RenderStoredFrame(page);
        else ShowWaitingForMacIfOffline();
    }
    void SelectNext() {
        size_t page;
        bool frame_ready;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (reminder_ids_.empty()) return;
            if (!MoveToAvailableLocked(1)) return;
            page = selected_index_;
            frame_ready = cached_frame_index_ == page;
            if (!frame_ready) { display_requested_ = true; RequestMacWakeLocked(); }
        }
        if (frame_ready) RenderStoredFrame(page);
        else ShowWaitingForMacIfOffline();
    }
    void CompleteSelected() {
        size_t confirmed_page = 0;
        bool preview_ready = false;
        bool waiting_for_mac = false;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (active_view_ == ReminderView::kCompleted || active_view_ == ReminderView::kNotes) return;
            if (reminder_ids_.empty() || selected_index_ >= reminder_ids_.size()) return;
            if (confirmation_frame_index_ != selected_index_) {
                display_requested_ = true;
                RequestMacWakeLocked();
                waiting_for_mac = true;
            } else {
                confirmed_page = selected_index_;
                const std::string& selected_id = reminder_ids_[selected_index_];
                const bool already_queued = std::any_of(
                    operations_.begin(), operations_.end(),
                    [&selected_id](const Operation& item) {
                        return item.type == "setCompleted" &&
                               item.sync_id == selected_id &&
                               item.completed;
                    });
                if (already_queued) return;

                const std::string apple_id = selected_index_ < reminder_apple_ids_.size()
                    ? reminder_apple_ids_[selected_index_] : "";
                Operation operation = {
                    next_sequence_++,
                    "setCompleted",
                    selected_id,
                    apple_id,
                    true
                };
                operations_.push_back(operation);

                // 操作存不进 Flash 就不接受这次完成：回滚队列，并请求同步让 Mac 取走已排队的操作，
                // 不显示一个断电后会丢失的完成状态。
                if (!SaveOperationsLocked()) {
                    operations_.pop_back();
                    --next_sequence_;
                    MarkSyncRequestedLocked(0);
                    waiting_for_mac = true;
                } else {
                    completion_latched_ = true;

                    // A short Mac-side debounce keeps the final removal inside
                    // 1–2 seconds while still coalescing rapid confirmations.
                    MarkSyncRequestedLocked(esp_timer_get_time());
                    MoveToAvailableLocked(1);
                    cached_frame_index_ = kInvalidIndex;
                    confirmation_frame_index_ = kInvalidIndex;
                    display_requested_ = true;
                    RequestMacWakeLocked();
                    preview_ready = true;
                    ESP_LOGI(kTag, "queued completion for %s", operation.sync_id.c_str());
                }
            }
        }

        if (waiting_for_mac) {
            ShowWaitingForMacIfOffline();
            return;
        }

        // The Mac keeps one predicted confirmation frame ready for the current
        // selection. This gives immediate local feedback without storing an
        // exponential set of completion combinations on flash.
        if (preview_ready && !RenderConfirmationFrame()) {
            ESP_LOGE(kTag, "confirmation preview selected=%u unavailable; sync remains enabled",
                     static_cast<unsigned>(confirmed_page));
            std::lock_guard<std::mutex> lock(mutex_);
            completion_latched_ = false;
        }
        board_.SetPowerLed(true);
        vTaskDelay(pdMS_TO_TICKS(120));
        board_.SetPowerLed(false);
    }

    bool HasQueuedCompletionLocked(size_t index) const {
        if (index >= reminder_ids_.size()) return true;
        const std::string& id = reminder_ids_[index];
        return std::any_of(operations_.begin(), operations_.end(),
                           [&id](const Operation& item) {
                               return item.type == "setCompleted" &&
                                      item.sync_id == id && item.completed;
                           });
    }

    bool MoveToAvailableLocked(int direction) {
        const size_t count = reminder_ids_.size();
        if (count == 0) return false;
        for (size_t offset = 1; offset <= count; ++offset) {
            const size_t candidate = direction > 0
                ? (selected_index_ + offset) % count
                : (selected_index_ + count - (offset % count)) % count;
            if (!HasQueuedCompletionLocked(candidate)) {
                selected_index_ = candidate;
                return true;
            }
        }
        return false;
    }

    bool RenderStoredFrame(size_t index) {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (cached_frame_index_ != index) return false;
        }
        FILE* file = std::fopen(FramePath().c_str(), "rb");
        if (!file) return false;
        std::vector<uint8_t> frame(ZECTRIX_EPD_1BPP_FRAME_BYTES);
        const bool loaded = std::fread(frame.data(), 1, frame.size(), file) == frame.size();
        std::fclose(file);
        if (!loaded) return false;
        return RefreshFrame(frame.data());
    }
    bool RenderConfirmationFrame() {
        FILE* file = std::fopen(ConfirmationFramePath().c_str(), "rb");
        if (!file) return false;
        std::vector<uint8_t> frame(ZECTRIX_EPD_1BPP_FRAME_BYTES);
        const bool loaded = std::fread(frame.data(), 1, frame.size(), file) == frame.size();
        std::fclose(file);
        if (!loaded) return false;
        return RefreshFrame(frame.data());
    }
    bool RenderNoteFrame() {
        FILE* file = std::fopen(NoteFramePath().c_str(), "rb");
        if (!file) return false;
        std::vector<uint8_t> frame(ZECTRIX_EPD_1BPP_FRAME_BYTES);
        const bool loaded = std::fread(frame.data(), 1, frame.size(), file) == frame.size();
        std::fclose(file);
        return loaded && RefreshFrame(frame.data());
    }
    bool RenderIdleFrame(bool force_full = false) {
        FILE* file = std::fopen(IdleFramePath().c_str(), "rb");
        if (!file) return false;
        std::vector<uint8_t> frame(ZECTRIX_EPD_1BPP_FRAME_BYTES);
        const bool loaded = std::fread(frame.data(), 1, frame.size(), file) == frame.size();
        std::fclose(file);
        if (!loaded) return false;
        return RefreshFrame(frame.data(), force_full);
    }
    void RenderWhite() {
        std::vector<uint8_t> white(ZECTRIX_EPD_1BPP_FRAME_BYTES, 0xFF);
        RefreshFrame(white.data(), true);
    }

    bool RefreshFrame(const uint8_t* frame, bool force_full = false) {
        if (!frame) return false;
        std::lock_guard<std::mutex> display_lock(display_mutex_);
        return RefreshFrameLocked(frame, force_full);
    }

    bool RefreshFrameLocked(const uint8_t* frame, bool force_full = false) {
        constexpr int kStride = ZECTRIX_EPD_PANEL_WIDTH / 8;
        int min_byte = kStride;
        int max_byte = -1;
        int min_y = ZECTRIX_EPD_PANEL_HEIGHT;
        int max_y = -1;
        if (current_frame_valid_) {
            for (int y = 0; y < ZECTRIX_EPD_PANEL_HEIGHT; ++y) {
                for (int byte = 0; byte < kStride; ++byte) {
                    const size_t offset = static_cast<size_t>(y) * kStride + byte;
                    if (current_frame_[offset] == frame[offset]) continue;
                    min_byte = std::min(min_byte, byte);
                    max_byte = std::max(max_byte, byte);
                    min_y = std::min(min_y, y);
                    max_y = std::max(max_y, y);
                }
            }
        }
        // A manual refresh must run the full waveform even if the pixels are
        // identical to the current frame; otherwise "刷新屏幕" does nothing.
        if (current_frame_valid_ && max_byte < 0 && !force_full) return true;

        const int rect_width = max_byte >= 0 ? (max_byte - min_byte + 1) * 8 : 0;
        const int rect_height = max_y >= 0 ? max_y - min_y + 1 : 0;
        const int changed_area = rect_width * rect_height;
        const int panel_area = ZECTRIX_EPD_PANEL_WIDTH * ZECTRIX_EPD_PANEL_HEIGHT;
        const size_t partial_limit = ui_mode_ == UiMode::kDogCow ? 48 : kPartialRefreshLimit;
        const bool use_partial = !force_full && current_frame_valid_ &&
            partial_refresh_count_ < partial_limit &&
            changed_area > 0 && changed_area * 100 <= panel_area * 65;

        esp_err_t err = zectrix_epd_power_on(epd_);
        if (err != ESP_OK) return false;
        if (use_partial) {
            const int row_bytes = rect_width / 8;
            std::vector<uint8_t> patch(static_cast<size_t>(row_bytes) * rect_height);
            for (int row = 0; row < rect_height; ++row) {
                const uint8_t* source = frame +
                    static_cast<size_t>(min_y + row) * kStride + min_byte;
                std::memcpy(patch.data() + static_cast<size_t>(row) * row_bytes,
                            source, row_bytes);
            }
            const zectrix_epd_rect_t rect = {
                .x = min_byte * 8,
                .y = min_y,
                .width = rect_width,
                .height = rect_height,
            };
            err = zectrix_epd_refresh_partial_1bpp(epd_, &rect, patch.data(), patch.size());
        } else {
            err = zectrix_epd_refresh_full_1bpp(
                epd_, frame, ZECTRIX_EPD_1BPP_FRAME_BYTES);
        }
        zectrix_epd_power_off(epd_);

        // If the fast waveform failed, immediately restore a trustworthy full
        // base. This keeps later partial updates safe and avoids a stuck UI.
        if (err != ESP_OK && use_partial && zectrix_epd_power_on(epd_) == ESP_OK) {
            err = zectrix_epd_refresh_full_1bpp(
                epd_, frame, ZECTRIX_EPD_1BPP_FRAME_BYTES);
            zectrix_epd_power_off(epd_);
            partial_refresh_count_ = 0;
        } else if (err == ESP_OK && use_partial) {
            ++partial_refresh_count_;
        } else if (err == ESP_OK) {
            partial_refresh_count_ = 0;
        }
        if (err == ESP_OK) {
            current_frame_.assign(frame, frame + ZECTRIX_EPD_1BPP_FRAME_BYTES);
            current_frame_valid_ = true;
        } else {
            current_frame_valid_ = false;
        }
        return err == ESP_OK;
    }

    static void DrawSetupQr(esp_qrcode_handle_t qrcode, void* user_data) {
        auto* canvas = static_cast<ZectrixCanvas*>(user_data);
        if (!canvas) return;
        const int size = esp_qrcode_get_size(qrcode);
        constexpr int quiet_zone = 4;
        const int scale = std::max(3, std::min(4, 168 / (size + quiet_zone * 2)));
        const int extent = (size + quiet_zone * 2) * scale;
        const int left = (ZECTRIX_EPD_PANEL_WIDTH - extent) / 2;
        constexpr int top = 45;
        canvas->FillRect(left, top, extent, extent, false);
        for (int y = 0; y < size; ++y) {
            for (int x = 0; x < size; ++x) {
                if (esp_qrcode_get_module(qrcode, x, y)) {
                    canvas->FillRect(
                        left + (x + quiet_zone) * scale,
                        top + (y + quiet_zone) * scale,
                        scale, scale, true);
                }
            }
        }
    }

    void ShowWifiSetupScreen() {
        std::lock_guard<std::mutex> display_lock(display_mutex_);
        ZectrixCanvas& canvas = ui_.canvas();
        const size_t bytes = static_cast<size_t>(settings_frames_bin_end - settings_frames_bin_start);
        if (bytes < (kWifiSetupFrame + 1) * ZECTRIX_EPD_1BPP_FRAME_BYTES) return;
        std::memcpy(canvas.data(),
                    settings_frames_bin_start + kWifiSetupFrame * ZECTRIX_EPD_1BPP_FRAME_BYTES,
                    ZECTRIX_EPD_1BPP_FRAME_BYTES);
        const std::string payload = "WIFI:T:nopass;S:" + portal_ssid_ + ";;";
        esp_qrcode_config_t qr_config = ESP_QRCODE_CONFIG_DEFAULT();
        qr_config.display_func_with_cb = DrawSetupQr;
        qr_config.user_data = &canvas;
        qr_config.max_qrcode_version = 5;
        qr_config.qrcode_ecc_level = ESP_QRCODE_ECC_QUART;
        if (esp_qrcode_generate(&qr_config, payload.c_str()) != ESP_OK) {
            ESP_LOGE(kTag, "failed to generate Wi-Fi QR code");
        }
        canvas.TextCentered(214, portal_ssid_.c_str());
        RefreshFrameLocked(canvas.data(), true);
    }

    void ShowWifiConnectingScreen(const char* ssid) {
        std::lock_guard<std::mutex> display_lock(display_mutex_);
        ZectrixCanvas& canvas = ui_.canvas();
        const size_t bytes = static_cast<size_t>(settings_frames_bin_end - settings_frames_bin_start);
        if (bytes < (kWifiConnectingFrame + 1) * ZECTRIX_EPD_1BPP_FRAME_BYTES) return;
        std::memcpy(canvas.data(),
                    settings_frames_bin_start + kWifiConnectingFrame * ZECTRIX_EPD_1BPP_FRAME_BYTES,
                    ZECTRIX_EPD_1BPP_FRAME_BYTES);
        canvas.TextCentered(176, ssid);
        RefreshFrameLocked(canvas.data(), true);
    }

    void ShowWifiConnectedScreen(const char* address) {
        std::lock_guard<std::mutex> display_lock(display_mutex_);
        ZectrixCanvas& canvas = ui_.canvas();
        const size_t bytes = static_cast<size_t>(settings_frames_bin_end - settings_frames_bin_start);
        if (bytes < (kWifiConnectedFrame + 1) * ZECTRIX_EPD_1BPP_FRAME_BYTES) return;
        std::memcpy(canvas.data(),
                    settings_frames_bin_start + kWifiConnectedFrame * ZECTRIX_EPD_1BPP_FRAME_BYTES,
                    ZECTRIX_EPD_1BPP_FRAME_BYTES);
        canvas.TextCentered(151, address, 2);
        RefreshFrameLocked(canvas.data(), true);
    }

    void MarkClientActivity() { last_client_activity_us_.store(esp_timer_get_time()); }

    // v1.1 uses event wakeups rather than one-second polling. Recent traffic
    // remains a useful hint, but must not expire after only ten idle seconds.
    bool IsMacOnline() const {
        const int64_t last_activity_us = last_client_activity_us_.load();
        return last_activity_us != 0 && esp_timer_get_time() - last_activity_us < 600000000;
    }

    void HandleSettingsBack() {
        if (ui_mode_ == UiMode::kReminders) {
            settings_index_ = 0;
            ui_mode_ = UiMode::kMenu;
            TouchSettings();
            RenderSettingsMenu();
        } else if (ui_mode_ == UiMode::kMenu) {
            ExitSettings();
        } else if (ui_mode_ == UiMode::kDogCow) {
            LeaveDogCowToMenu();
        } else if (ui_mode_ == UiMode::kReminderPicker) {
            ui_mode_ = UiMode::kViewPicker;
            TouchSettings();
            RenderViewPicker();
        } else if (ui_mode_ == UiMode::kStandby || ui_mode_ == UiMode::kCalendar) {
            ui_mode_ = UiMode::kViewPicker;
            TouchSettings();
            RenderViewPicker();
        } else {
            ui_mode_ = UiMode::kMenu;
            TouchSettings();
            RenderSettingsMenu();
        }
    }

    void HandleSettingsClick(ZectrixButton button) {
        TouchSettings();
        if (ui_mode_ == UiMode::kDogCow) {
            if (button == ZectrixButton::kOk) {
                easter_animation_index_ =
                    (easter_animation_index_ + 1) % kEasterEggAnimationCount;
                dog_step_ = 0;
                dog_next_frame_at_ = xTaskGetTickCount() + CurrentEasterFrameInterval();
                // Switching scenes changes most of the display; establish a
                // clean full-refresh base before the new loop starts.
                partial_refresh_count_ = kPartialRefreshLimit;
                RenderEasterEggFrame(true);
            }
            return;
        }
        if (ui_mode_ == UiMode::kMenu) {
            if (button == ZectrixButton::kUp) settings_index_ = (settings_index_ + kSettingsMenuCount - 1) % kSettingsMenuCount;
            else if (button == ZectrixButton::kDown) settings_index_ = (settings_index_ + 1) % kSettingsMenuCount;
            else { ActivateSetting(); return; }
            RenderSettingsMenu();
            return;
        }
        if (ui_mode_ == UiMode::kViewPicker) {
            if (button == ZectrixButton::kUp) {
                settings_view_index_ = (settings_view_index_ + 3) % 4;
                RenderViewPicker();
            } else if (button == ZectrixButton::kDown) {
                settings_view_index_ = (settings_view_index_ + 1) % 4;
                RenderViewPicker();
            } else {
                switch (settings_view_index_) {
                    case 0:
                        ui_mode_ = UiMode::kReminderPicker;
                        RenderReminderPicker();
                        break;
                    case 1: ApplySelectedView(ReminderView::kNotes); break;
                    case 2:
                        standby_style_ = 0;
                        ui_mode_ = UiMode::kStandby;
                        RenderStandby(true);
                        break;
                    case 3:
                        calendar_month_offset_ = 0;
                        calendar_selected_day_ = today_calendar_day_ > 0 ? today_calendar_day_ : 1;
                        calendar_selecting_day_ = true;
                        calendar_day_detail_ = false;
                        calendar_detail_page_ = 0;
                        ApplySelectedView(ReminderView::kCalendar);
                        break;
                }
            }
            return;
        }
        if (ui_mode_ == UiMode::kReminderPicker) {
            if (button == ZectrixButton::kUp) {
                reminder_picker_index_ = (reminder_picker_index_ + 3) % 4;
                RenderReminderPicker();
            } else if (button == ZectrixButton::kDown) {
                reminder_picker_index_ = (reminder_picker_index_ + 1) % 4;
                RenderReminderPicker();
            } else {
                ApplySelectedView(kReminderPickerViews[reminder_picker_index_]);
            }
            return;
        }
        if (ui_mode_ == UiMode::kStandby) {
            if (button == ZectrixButton::kUp || button == ZectrixButton::kDown) {
                standby_style_ = (standby_style_ + (button == ZectrixButton::kDown ? 1 : 2)) % 3;
                RenderStandby(true, true);
            }
            return;
        }
        if (ui_mode_ == UiMode::kCalendar) {
            if (button == ZectrixButton::kUp) --calendar_month_offset_;
            else if (button == ZectrixButton::kDown) ++calendar_month_offset_;
            else calendar_month_offset_ = 0;
            calendar_month_offset_ = std::clamp(calendar_month_offset_, -120, 120);
            RenderCalendar();
            return;
        }
        if (ui_mode_ == UiMode::kNetworkMenu) {
            if (button == ZectrixButton::kUp || button == ZectrixButton::kDown) {
                network_action_index_ = network_action_index_ == 0 ? 1 : 0;
                RenderNetworkMenu();
            } else if (network_action_index_ == 0) {
                ReconnectWifi();
            } else {
                BeginConfirmation(ConfirmAction::kWifi);
            }
            return;
        }
        if (ui_mode_ == UiMode::kConfirm) {
            if (button == ZectrixButton::kUp || button == ZectrixButton::kDown) {
                confirm_selected_ = !confirm_selected_;
                RenderConfirmation();
            } else if (!confirm_selected_) {
                if (confirm_action_ == ConfirmAction::kWifi) {
                    ui_mode_ = UiMode::kNetworkMenu;
                    RenderNetworkMenu();
                } else {
                    ui_mode_ = UiMode::kMenu;
                    RenderSettingsMenu();
                }
            } else {
                ExecuteConfirmedAction();
            }
            return;
        }
        if (button != ZectrixButton::kOk) return;
        if (ui_mode_ == UiMode::kMessage) {
            if (message_returns_to_network_) {
                message_returns_to_network_ = false;
                ui_mode_ = UiMode::kNetworkMenu;
                RenderNetworkMenu();
            } else {
                ui_mode_ = UiMode::kMenu;
                RenderSettingsMenu();
            }
        } else if (ui_mode_ == UiMode::kDetail) {
            if (settings_index_ == 2) RequestSync();
            else {
                ui_mode_ = UiMode::kMenu;
                RenderSettingsMenu();
            }
        } else {
            ui_mode_ = UiMode::kMenu;
            RenderSettingsMenu();
        }
    }

    void TouchSettings() { settings_last_activity_ = xTaskGetTickCount(); }

    void HandlePendingWebAction() {
        const WebAction action = static_cast<WebAction>(
            pending_web_action_.exchange(static_cast<int>(WebAction::kNone)));
        if (action == WebAction::kNone || portal_active_) return;
        switch (action) {
            case WebAction::kSync:
                RequestSync();
                break;
            case WebAction::kRefresh:
                ExitSettings(true);
                break;
            case WebAction::kSetView:
                ApplySelectedView(static_cast<ReminderView>(std::clamp(
                    pending_web_view_.load(), 0,
                    static_cast<int>(kReminderViewNames.size() - 1))));
                break;
            case WebAction::kReconnectWifi:
                ReconnectWifi();
                break;
            case WebAction::kReconfigureWifi:
                confirm_action_ = ConfirmAction::kWifi;
                ExecuteConfirmedAction();
                break;
            case WebAction::kClearCache:
                confirm_action_ = ConfirmAction::kClearCache;
                ExecuteConfirmedAction();
                break;
            case WebAction::kRestart:
                confirm_action_ = ConfirmAction::kRestart;
                ExecuteConfirmedAction();
                break;
            case WebAction::kFactoryReset:
                confirm_action_ = ConfirmAction::kFactoryReset;
                ExecuteConfirmedAction();
                break;
            case WebAction::kNone:
                break;
        }
    }

    void ActivateSetting() {
        switch (settings_index_) {
            case 0:
                settings_view_index_ = active_view_ == ReminderView::kNotes ? 1 : 0;
                for (size_t index = 0; index < kReminderPickerViews.size(); ++index) {
                    if (kReminderPickerViews[index] == active_view_) reminder_picker_index_ = index;
                }
                ui_mode_ = UiMode::kViewPicker;
                RenderViewPicker();
                break;
            case 1: RequestSync(); break;
            case 2: ui_mode_ = UiMode::kDetail; RenderSyncStatus(); break;
            case 3:
                network_action_index_ = 0;
                ui_mode_ = UiMode::kNetworkMenu;
                RenderNetworkMenu();
                break;
            case 4: ExitSettings(true); break;
            case 5: ui_mode_ = UiMode::kDetail; RenderDeviceInfo(); break;
            case 6: BeginConfirmation(ConfirmAction::kRestart); break;
            case 7: BeginConfirmation(ConfirmAction::kClearCache); break;
            case 8: BeginConfirmation(ConfirmAction::kFactoryReset); break;
            case 9: StartDogCow(); break;
            case 10: {
                const bool next = !standby_inverted_;
                nvs_handle_t nvs;
                if (nvs_open(kNamespace, NVS_READWRITE, &nvs) == ESP_OK) {
                    if (nvs_set_u8(nvs, "standbyInvert", next ? 1 : 0) == ESP_OK &&
                        nvs_commit(nvs) == ESP_OK) standby_inverted_ = next;
                    nvs_close(nvs);
                }
                RenderSettingsMenu();
                break;
            }
            case 11: ExitSettings(); break;
        }
    }

    void StartDogCow() {
        easter_animation_index_ = 0;
        dog_step_ = 0;
        dog_next_frame_at_ = xTaskGetTickCount() + CurrentEasterFrameInterval();
        ui_mode_ = UiMode::kDogCow;
        RenderEasterEggFrame(true);
    }

    void LeaveDogCowToMenu() {
        // The animation intentionally allows many fast partial updates. Force
        // a clean base when leaving so no moving-dog ghost remains in menus.
        partial_refresh_count_ = kPartialRefreshLimit;
        ui_mode_ = UiMode::kMenu;
        TouchSettings();
        RenderSettingsMenu();
    }

    void AdvanceDogCow() {
        const TickType_t now = xTaskGetTickCount();
        if (now < dog_next_frame_at_) return;
        dog_next_frame_at_ = now + CurrentEasterFrameInterval();
        dog_step_ = (dog_step_ + 1) %
            (easter_animation_index_ == 0 ? 76 : kAppleAnimationFrameCount);
        RenderEasterEggFrame();
    }

    TickType_t CurrentEasterFrameInterval() const {
        return easter_animation_index_ == 0
            ? kMoofDogFrameInterval : kAppleAnimationFrameInterval;
    }

    bool RenderEasterEggFrame(bool force_full = false) {
        if (easter_animation_index_ == 0) {
            return RenderDogCowFrame(force_full);
        }
        const size_t bytes = static_cast<size_t>(
            easter_egg_frames_bin_end - easter_egg_frames_bin_start);
        const size_t frame_index =
            (easter_animation_index_ - 1) * kAppleAnimationFrameCount +
            dog_step_ % kAppleAnimationFrameCount;
        const size_t offset = frame_index * kFullScreenFrameBytes;
        if (bytes < offset + kFullScreenFrameBytes) return false;

        std::lock_guard<std::mutex> display_lock(display_mutex_);
        ZectrixCanvas& canvas = ui_.canvas();
        std::memcpy(canvas.data(), easter_egg_frames_bin_start + offset,
                    kFullScreenFrameBytes);
        return RefreshFrameLocked(canvas.data(), force_full);
    }

    static void BlitDogSprite(ZectrixCanvas& canvas, size_t pose, int left, int top) {
        const size_t bytes = static_cast<size_t>(
            moof_dog_frames_bin_end - moof_dog_frames_bin_start);
        if (pose >= kMoofDogFrameCount ||
            bytes < (pose + 1) * kMoofDogFrameBytes) return;
        const uint8_t* frame = moof_dog_frames_bin_start + pose * kMoofDogFrameBytes;
        constexpr int stride = kMoofDogWidth / 8;
        for (int y = 0; y < kMoofDogHeight; ++y) {
            for (int x = 0; x < kMoofDogWidth; ++x) {
                const uint8_t value = frame[static_cast<size_t>(y) * stride + x / 8];
                if ((value & (0x80U >> (x & 7))) == 0) {
                    canvas.Pixel(left + x, top + y, true);
                }
            }
        }
    }

    bool RenderDogCowFrame(bool force_full = false) {
        size_t step = dog_step_;
        int x = 0;
        bool barking = false;
        if (step < 18) {
            x = 292 - static_cast<int>(step) * 6;
        } else if (step < 22) {
            x = 184;
            barking = step == 19 || step == 20;
        } else if (step < 52) {
            x = 184 - static_cast<int>(step - 22) * 7;
        } else {
            x = 350 - static_cast<int>(step - 52) * 7;
        }
        const size_t pose = barking ? 2 : step % kMoofDogFrameCount;
        constexpr int bob[] = {0, 2, 1, 0, 2, 1};
        const int y = 106 + bob[pose];

        std::lock_guard<std::mutex> display_lock(display_mutex_);
        ZectrixCanvas& canvas = ui_.canvas();
        canvas.Clear(true);
        BlitDogSprite(canvas, pose, x, y);
        if (barking) {
            const int bubble_x = std::clamp(x + 7, 5, ZECTRIX_EPD_PANEL_WIDTH - 64);
            const int bubble_y = std::max(5, y - 35);
            canvas.FillRect(bubble_x, bubble_y, 62, 28, false);
            canvas.Rect(bubble_x, bubble_y, 62, 28, true);
            canvas.Text(bubble_x + 9, bubble_y + 6, "Moof!", 1);
            canvas.Line(bubble_x + 42, bubble_y + 27, bubble_x + 46, bubble_y + 33);
            canvas.Line(bubble_x + 46, bubble_y + 33, bubble_x + 50, bubble_y + 27);
        }
        return RefreshFrameLocked(canvas.data(), force_full);
    }

    void ApplySelectedView(ReminderView view) {
        if (active_view_ == view) {
            // Selecting the current card is a no-op, not a pending view change.
            ExitSettings();
            return;
        }
        {
            std::lock_guard<std::mutex> lock(mutex_);
            active_view_ = view;
            LoadCachedItems();
            selected_index_ = 0;
            completion_latched_ = false;
            cached_frame_index_ = kInvalidIndex;
            confirmation_frame_index_ = kInvalidIndex;
            display_requested_ = false;
            MarkSyncRequestedLocked(0);
        }
        nvs_handle_t nvs;
        if (nvs_open(kNamespace, NVS_READWRITE, &nvs) == ESP_OK) {
            nvs_set_u8(nvs, "viewMode", static_cast<uint8_t>(view));
            nvs_commit(nvs);
            nvs_close(nvs);
        }
        if (portal_active_) {
            ExitSettings();
            return;
        }
        ui_mode_ = UiMode::kReminders;
        // Every view owns an idle frame. Show its last successful version
        // immediately (also when offline) while Mac prepares newer content.
        if (!RenderIdleFrame()) {
            RenderSettingsFrame(active_view_ == ReminderView::kNotes
                ? kSwitchingNotesFrame : kSwitchingViewFrame);
        }
    }

    void RequestSync() {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            MarkSyncRequestedLocked(0);
            selection_visible_ = false;
        }
        ui_mode_ = UiMode::kReminders;
        if (portal_active_) {
            ShowWifiSetupScreen();
            return;
        }
        if (!RenderIdleFrame()) {
            // With no cached view, the Mac must rebuild even if its reminder
            // array has not changed since the previous successful sync.
            {
                std::lock_guard<std::mutex> lock(mutex_);
                snapshot_revision_ = 0;
            }
            RenderSettingsFrame(kSyncRequestedFrame);
        }
    }

    void BeginConfirmation(ConfirmAction action) {
        confirm_action_ = action;
        confirm_selected_ = false;
        ui_mode_ = UiMode::kConfirm;
        RenderConfirmation();
    }

    void ExecuteConfirmedAction() {
        if (confirm_action_ == ConfirmAction::kClearCache) {
            std::remove(FramePath().c_str());
            std::remove(ConfirmationFramePath().c_str());
            std::remove("/spiffs/idle.bin");
            for (size_t view = 0; view < kReminderViewNames.size(); ++view) {
                char path[32];
                std::snprintf(path, sizeof(path), "/spiffs/idle%u.bin", static_cast<unsigned>(view));
                std::remove(path);
            }
            std::remove(NoteFramePath().c_str());
            std::remove("/spiffs/items.json");
            for (size_t view = 0; view < kReminderViewNames.size(); ++view) {
                char path[32];
                std::snprintf(path, sizeof(path), "/spiffs/items%u.json", static_cast<unsigned>(view));
                std::remove(path);
            }
            {
                std::lock_guard<std::mutex> lock(mutex_);
                snapshot_revision_ = 0;
                cached_frame_index_ = kInvalidIndex;
                confirmation_frame_index_ = kInvalidIndex;
                display_requested_ = false;
                selection_visible_ = false;
                MarkSyncRequestedLocked(0);
            }
            ui_mode_ = UiMode::kReminders;
            RenderSettingsFrame(kCacheClearedFrame);
            return;
        }
        if (confirm_action_ == ConfirmAction::kWifi) {
            nvs_handle_t nvs;
            if (nvs_open(kNamespace, NVS_READWRITE, &nvs) == ESP_OK) {
                // Keep the working credentials until the replacement network
                // has been verified successfully in the captive portal.
                nvs_set_u8(nvs, "forcePortal", 1);
                nvs_commit(nvs);
                nvs_close(nvs);
            }
        } else if (confirm_action_ == ConfirmAction::kFactoryReset) {
            // esp_wifi_set_config 会把网络另存到 Wi-Fi 驱动的 nvs.net80211，
            // 只擦应用命名空间会留下旧网络：先恢复驱动默认配置，再擦除整个 NVS 分区。
            esp_wifi_restore();
            nvs_flash_erase();

            esp_spiffs_format("storage");
        }
        board_.SetPowerLed(true);
        vTaskDelay(pdMS_TO_TICKS(350));
        esp_restart();
    }

    void ExitSettings(bool force_full = false) {
        ui_mode_ = UiMode::kReminders;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            selection_visible_ = false;
        }
        if (portal_active_) {
            ShowWifiSetupScreen();
            return;
        }
        if (!RenderIdleFrame(force_full)) RequestSync();
    }

    void RenderSettingsMenu() {
        const size_t frame = settings_index_ == 11 ? kSettingsReturnFrame :
            (settings_index_ == 10 && standby_inverted_ ? kSettingsStandbyInvertedFrame : settings_index_);
        RenderSettingsFrame(frame);
    }

    bool RenderViewPicker() {
        const size_t bytes = static_cast<size_t>(settings_frames_bin_end - settings_frames_bin_start);
        const size_t frame_index = kViewPickerFrame + settings_view_index_;
        if (frame_index >= kSettingsFrameCount ||
            bytes < (frame_index + 1) * ZECTRIX_EPD_1BPP_FRAME_BYTES) return false;
        std::lock_guard<std::mutex> display_lock(display_mutex_);
        ZectrixCanvas& canvas = ui_.canvas();
        std::memcpy(canvas.data(), settings_frames_bin_start + frame_index * ZECTRIX_EPD_1BPP_FRAME_BYTES,
                    ZECTRIX_EPD_1BPP_FRAME_BYTES);
        return RefreshFrameLocked(canvas.data());
    }

    bool RenderReminderPicker() {
        const size_t bytes = static_cast<size_t>(settings_frames_bin_end - settings_frames_bin_start);
        const size_t frame_index = kReminderPickerFrame + reminder_picker_index_;
        if (frame_index >= kSettingsFrameCount ||
            bytes < (frame_index + 1) * ZECTRIX_EPD_1BPP_FRAME_BYTES) return false;
        std::array<uint32_t, 6> counts;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            counts = view_counts_;
        }
        std::lock_guard<std::mutex> display_lock(display_mutex_);
        ZectrixCanvas& canvas = ui_.canvas();
        std::memcpy(canvas.data(), settings_frames_bin_start + frame_index * ZECTRIX_EPD_1BPP_FRAME_BYTES,
                    ZECTRIX_EPD_1BPP_FRAME_BYTES);
        constexpr int right_edges[] = {181, 375, 181, 375};
        constexpr int ys[] = {83, 83, 185, 185};
        constexpr size_t count_indices[] = {0, 2, 4};
        for (size_t index = 0; index < 3; ++index) {
            char count[12];
            std::snprintf(count, sizeof(count), "%u", static_cast<unsigned>(counts[count_indices[index]]));
            canvas.Text(right_edges[index] - canvas.TextWidth(count, 2), ys[index], count, 2);
        }
        return RefreshFrameLocked(canvas.data());
    }

    static bool IsLeapYear(int year) {
        return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
    }

    static int DaysInMonth(int year, int month) {
        constexpr int days[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
        return days[month - 1] + (month == 2 && IsLeapYear(year) ? 1 : 0);
    }

    static int FirstWeekday(int year, int month) {
        // Sakamoto's Gregorian algorithm: Sunday = 0.
        constexpr int offsets[] = {0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4};
        if (month < 3) --year;
        return (year + year / 4 - year / 100 + year / 400 + offsets[month - 1] + 1) % 7;
    }

    bool RenderCalendar(bool force_full = false) {
        const size_t bytes = static_cast<size_t>(settings_frames_bin_end - settings_frames_bin_start);
        if (bytes < (kCalendarFrame + 1) * ZECTRIX_EPD_1BPP_FRAME_BYTES) return false;
        int day = 0, month = 0, year = 0;
        std::vector<int> marked_dates;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            day = today_calendar_day_;
            month = today_calendar_month_;
            year = today_calendar_year_;
            marked_dates = calendar_date_keys_;
        }
        std::lock_guard<std::mutex> display_lock(display_mutex_);
        ZectrixCanvas& canvas = ui_.canvas();
        std::memcpy(canvas.data(), settings_frames_bin_start + kCalendarFrame * ZECTRIX_EPD_1BPP_FRAME_BYTES,
                    ZECTRIX_EPD_1BPP_FRAME_BYTES);
        if (year == 0 || month == 0) {
            canvas.TextCentered(135, "WAIT FOR MAC", 2);
            return RefreshFrameLocked(canvas.data(), force_full);
        }
        month += calendar_month_offset_;
        while (month < 1) { month += 12; --year; }
        while (month > 12) { month -= 12; ++year; }
        char heading[20];
        std::snprintf(heading, sizeof(heading), "%04d / %02d", year, month);
        canvas.Text(388 - canvas.TextWidth(heading, 2), 22, heading, 2);
        const int first = FirstWeekday(year, month);
        const int total = DaysInMonth(year, month);
        for (int date = 1; date <= total; ++date) {
            const int cell = first + date - 1;
            const int x = 27 + (cell % 7) * 55;
            const int y = 107 + (cell / 7) * 28;
            char label[16];
            std::snprintf(label, sizeof(label), "%d", date);
            canvas.Text(x, y, label, 1);
            if (calendar_month_offset_ == 0 && date == day) {
                canvas.Rect(x - 5, y - 4, 27, 23);
            }
            const int key = year * 10000 + month * 100 + date;
            if (std::find(marked_dates.begin(), marked_dates.end(), key) != marked_dates.end()) {
                canvas.FillRect(x + 21, y + 6, 3, 3, true);
            }
        }
        return RefreshFrameLocked(canvas.data(), force_full);
    }

    void AdvanceStandby() {
        // The clock changes once per minute. Never refresh an e-ink panel at
        // the former countdown's ten-second cadence.
        int64_t now_ms = 0;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            now_ms = clock_epoch_ms_ > 0
                ? clock_epoch_ms_ + (esp_timer_get_time() - clock_anchor_us_) / 1000 : 0;
        }
        const int64_t bucket = now_ms > 0 ? now_ms / 60000 : 0;
        if (bucket != standby_last_bucket_) RenderStandby();
    }

    static void DrawStandbyDigits(ZectrixCanvas& canvas, const char* value,
                                  int center_x, int y, bool small) {
        const int glyph_width = small ? 64 : 80;
        const int glyph_height = small ? 256 : 176;
        const int advance = small ? 58 : 76;
        const int colon_advance = small ? 20 : 32;
        const size_t bytes_per_glyph = small ? kSmallDigitFrameBytes : kBigDigitFrameBytes;
        const size_t offset = small ? 11 * kBigDigitFrameBytes : 0;
        const size_t available = static_cast<size_t>(standby_digits_bin_end - standby_digits_bin_start);
        if (available < offset + 11 * bytes_per_glyph) return;
        int total_width = 0;
        for (const char* p = value; *p; ++p) total_width += *p == ':' ? colon_advance : advance;
        int cursor_x = center_x - total_width / 2;
        for (const char* p = value; *p; ++p) {
            const int index = *p == ':' ? 10 : (*p >= '0' && *p <= '9' ? *p - '0' : -1);
            if (index < 0) continue;
            const uint8_t* pixels = standby_digits_bin_start + offset + index * bytes_per_glyph;
            for (int row = 0; row < glyph_height; ++row) {
                for (int column = 0; column < glyph_width; ++column) {
                    const size_t pixel = static_cast<size_t>(row * glyph_width + column);
                    if ((pixels[pixel / 8] & (0x80 >> (pixel % 8))) == 0) {
                        canvas.Pixel(cursor_x + column, y + row, false);
                    }
                }
            }
            cursor_x += *p == ':' ? colon_advance : advance;
        }
    }

    static void DrawStandbyClock(ZectrixCanvas& canvas, int hour, int minute, int style) {
        struct MaskRegion { int x, y, width, height; size_t offset; };
        constexpr size_t style_zero_hours = 24 * (200 * 200 / 8);
        constexpr size_t style_zero_minutes = 60 * (216 * 200 / 8);
        constexpr size_t style_one_hours = 24 * (160 * 268 / 8);
        const size_t style_one_offset = style_zero_hours + style_zero_minutes;
        const std::array<MaskRegion, 2> regions = style == 0
            ? std::array<MaskRegion, 2>{
                MaskRegion{20, 40, 200, 200, static_cast<size_t>(hour) * (200 * 200 / 8)},
                MaskRegion{184, 40, 216, 200, style_zero_hours + static_cast<size_t>(minute) * (216 * 200 / 8)}
              }
            : std::array<MaskRegion, 2>{
                MaskRegion{0, 16, 160, 268, style_one_offset + static_cast<size_t>(hour) * (160 * 268 / 8)},
                MaskRegion{152, 16, 128, 268, style_one_offset + style_one_hours + static_cast<size_t>(minute) * (128 * 268 / 8)}
              };
        const size_t available = static_cast<size_t>(standby_clock_masks_bin_end - standby_clock_masks_bin_start);
        int clock_left = ZECTRIX_EPD_PANEL_WIDTH;
        int clock_right = -1;
        if (style == 0) {
            // The rounded font has different visible widths for 1, 3, 8, etc.
            // Center the actual white pixels of this HH:MM combination, not
            // the fixed glyph slots used to keep the two masks aligned.
            for (const MaskRegion& region : regions) {
                const size_t size = static_cast<size_t>(region.width * region.height / 8);
                if (available < region.offset + size) return;
                const uint8_t* mask = standby_clock_masks_bin_start + region.offset;
                for (int row = 0; row < region.height; ++row) {
                    for (int column = 0; column < region.width; ++column) {
                        const size_t bit = static_cast<size_t>(row * region.width + column);
                        if (mask[bit / 8] & (0x80 >> (bit % 8))) {
                            const int x = region.x + column;
                            clock_left = std::min(clock_left, x);
                            clock_right = std::max(clock_right, x);
                        }
                    }
                }
            }
        }
        const int shift = clock_right >= clock_left
            ? std::clamp((ZECTRIX_EPD_PANEL_WIDTH - 1 - clock_left - clock_right) / 2,
                         -clock_left, ZECTRIX_EPD_PANEL_WIDTH - 1 - clock_right)
            : 0;
        for (const MaskRegion& region : regions) {
            const size_t size = static_cast<size_t>(region.width * region.height / 8);
            if (available < region.offset + size) return;
            const uint8_t* mask = standby_clock_masks_bin_start + region.offset;
            for (int row = 0; row < region.height; ++row) {
                for (int column = 0; column < region.width; ++column) {
                    const size_t bit = static_cast<size_t>(row * region.width + column);
                    if (mask[bit / 8] & (0x80 >> (bit % 8)))
                        canvas.Pixel(region.x + column + shift, region.y + row, false);
                }
            }
        }
    }

    static void DrawStandbyDate(ZectrixCanvas& canvas, int day, int weekday) {
        constexpr size_t clock_bytes = 24 * (200 * 200 / 8) + 60 * (216 * 200 / 8)
            + 24 * (160 * 268 / 8) + 60 * (128 * 268 / 8);
        constexpr int width = 48, height = 48;
        constexpr size_t mask_bytes = width * height / 8;
        if (day < 1 || day > 31 || weekday < 0 || weekday > 6) return;
        const size_t available = static_cast<size_t>(standby_clock_masks_bin_end - standby_clock_masks_bin_start);
        for (const auto& part : {
                 std::pair<size_t, int>{clock_bytes + static_cast<size_t>(day - 1) * mask_bytes, 282},
                 {clock_bytes + static_cast<size_t>(31 + weekday) * mask_bytes, 329}}) {
            if (available < part.first + mask_bytes) return;
            const uint8_t* mask = standby_clock_masks_bin_start + part.first;
            for (int row = 0; row < height; ++row) {
                for (int column = 0; column < width; ++column) {
                    const size_t bit = static_cast<size_t>(row * width + column);
                    if (mask[bit / 8] & (0x80 >> (bit % 8)))
                        canvas.Pixel(part.second + column, 28 + row, false);
                }
            }
        }
    }

    static void DrawStandbyWeekday(ZectrixCanvas& canvas, int weekday) {
        constexpr int width = 48, height = 24;
        constexpr size_t glyph_bytes = width * height / 8;
        const size_t offset = 11 * (kBigDigitFrameBytes + kSmallDigitFrameBytes)
            + static_cast<size_t>(weekday) * glyph_bytes;
        const size_t available = static_cast<size_t>(standby_digits_bin_end - standby_digits_bin_start);
        if (weekday < 0 || weekday > 6 || available < offset + glyph_bytes) return;
        const uint8_t* glyph = standby_digits_bin_start + offset;
        for (int row = 0; row < height; ++row) {
            for (int column = 0; column < width; ++column) {
                const size_t pixel = static_cast<size_t>(row * width + column);
                if ((glyph[pixel / 8] & (0x80 >> (pixel % 8))) == 0)
                    canvas.Pixel(329 + column, 38 + row, false);
            }
        }
    }

    static void DrawStandbyText(ZectrixCanvas& canvas,
                                const std::vector<uint8_t>& bitmap, int x, int y) {
        if (bitmap.size() != kStandbyTextBytes) return;
        for (int row = 0; row < kStandbyTextHeight; ++row) {
            for (int column = 0; column < kStandbyTextWidth; ++column) {
                const size_t bit = static_cast<size_t>(row * kStandbyTextWidth + column);
                if ((bitmap[bit / 8] & (0x80 >> (bit % 8))) == 0)
                    canvas.Pixel(x + column, y + row, false);
            }
        }
    }

    static void DrawWhiteInkPatch(ZectrixCanvas& canvas, const uint8_t* bitmap,
                                  int width, int height, int x, int y) {
        for (int row = 0; row < height; ++row) {
            for (int column = 0; column < width; ++column) {
                const size_t bit = static_cast<size_t>(row * width + column);
                if (bitmap[bit / 8] & (0x80U >> (bit % 8)))
                    canvas.Pixel(x + column, y + row, false);
            }
        }
    }

    static void DrawWhiteInkTextPatch(ZectrixCanvas& canvas,
                                      const std::vector<uint8_t>& bitmap,
                                      int width, int height, int x, int y) {
        if (bitmap.size() != static_cast<size_t>(width * height / 8)) return;
        // Mac text patches use the existing 1=background, 0=ink convention.
        for (int row = 0; row < height; ++row) {
            for (int column = 0; column < width; ++column) {
                const size_t bit = static_cast<size_t>(row * width + column);
                if ((bitmap[bit / 8] & (0x80U >> (bit % 8))) == 0)
                    canvas.Pixel(x + column, y + row, false);
            }
        }
    }

    bool RenderStandby(bool force_full = false, bool clear_before = false) {
        const size_t bytes = static_cast<size_t>(settings_frames_bin_end - settings_frames_bin_start);
        DueAlert nearest;
        bool found = false;
        int64_t now_ms = 0;
        int offset_minutes = 0;
        std::vector<uint8_t> photo;
        std::vector<uint8_t> weather;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            now_ms = clock_epoch_ms_ > 0
                ? clock_epoch_ms_ + (esp_timer_get_time() - clock_anchor_us_) / 1000 : 0;
            offset_minutes = time_zone_offset_minutes_;
            if (standby_style_ == 2) {
                photo = photo_bitmap_;
                weather = weather_bitmap_;
            }
            for (const DueAlert& candidate : alerts_) {
                if (candidate.due_at_epoch_ms < now_ms) continue;
                if (!found || candidate.due_at_epoch_ms < nearest.due_at_epoch_ms) {
                    nearest = candidate;
                    found = true;
                }
            }
        }
        const size_t frame = kStandbySecondsFrame + standby_style_;
        if (standby_style_ != 2 &&
            bytes < (frame + 1) * ZECTRIX_EPD_1BPP_FRAME_BYTES) return false;
        std::lock_guard<std::mutex> display_lock(display_mutex_);
        if (clear_before) {
            // A full black-to-black waveform can leave the previous large
            // digits visible. Clear the whole panel to white first, then run
            // the full waveform for the new standby style.
            std::vector<uint8_t> white(ZECTRIX_EPD_1BPP_FRAME_BYTES, 0xFF);
            RefreshFrameLocked(white.data(), true);
        }
        ZectrixCanvas& canvas = ui_.canvas();
        if (standby_style_ == 2) {
            canvas.Clear(false);
            const size_t default_bytes = static_cast<size_t>(
                standby_default_photo_bin_end - standby_default_photo_bin_start);
            const uint8_t* photo_pixels = photo.size() == kPhotoBytes
                ? photo.data() : standby_default_photo_bin_start;
            if (photo.size() == kPhotoBytes || default_bytes == kPhotoBytes)
                DrawWhiteInkPatch(canvas, photo_pixels, kPhotoWidth, kPhotoHeight, 15, 43);
            if (weather.size() == kWeatherBytes)
                DrawWhiteInkPatch(canvas, weather.data(), kWeatherWidth, kWeatherHeight, 207, 40);
            else canvas.Text(211, 100, "--", 4, false);
            if (found) {
                DrawWhiteInkTextPatch(canvas, nearest.photo_reminder_bitmap,
                                      kPhotoReminderWidth, kPhotoReminderHeight, 210, 216);
                DrawWhiteInkTextPatch(canvas, nearest.standby_due_bitmap,
                                      kStandbyTextWidth, kStandbyTextHeight, 210, 242);
            }
            standby_last_bucket_ = now_ms > 0 ? now_ms / 60000 : 0;
            if (standby_inverted_) {
                for (size_t i = 0; i < ZECTRIX_EPD_1BPP_FRAME_BYTES; ++i)
                    canvas.data()[i] = static_cast<uint8_t>(~canvas.data()[i]);
            }
            return RefreshFrameLocked(canvas.data(), force_full);
        }
        std::memcpy(canvas.data(), settings_frames_bin_start + frame * ZECTRIX_EPD_1BPP_FRAME_BYTES,
                    ZECTRIX_EPD_1BPP_FRAME_BYTES);
        std::tm local_time{};
        if (now_ms > 0) {
            const std::time_t epoch = static_cast<std::time_t>(now_ms / 1000 + offset_minutes * 60);
            ::gmtime_r(&epoch, &local_time);
            DrawStandbyClock(canvas, local_time.tm_hour, local_time.tm_min, standby_style_);
        } else {
            canvas.TextCentered(130, "WAIT FOR TIME", 2, true);
        }
        if (standby_style_ == 1 && now_ms > 0) {
            DrawStandbyDate(canvas, local_time.tm_mday, local_time.tm_wday);
        }
        if (found) {
            const int title_x = standby_style_ == 0 ? 128 : 282;
            const int title_y = standby_style_ == 0 ? 267 : 233;
            if (nearest.standby_title_bitmap.size() == kStandbyTextBytes) {
                DrawStandbyText(canvas, nearest.standby_title_bitmap, title_x, title_y);
            } else {
                for (int y = 36; y < 56; ++y) {
                    for (int x = 64; x < 176; ++x) {
                        const size_t pixel = static_cast<size_t>(y * kAlertWidth + x);
                        if (nearest.bitmap[pixel / 8] & (0x80 >> (pixel % 8))) continue;
                        canvas.Pixel(title_x + x - 64, title_y + y - 36, false);
                    }
                }
            }
            if (nearest.standby_due_bitmap.size() == kStandbyTextBytes) {
                DrawStandbyText(canvas, nearest.standby_due_bitmap,
                                standby_style_ == 0 ? 280 : 285,
                                standby_style_ == 0 ? 267 : 258);
            } else {
                const std::time_t due_epoch = static_cast<std::time_t>(
                    nearest.due_at_epoch_ms / 1000 + offset_minutes * 60);
                std::tm due_time{};
                ::gmtime_r(&due_epoch, &due_time);
                char due[24];
                std::snprintf(due, sizeof(due), "%02d/%02d %02d:%02d",
                    due_time.tm_mon + 1, due_time.tm_mday, due_time.tm_hour, due_time.tm_min);
                canvas.Text(standby_style_ == 0 ? 280 : 285,
                            standby_style_ == 0 ? 272 : 270, due, 1, true);
            }
        }
        standby_last_bucket_ = now_ms > 0 ? now_ms / 60000 : 0;
        if (standby_inverted_) {
            for (size_t i = 0; i < ZECTRIX_EPD_1BPP_FRAME_BYTES; ++i) {
                canvas.data()[i] = static_cast<uint8_t>(~canvas.data()[i]);
            }
        }
        return RefreshFrameLocked(canvas.data(), force_full);
    }

    void RenderConfirmation() {
        size_t base = kWifiConfirmFrame;
        if (confirm_action_ == ConfirmAction::kRestart) base = kRestartConfirmFrame;
        else if (confirm_action_ == ConfirmAction::kClearCache) base = kClearCacheConfirmFrame;
        else if (confirm_action_ == ConfirmAction::kFactoryReset) base = kFactoryResetConfirmFrame;
        RenderSettingsFrame(base + (confirm_selected_ ? 1 : 0));
    }

    void RenderSyncStatus() {
        char revision[24];
        char pending[16];
        uint64_t snapshot = 0;
        size_t operation_count = 0;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            snapshot = snapshot_revision_;
            operation_count = operations_.size();
        }
        std::snprintf(revision, sizeof(revision), "%llu", static_cast<unsigned long long>(snapshot));
        std::snprintf(pending, sizeof(pending), "%u", static_cast<unsigned>(operation_count));
        const bool online = IsMacOnline();
        RenderSettingsFrame(kSyncDetailFrame, revision, pending, online ? "ONLINE" : "OFFLINE");
    }

    void RenderNetworkMenu() {
        wifi_ap_record_t access_point = {};
        const bool connected = esp_wifi_sta_get_ap_info(&access_point) == ESP_OK;
        const size_t frame_index = network_action_index_ == 0
            ? kNetworkDetailFrame : kNetworkReconfigureFrame;
        RenderSettingsFrame(
            frame_index,
            connected ? reinterpret_cast<const char*>(access_point.ssid) : "NOT CONNECTED");
    }

    void ReconnectWifi() {
        ui_mode_ = UiMode::kMessage;
        message_returns_to_network_ = true;
        RenderSettingsFrame(kWifiReconnectingFrame);

        std::string ssid;
        std::string password;
        if (!LoadWifi(&ssid, &password)) {
            RenderSettingsFrame(kWifiReconnectFailedFrame);
            return;
        }

        wifi_config_t station = {};
        std::strncpy(reinterpret_cast<char*>(station.sta.ssid),
                     ssid.c_str(), sizeof(station.sta.ssid) - 1);
        std::strncpy(reinterpret_cast<char*>(station.sta.password),
                     password.c_str(), sizeof(station.sta.password) - 1);
        station.sta.threshold.authmode = WIFI_AUTH_OPEN;
        esp_wifi_disconnect();
        vTaskDelay(pdMS_TO_TICKS(150));
        esp_err_t err = esp_wifi_set_mode(WIFI_MODE_STA);
        if (err == ESP_OK) err = esp_wifi_set_config(WIFI_IF_STA, &station);
        if (err == ESP_OK) err = esp_wifi_connect();
        char address[20] = {};
        if (err != ESP_OK || !WaitForStationAddress(address, sizeof(address), 40)) {
            ESP_LOGW(kTag, "saved Wi-Fi reconnect failed: %s",
                     err == ESP_OK ? "timeout" : esp_err_to_name(err));
            RenderSettingsFrame(kWifiReconnectFailedFrame);
            return;
        }
        esp_wifi_set_ps(WIFI_PS_MAX_MODEM);

        const bool reconnected_in_portal = portal_active_;
        portal_active_ = false;
        portal_ssid_.clear();
        wifi_recovery_pending_ = false;
        wifi_retry_at_ = 0;
        wifi_retry_delay_ms_ = 10000;

        ESP_LOGI(kTag, "reconnected saved Wi-Fi %s at %s", ssid.c_str(), address);
        message_returns_to_network_ = false;
        RenderSettingsFrame(kWifiReconnectSuccessFrame);
        vTaskDelay(pdMS_TO_TICKS(900));

        // 能在门户里重连成功，说明已有保存的网络，门户是「重新配网」写入的 forcePortal 触发的。
        // 擦掉该标记并重启，关闭设备热点和通配 DNS 任务，下次启动直接使用已保存的网络。
        if (reconnected_in_portal) {
            nvs_handle_t nvs;
            if (nvs_open(kNamespace, NVS_READWRITE, &nvs) == ESP_OK) {
                nvs_erase_key(nvs, "forcePortal");
                nvs_commit(nvs);
                nvs_close(nvs);
            }

            esp_restart();
        }

        RequestSync();
    }

    void RenderDeviceInfo() {
        const ZectrixPowerSnapshot power = board_.ReadPowerSnapshot();
        size_t total = 0, used = 0;
        esp_spiffs_info("storage", &total, &used);
        char battery[20];
        char storage[20];
        std::snprintf(battery, sizeof(battery), power.battery_valid ? "%u%%" : "--", power.battery_percent);
        if (total >= used && total > 0) {
            std::snprintf(storage, sizeof(storage), "%u KB", static_cast<unsigned>((total - used) / 1024));
        } else {
            std::snprintf(storage, sizeof(storage), "--");
        }
        RenderSettingsFrame(kDeviceDetailFrame, kFirmwareVersion, battery, storage);
    }

    bool RenderSettingsFrame(size_t index, const char* value1 = nullptr,
                             const char* value2 = nullptr, const char* value3 = nullptr) {
        const size_t bytes = static_cast<size_t>(settings_frames_bin_end - settings_frames_bin_start);
        if (index >= kSettingsFrameCount || bytes < (index + 1) * ZECTRIX_EPD_1BPP_FRAME_BYTES) return false;
        std::lock_guard<std::mutex> display_lock(display_mutex_);
        ZectrixCanvas& canvas = ui_.canvas();
        std::memcpy(canvas.data(), settings_frames_bin_start + index * ZECTRIX_EPD_1BPP_FRAME_BYTES,
                    ZECTRIX_EPD_1BPP_FRAME_BYTES);
        const char* values[] = {value1, value2, value3};
        const int ys[] = {80, 128, 176};
        for (size_t row = 0; row < 3; ++row) {
            if (values[row]) canvas.Text(214, ys[row], values[row], 1);
        }
        return RefreshFrameLocked(canvas.data());
    }

    static std::string FramePath() { return "/spiffs/frame.bin"; }
    std::string IdleFramePath() const {
        char path[32];
        std::snprintf(path, sizeof(path), "/spiffs/idle%u.bin", static_cast<unsigned>(active_view_));
        return path;
    }
    static std::string ConfirmationFramePath() { return "/spiffs/confirm.bin"; }
    static std::string NoteFramePath() { return "/spiffs/note.bin"; }
    std::string CachedItemsPath() const {
        char path[32];
        std::snprintf(path, sizeof(path), "/spiffs/items%u.json", static_cast<unsigned>(active_view_));
        return path;
    }

    // 写接口只接受带 X-EInk-Reminders: 1 请求头、且用 IPv4 地址访问设备的请求。
    // 自定义请求头让其他网站发起的跨站请求必须先预检，设备不响应预检，浏览器就不会发出；
    // Host 必须是 IP 地址，挡住用域名重绑定到设备地址的网页。
    static bool AcceptsWrite(httpd_req_t* req) {
        char marker[4] = {};
        if (httpd_req_get_hdr_value_str(req, "X-EInk-Reminders", marker, sizeof(marker)) != ESP_OK ||
            std::strcmp(marker, "1") != 0) {
            return false;
        }

        return HostIsIpv4(req);
    }

    // 请求的 Host 是否为 IPv4 地址。Host 可能带端口，只取冒号前的部分；
    // 超过缓冲区的 Host 不可能是 IPv4 地址，直接判为否。
    static bool HostIsIpv4(httpd_req_t* req) {
        char host[32] = {};
        if (httpd_req_get_hdr_value_str(req, "Host", host, sizeof(host)) != ESP_OK) return false;
        if (char* port = std::strchr(host, ':')) *port = '\0';

        esp_ip4_addr_t address = {};
        return esp_netif_str_to_ip4(host, &address) == ESP_OK;
    }

    static bool ReadBody(httpd_req_t* req, std::string* body, size_t maximum) {
        if (req->content_len <= 0 || static_cast<size_t>(req->content_len) > maximum) return false;
        body->resize(req->content_len);
        size_t received = 0;
        while (received < body->size()) {
            const int count = httpd_req_recv(req, body->data() + received, body->size() - received);
            if (count <= 0) return false;
            received += count;
        }
        return true;
    }
    static std::string String(const cJSON* object, const char* key) {
        const cJSON* value = cJSON_GetObjectItemCaseSensitive(object, key);
        return cJSON_IsString(value) && value->valuestring ? value->valuestring : "";
    }
    static uint64_t Number(const cJSON* object, const char* key) {
        const cJSON* value = cJSON_GetObjectItemCaseSensitive(object, key);
        return cJSON_IsNumber(value) && value->valuedouble >= 0 ? static_cast<uint64_t>(value->valuedouble) : 0;
    }
    static bool Bool(const cJSON* object, const char* key) { return cJSON_IsTrue(cJSON_GetObjectItemCaseSensitive(object, key)); }

    static std::string FormValue(const std::string& body, const std::string& key) {
        const std::string prefix = key + "=";
        size_t start = body.find(prefix);
        if (start == std::string::npos || (start != 0 && body[start - 1] != '&')) return "";
        start += prefix.size();
        const size_t end = body.find('&', start);
        const std::string value = body.substr(start, end == std::string::npos ? end : end - start);
        std::string decoded;
        for (size_t i = 0; i < value.size(); ++i) {
            if (value[i] == '+') decoded.push_back(' ');
            else if (value[i] == '%' && i + 2 < value.size() &&
                     std::isxdigit(static_cast<unsigned char>(value[i + 1])) && std::isxdigit(static_cast<unsigned char>(value[i + 2]))) {
                char hex[3] = {value[i + 1], value[i + 2], 0};
                decoded.push_back(static_cast<char>(std::strtol(hex, nullptr, 16))); i += 2;
            } else decoded.push_back(value[i]);
        }
        return decoded;
    }
    static esp_err_t SendJson(httpd_req_t* req, cJSON* root) {
        char* json = cJSON_PrintUnformatted(root); cJSON_Delete(root);
        if (!json) return ESP_ERR_NO_MEM;
        httpd_resp_set_type(req, "application/json");
        const esp_err_t err = httpd_resp_sendstr(req, json); cJSON_free(json); return err;
    }
    static esp_err_t SendError(httpd_req_t* req, int status, const char* error) {
        char status_text[32]; std::snprintf(status_text, sizeof(status_text), "%d Error", status);
        char body[96]; std::snprintf(body, sizeof(body), "{\"error\":\"%s\"}", error);
        httpd_resp_set_status(req, status_text); httpd_resp_set_type(req, "application/json");
        return httpd_resp_sendstr(req, body);
    }

    ZectrixBoard board_;
    zectrix_epd_handle_t epd_ = nullptr;
    ZectrixDemoUi ui_{nullptr};
    httpd_handle_t server_ = nullptr;
    esp_netif_t* station_netif_ = nullptr;
    esp_netif_t* portal_netif_ = nullptr;
    bool portal_active_ = false;
    std::string portal_ssid_;
    bool wifi_recovery_pending_ = false;
    TickType_t wifi_retry_at_ = 0;
    uint32_t wifi_retry_delay_ms_ = 10000;
    std::mutex mutex_;
    std::mutex display_mutex_;
    std::vector<Operation> operations_;
    std::vector<std::string> reminder_ids_;
    std::vector<std::string> reminder_apple_ids_;
    std::vector<DueAlert> alerts_;
    DueAlert active_alert_;
    std::vector<std::string> handled_alert_keys_;
    std::vector<uint8_t> alert_base_frame_ =
        std::vector<uint8_t>(ZECTRIX_EPD_1BPP_FRAME_BYTES, 0xFF);
    std::vector<uint8_t> alert_render_frame_ =
        std::vector<uint8_t>(ZECTRIX_EPD_1BPP_FRAME_BYTES, 0xFF);
    size_t alert_action_index_ = 0;
    bool alert_delay_menu_open_ = false;
    size_t alert_delay_option_ = 0;
    std::atomic<bool> alert_sound_playing_{false};
    int64_t clock_epoch_ms_ = 0;
    int64_t clock_anchor_us_ = 0;
    int time_zone_offset_minutes_ = 0;
    std::vector<uint8_t> current_frame_ =
        std::vector<uint8_t>(ZECTRIX_EPD_1BPP_FRAME_BYTES, 0xFF);
    bool current_frame_valid_ = false;
    size_t partial_refresh_count_ = 0;
    size_t selected_index_ = 0;
    bool completion_latched_ = false;
    bool selection_visible_ = false;
    bool idle_frame_received_since_snapshot_ = false;
    bool display_requested_ = false;
    bool note_detail_ = false;
    bool note_open_requested_ = false;
    size_t note_page_ = 0;
    size_t note_page_count_ = 1;
    size_t cached_frame_index_ = kInvalidIndex;
    size_t confirmation_frame_index_ = kInvalidIndex;
    TickType_t selection_last_activity_ = 0;
    uint64_t snapshot_revision_ = 0;
    uint64_t next_sequence_ = 1;
    std::atomic<UiMode> ui_mode_{UiMode::kReminders};
    size_t settings_index_ = 0;
    TickType_t settings_last_activity_ = 0;
    ConfirmAction confirm_action_ = ConfirmAction::kRestart;
    bool confirm_selected_ = false;
    bool sync_requested_ = false;
    uint64_t sync_request_id_ = 0;
    int64_t sync_requested_at_us_ = 0;
    std::atomic<int64_t> last_client_activity_us_{0};
    std::atomic<bool> mac_wake_pending_{false};
    std::atomic<int> pending_web_action_{static_cast<int>(WebAction::kNone)};
    std::atomic<int> pending_web_view_{0};
    ReminderView active_view_ = ReminderView::kToday;
    size_t settings_view_index_ = 0;
    size_t network_action_index_ = 0;
    bool message_returns_to_network_ = false;
    size_t easter_animation_index_ = 0;
    size_t dog_step_ = 0;
    TickType_t dog_next_frame_at_ = 0;
    std::array<uint32_t, 6> view_counts_ = {};
    size_t reminder_picker_index_ = 0;
    int today_calendar_day_ = 0;
    int today_calendar_month_ = 0;
    int today_calendar_year_ = 0;
    int calendar_month_offset_ = 0;
    int standby_style_ = 0;
    bool standby_inverted_ = false;
    int64_t standby_last_bucket_ = -1;
    std::vector<uint8_t> photo_bitmap_;
    std::vector<uint8_t> weather_bitmap_;
    std::string weather_city_ = "广州";
    int32_t weather_latitude_e6_ = 23129100;
    int32_t weather_longitude_e6_ = 113264400;
    uint32_t weather_location_version_ = 0;
    UiMode alert_return_mode_ = UiMode::kReminders;
    std::vector<int> calendar_date_keys_;
    int calendar_selected_day_ = 1;
    bool calendar_selecting_day_ = false;
    bool calendar_day_detail_ = false;
    int calendar_detail_page_ = 0;
};

}  // namespace

extern "C" void app_main() {
    static ReminderApp app;
    app.Run();
}
