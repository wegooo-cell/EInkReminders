#include "zectrix_demo_ui.h"

#include <algorithm>
#include <cstdio>
#include <cstring>

#include "esp_log.h"
#include "esp_timer.h"

namespace {

constexpr char kTag[] = "demo_ui";
constexpr int kHeaderHeight = 36;
constexpr int kFooterHeight = 30;
constexpr int kTestStripHeight = 42;
constexpr int kTestContentLeft = 16;
constexpr int kTestContentRight = 384;
constexpr int kPartialRefreshLimit = 8;
constexpr int64_t kUpdateThrottleUs = 500000;

constexpr std::array<ZectrixTestId, 7> kTestOrder = {
    ZectrixTestId::kRf, ZectrixTestId::kAudio, ZectrixTestId::kRtc,
    ZectrixTestId::kCharge, ZectrixTestId::kLed, ZectrixTestId::kButtons,
    ZectrixTestId::kNfc};

constexpr std::array<const char*, 7> kTestShortNames = {
    "RF", "AUDIO", "RTC", "PWR", "LED", "KEYS", "NFC"};

void DrawFittedText(ZectrixCanvas& canvas, int x, int y, const char* text,
                    int max_width) {
    if (text == nullptr || max_width <= 0) {
        return;
    }
    if (canvas.TextWidth(text) <= max_width) {
        canvas.Text(x, y, text);
        return;
    }

    constexpr char kEllipsis[] = "...";
    char fitted[80] = {};
    size_t length = std::min(std::strlen(text), sizeof(fitted) - 4);
    std::memcpy(fitted, text, length);
    while (length > 0) {
        fitted[length] = '\0';
        if (canvas.TextWidth(fitted) + canvas.TextWidth(kEllipsis) <=
            max_width) {
            break;
        }
        --length;
    }
    std::memcpy(fitted + length, kEllipsis, sizeof(kEllipsis));
    canvas.Text(x, y, fitted);
}

}  // namespace

void ZectrixDemoUi::DrawFrame(const char* title, const char* footer) {
    canvas_.Clear();
    canvas_.FillRect(0, 0, 400, kHeaderHeight, true);
    canvas_.Text(10, 10, title, 1, true);
    canvas_.Line(0, 269, 399, 269);
    canvas_.Text(8, 277, footer, 1);
}

esp_err_t ZectrixDemoUi::ShowSplash() {
    canvas_.Clear();
    canvas_.FillRect(0, 0, 400, 8, true);
    canvas_.FillRect(0, 292, 400, 8, true);
    canvas_.TextCentered(58, "ZECTRIX", 2);
    canvas_.Line(72, 98, 327, 98);
    canvas_.TextCentered(118, "HARDWARE SHOWCASE", 1);
    canvas_.TextCentered(154, "ESP32-S3 E-PAPER DEV KIT", 1);
    canvas_.TextCentered(184, "400 x 300  /  16 GRAY", 1);
    canvas_.TextCentered(236, "ZECTRIX LAB", 1);
    return RefreshFull();
}

esp_err_t ZectrixDemoUi::ShowMenu(const char* title,
                                  const char* const* items, size_t count,
                                  size_t selected, const char* footer,
                                  bool full_refresh) {
    DrawFrame(title, footer);
    constexpr int row_height = 42;
    const int start_y = 46;
    for (size_t i = 0; i < count; ++i) {
        const int y = start_y + static_cast<int>(i) * row_height;
        const bool active = i == selected;
        if (active) {
            canvas_.FillRect(16, y, 368, 34, true);
            canvas_.Text(28, y + 9, items[i], 1, true);
        } else {
            canvas_.Rect(16, y, 368, 34);
            canvas_.Text(28, y + 9, items[i]);
        }
    }
    return full_refresh ? RefreshFull()
                        : RefreshPartial({0, 36, 400, 234});
}

esp_err_t ZectrixDemoUi::ShowSceneInfo(const char* title, const char* mode,
                                       const char* format, size_t bytes,
                                       int64_t elapsed_ms, esp_err_t result) {
    DrawFrame("DISPLAY GALLERY", "OK Return   Hold OK Back");
    canvas_.Text(20, 54, title, 2);
    canvas_.Line(20, 92, 379, 92);
    canvas_.Text(28, 112, "REFRESH MODE:");
    canvas_.Text(184, 112, mode);
    canvas_.Text(28, 142, "PIXEL FORMAT:");
    canvas_.Text(184, 142, format);
    char line[64];
    std::snprintf(line, sizeof(line), "%u BYTES",
                  static_cast<unsigned>(bytes));
    canvas_.Text(184, 172, line);
    canvas_.Text(28, 172, "FRAME BUFFER:");
    std::snprintf(line, sizeof(line), "%lld ms",
                  static_cast<long long>(elapsed_ms));
    canvas_.Text(184, 202, line);
    canvas_.Text(28, 202, "LAST TIME:");
    std::snprintf(line, sizeof(line), "%s", esp_err_to_name(result));
    canvas_.Text(184, 232, line);
    canvas_.Text(28, 232, "RESULT:");
    return RefreshFull();
}

const char* ZectrixDemoUi::StateText(ZectrixTestState state) {
    switch (state) {
        case ZectrixTestState::kRunning: return "RUN";
        case ZectrixTestState::kPass: return "PASS";
        case ZectrixTestState::kFail: return "FAIL";
        default: return "WAIT";
    }
}

void ZectrixDemoUi::DrawTestStrip(
    ZectrixTestId current,
    const std::array<ZectrixTestState,
                     static_cast<size_t>(ZectrixTestId::kCount)>& states) {
    for (size_t i = 0; i < kTestOrder.size(); ++i) {
        const ZectrixTestId id = kTestOrder[i];
        const int left = static_cast<int>(i) * 400 /
                         static_cast<int>(kTestOrder.size());
        const int right = static_cast<int>(i + 1) * 400 /
                          static_cast<int>(kTestOrder.size());
        const int width = right - left;
        const bool selected = id == current;
        if (selected) {
            canvas_.FillRect(left, kHeaderHeight, width, kTestStripHeight,
                             true);
        } else {
            canvas_.Rect(left, kHeaderHeight, width, kTestStripHeight);
        }
        const char* name = kTestShortNames[i];
        const char* state = StateText(states[static_cast<size_t>(id)]);
        canvas_.Text(left + (width - canvas_.TextWidth(name)) / 2,
                     kHeaderHeight + 2, name, 1, selected);
        canvas_.Text(left + (width - canvas_.TextWidth(state)) / 2,
                     kHeaderHeight + 20, state, 1, selected);
    }
}

esp_err_t ZectrixDemoUi::ShowTestMenu(
    size_t selected,
    const std::array<ZectrixTestState,
                     static_cast<size_t>(ZectrixTestId::kCount)>& states,
    bool full_refresh) {
    const ZectrixTestId current = kTestOrder[std::min(selected, kTestOrder.size() - 1)];
    DrawFrame("HARDWARE TESTS", "UP/DOWN Move  OK Run  Hold OK Back");
    DrawTestStrip(current, states);
    canvas_.Text(20, 92, ZectrixSelfTest::Name(current), 2);
    canvas_.Line(20, 126, 379, 126);
    canvas_.Text(20, 142, "PRESS OK TO RUN THIS TEST");
    canvas_.Text(20, 176, "RESULT:");
    canvas_.Text(116, 176, StateText(states[static_cast<size_t>(current)]));
    canvas_.Text(20, 212, "RUN ALL TESTS IS AVAILABLE");
    canvas_.Text(20, 232, "FROM THE HARDWARE TEST MENU.");
    return full_refresh ? RefreshFull()
                        : RefreshPartial({0, 36, 400, 234});
}

esp_err_t ZectrixDemoUi::ShowTestUpdate(
    const ZectrixTestUpdate& update,
    const std::array<ZectrixTestState,
                     static_cast<size_t>(ZectrixTestId::kCount)>& states,
    bool force) {
    const int64_t now = esp_timer_get_time();
    const bool terminal = update.state == ZectrixTestState::kPass ||
                          update.state == ZectrixTestState::kFail;
    if (!force && !terminal && now - last_update_us_ < kUpdateThrottleUs) {
        return ESP_OK;
    }
    last_update_us_ = now;

    DrawFrame("HARDWARE TESTS", "Follow Prompt  Hold OK Cancel  Hold DOWN Off");
    DrawTestStrip(update.id, states);
    canvas_.FillRect(0, kHeaderHeight + kTestStripHeight, 400,
                     269 - kHeaderHeight - kTestStripHeight, false);
    canvas_.Text(kTestContentLeft, 86, update.title, 1);
    canvas_.FillRect(308, 82, 76, 25, true);
    canvas_.Text(314, 87, StateText(update.state), 1, true);
    canvas_.Line(kTestContentLeft, 112, kTestContentRight, 112);
    DrawFittedText(canvas_, kTestContentLeft, 122, update.hint,
                   kTestContentRight - kTestContentLeft);
    for (size_t i = 0; i < update.details.size(); ++i) {
        DrawFittedText(canvas_, kTestContentLeft,
                       154 + static_cast<int>(i) * 26,
                       update.details[i].data(),
                       kTestContentRight - kTestContentLeft);
    }
    return RefreshPartial({0, 36, 400, 234});
}

esp_err_t ZectrixDemoUi::ShowTestSummary(
    const std::array<ZectrixTestState,
                     static_cast<size_t>(ZectrixTestId::kCount)>& states) {
    DrawFrame("TEST SUMMARY", "Any Key Return   Hold DOWN Power Off");
    int passed = 0;
    int failed = 0;
    for (ZectrixTestState state : states) {
        passed += state == ZectrixTestState::kPass ? 1 : 0;
        failed += state == ZectrixTestState::kFail ? 1 : 0;
    }
    char line[64];
    std::snprintf(line, sizeof(line), "%d / 7 PASSED", passed);
    canvas_.TextCentered(52, line, 2);
    std::snprintf(line, sizeof(line), "%d FAILED", failed);
    canvas_.TextCentered(94, line, 1);
    for (size_t i = 0; i < kTestOrder.size(); ++i) {
        const int column = i < 4 ? 0 : 1;
        const int row = i < 4 ? static_cast<int>(i) : static_cast<int>(i - 4);
        const int x = 28 + column * 196;
        const int y = 132 + row * 30;
        const ZectrixTestId id = kTestOrder[i];
        std::snprintf(line, sizeof(line), "%-8.8s %s",
                      ZectrixSelfTest::Name(id),
                      StateText(states[static_cast<size_t>(id)]));
        canvas_.Text(x, y, line);
    }
    return RefreshFull();
}

esp_err_t ZectrixDemoUi::ShowDeviceInfo(
    const ZectrixPowerSnapshot& power, bool rtc_ready, bool nfc_ready,
    const char* mac, uint32_t flash_mb, uint32_t psram_mb) {
    DrawFrame("DEVICE INFO", "Hold OK Back   Hold DOWN Power Off");
    char line[80];
    const char* labels[] = {"MCU", "DISPLAY", "FLASH / PSRAM", "WI-FI MAC",
                            "RTC / NFC", "BATTERY", "USB / CHARGE"};
    const int ys[] = {48, 78, 108, 138, 168, 198, 228};
    for (int i = 0; i < 7; ++i) {
        canvas_.Text(18, ys[i], labels[i]);
    }
    canvas_.Text(176, ys[0], "ESP32-S3");
    canvas_.Text(176, ys[1], "400x300 1/4bpp");
    std::snprintf(line, sizeof(line), "%lu MB / %lu MB",
                  static_cast<unsigned long>(flash_mb),
                  static_cast<unsigned long>(psram_mb));
    canvas_.Text(176, ys[2], line);
    canvas_.Text(176, ys[3], mac);
    std::snprintf(line, sizeof(line), "%s / %s",
                  rtc_ready ? "READY" : "N/A", nfc_ready ? "READY" : "N/A");
    canvas_.Text(176, ys[4], line);
    std::snprintf(line, sizeof(line), "%u%%  %u mV",
                  power.battery_percent, power.battery_mv);
    canvas_.Text(176, ys[5], power.battery_valid ? line : "NOT AVAILABLE");
    std::snprintf(line, sizeof(line), "%s / %s",
                  power.charge.power_present ? "IN" : "OUT",
                  power.charge.charging ? "CHARGING" : "IDLE");
    canvas_.Text(176, ys[6], line);
    return RefreshFull();
}

esp_err_t ZectrixDemoUi::ShowAbout() {
    DrawFrame("ABOUT", "Hold OK Back   Hold DOWN Power Off");
    canvas_.TextCentered(54, "ZECTRIX HARDWARE SHOWCASE", 1);
    canvas_.TextCentered(88, "OPEN-SOURCE DEMONSTRATION", 1);
    canvas_.Line(44, 118, 355, 118);
    canvas_.TextCentered(138, "COPYRIGHT (C) 2026", 1);
    canvas_.TextCentered(164, "ZECTRIX LAB", 2);
    canvas_.TextCentered(210, "MIT LICENSE", 1);
    canvas_.TextCentered(238, "www.zectrix.com", 1);
    return RefreshFull();
}

esp_err_t ZectrixDemoUi::RefreshFull() {
    if (epd_ == nullptr) {
        return ESP_ERR_INVALID_STATE;
    }
    esp_err_t err = zectrix_epd_power_on(epd_);
    if (err == ESP_OK) {
        err = zectrix_epd_refresh_full_1bpp(epd_, canvas_.data(), canvas_.size());
    }
    const esp_err_t off = zectrix_epd_power_off(epd_);
    partial_count_ = 0;
    return err == ESP_OK ? off : err;
}

esp_err_t ZectrixDemoUi::RefreshPartial(const zectrix_epd_rect_t& rect) {
    if (epd_ == nullptr || rect.x < 0 || rect.y < 0 || rect.width <= 0 ||
        rect.height <= 0 || (rect.x & 7) != 0 || (rect.width & 7) != 0 ||
        rect.x + rect.width > 400 || rect.y + rect.height > 300) {
        return ESP_ERR_INVALID_ARG;
    }
    if (partial_count_ >= kPartialRefreshLimit) {
        return RefreshFull();
    }
    const size_t row_bytes = static_cast<size_t>(rect.width / 8);
    const size_t required = row_bytes * rect.height;
    if (required > partial_buffer_.size()) {
        return ESP_ERR_INVALID_SIZE;
    }
    for (int row = 0; row < rect.height; ++row) {
        const uint8_t* source = canvas_.data() +
            static_cast<size_t>(rect.y + row) * ZectrixCanvas::kStride + rect.x / 8;
        std::memcpy(partial_buffer_.data() + static_cast<size_t>(row) * row_bytes,
                    source, row_bytes);
    }
    esp_err_t err = zectrix_epd_power_on(epd_);
    if (err == ESP_OK) {
        err = zectrix_epd_refresh_partial_1bpp(
            epd_, &rect, partial_buffer_.data(), required);
    }
    const esp_err_t off = zectrix_epd_power_off(epd_);
    if (err == ESP_OK) {
        ++partial_count_;
        err = off;
    }
    return err;
}

esp_err_t ZectrixDemoUi::ClearDisplay() {
    canvas_.Clear();
    return RefreshFull();
}
