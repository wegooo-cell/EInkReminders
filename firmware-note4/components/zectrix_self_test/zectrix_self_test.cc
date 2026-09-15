#include "zectrix_self_test.h"

#include <algorithm>
#include <array>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include "acoustic_selftest.h"
#include "audio_codec.h"
#include "driver/gpio.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_netif.h"
#include "esp_timer.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs_flash.h"
#include "rtc_pcf8563.h"
#include "zectrix_board.h"
#include "zectrix_board_config.h"
#include "zectrix_nfc.h"

namespace {

constexpr char kTag[] = "zectrix_test";
constexpr int kRfRequiredHits = 3;
constexpr int64_t kInteractiveTimeoutUs = 60LL * 1000 * 1000;

void SetText(char* target, size_t size, const char* format, ...) {
    va_list args;
    va_start(args, format);
    std::vsnprintf(target, size, format, args);
    va_end(args);
}

ZectrixTestUpdate MakeUpdate(ZectrixTestId id, ZectrixTestState state,
                             const char* hint) {
    ZectrixTestUpdate update;
    update.id = id;
    update.state = state;
    SetText(update.title, sizeof(update.title), "%s TEST",
            ZectrixSelfTest::Name(id));
    SetText(update.hint, sizeof(update.hint), "%s", hint ? hint : "");
    return update;
}

void Publish(const ZectrixSelfTest::UpdateCallback& callback,
             const ZectrixTestUpdate& update) {
    if (callback) {
        callback(update);
    }
}

bool IsCancelOrShutdown(ZectrixBoard* board, TickType_t timeout,
                        ZectrixTestResult* result,
                        ZectrixButtonEvent* received = nullptr) {
    ZectrixButtonEvent event;
    if (!board->WaitButton(&event, timeout)) {
        return false;
    }
    if (received != nullptr) {
        *received = event;
    }
    if (event.button == ZectrixButton::kDown &&
        event.action == ZectrixButtonAction::kLongPress) {
        *result = ZectrixTestResult::kShutdown;
        return true;
    }
    if (event.button == ZectrixButton::kOk &&
        event.action == ZectrixButtonAction::kLongPress) {
        *result = ZectrixTestResult::kCancelled;
        return true;
    }
    return false;
}

esp_err_t EnsureWifiReady() {
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES ||
        err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        err = nvs_flash_erase();
        if (err == ESP_OK) {
            err = nvs_flash_init();
        }
    }
    if (err != ESP_OK) {
        return err;
    }
    err = esp_netif_init();
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        return err;
    }
    err = esp_event_loop_create_default();
    if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) {
        return err;
    }

    static bool wifi_initialized = false;
    if (!wifi_initialized) {
        wifi_init_config_t config = WIFI_INIT_CONFIG_DEFAULT();
        err = esp_wifi_init(&config);
        if (err != ESP_OK) {
            return err;
        }
        wifi_initialized = true;
    }
    esp_wifi_set_storage(WIFI_STORAGE_RAM);
    err = esp_wifi_set_mode(WIFI_MODE_STA);
    if (err == ESP_OK) {
        err = esp_wifi_start();
    }
    return err == ESP_ERR_WIFI_CONN ? ESP_OK : err;
}

std::vector<uint8_t> BuildUriNdef(const std::string& uri) {
    uint8_t prefix = 0x00;
    std::string suffix = uri;
    if (uri.rfind("https://www.", 0) == 0) {
        prefix = 0x02;
        suffix = uri.substr(12);
    } else if (uri.rfind("https://", 0) == 0) {
        prefix = 0x04;
        suffix = uri.substr(8);
    } else if (uri.rfind("http://www.", 0) == 0) {
        prefix = 0x01;
        suffix = uri.substr(11);
    } else if (uri.rfind("http://", 0) == 0) {
        prefix = 0x03;
        suffix = uri.substr(7);
    }
    std::vector<uint8_t> payload = {prefix};
    payload.insert(payload.end(), suffix.begin(), suffix.end());
    std::vector<uint8_t> message = {
        0xD1, 0x01, static_cast<uint8_t>(payload.size()), 'U'};
    message.insert(message.end(), payload.begin(), payload.end());
    return message;
}

std::vector<uint8_t> BuildNdefStorage(const std::vector<uint8_t>& message) {
    std::vector<uint8_t> data = {0x03, static_cast<uint8_t>(message.size())};
    data.insert(data.end(), message.begin(), message.end());
    data.push_back(0xFE);
    return data;
}

}  // namespace

const char* ZectrixSelfTest::Name(ZectrixTestId id) {
    switch (id) {
        case ZectrixTestId::kRf: return "WI-FI RF";
        case ZectrixTestId::kAudio: return "AUDIO";
        case ZectrixTestId::kRtc: return "RTC";
        case ZectrixTestId::kCharge: return "POWER";
        case ZectrixTestId::kLed: return "LED";
        case ZectrixTestId::kButtons: return "BUTTONS";
        case ZectrixTestId::kNfc: return "NFC";
        default: return "UNKNOWN";
    }
}

ZectrixTestResult ZectrixSelfTest::Run(
    ZectrixTestId id, const UpdateCallback& callback) {
    if (board_ == nullptr) {
        return ZectrixTestResult::kFail;
    }
    board_->DrainButtons();
    switch (id) {
        case ZectrixTestId::kRf: return RunRf(callback);
        case ZectrixTestId::kAudio: return RunAudio(callback);
        case ZectrixTestId::kRtc: return RunRtc(callback);
        case ZectrixTestId::kCharge: return RunCharge(callback);
        case ZectrixTestId::kLed: return RunLed(callback);
        case ZectrixTestId::kButtons: return RunButtons(callback);
        case ZectrixTestId::kNfc: return RunNfc(callback);
        default: return ZectrixTestResult::kFail;
    }
}

ZectrixTestResult ZectrixSelfTest::RunRf(const UpdateCallback& callback) {
    auto update = MakeUpdate(ZectrixTestId::kRf, ZectrixTestState::kRunning,
                             "Scanning 2.4 GHz access points...");
    Publish(callback, update);
    const esp_err_t init = EnsureWifiReady();
    if (init != ESP_OK) {
        update.state = ZectrixTestState::kFail;
        SetText(update.hint, sizeof(update.hint), "Wi-Fi init failed");
        SetText(update.details[0].data(), update.details[0].size(), "%s",
                esp_err_to_name(init));
        Publish(callback, update);
        return ZectrixTestResult::kFail;
    }

    const char* target = CONFIG_ZECTRIX_DEMO_RF_TARGET_SSID;
    const bool qualification = target[0] != '\0';
    int consecutive_hits = 0;
    const int64_t deadline = esp_timer_get_time() + kInteractiveTimeoutUs;
    while (esp_timer_get_time() < deadline) {
        wifi_scan_config_t scan = {};
        scan.show_hidden = true;
        scan.scan_type = WIFI_SCAN_TYPE_ACTIVE;
        const esp_err_t scan_result = esp_wifi_scan_start(&scan, true);
        uint16_t count = 0;
        if (scan_result == ESP_OK) {
            esp_wifi_scan_get_ap_num(&count);
        }
        std::vector<wifi_ap_record_t> records(count);
        if (count > 0) {
            esp_wifi_scan_get_ap_records(&count, records.data());
        }

        int best_rssi = -127;
        std::string best_name;
        bool target_found = false;
        for (const auto& record : records) {
            const char* ssid = reinterpret_cast<const char*>(record.ssid);
            if (record.rssi > best_rssi) {
                best_rssi = record.rssi;
                best_name = ssid;
            }
            if (qualification && std::strcmp(ssid, target) == 0) {
                target_found = true;
                best_rssi = record.rssi;
                best_name = ssid;
                break;
            }
        }

        const bool hit = qualification
                             ? target_found &&
                                   best_rssi >= CONFIG_ZECTRIX_DEMO_RF_THRESHOLD_DBM
                             : count > 0;
        consecutive_hits = hit ? consecutive_hits + 1 : 0;
        SetText(update.details[0].data(), update.details[0].size(),
                "MODE: %s", qualification ? "QUALIFICATION" : "GENERIC SCAN");
        SetText(update.details[1].data(), update.details[1].size(),
                "AP COUNT: %u", static_cast<unsigned>(count));
        SetText(update.details[2].data(), update.details[2].size(),
                "BEST: %s", best_name.empty() ? "NOT FOUND" : best_name.c_str());
        SetText(update.details[3].data(), update.details[3].size(),
                "RSSI: %d dBm   HITS: %d/%d", best_rssi, consecutive_hits,
                qualification ? kRfRequiredHits : 1);
        Publish(callback, update);

        if ((!qualification && hit) ||
            consecutive_hits >= kRfRequiredHits) {
            esp_wifi_stop();
            update.state = ZectrixTestState::kPass;
            SetText(update.hint, sizeof(update.hint), "Wi-Fi radio is operational");
            Publish(callback, update);
            return ZectrixTestResult::kPass;
        }
        ZectrixTestResult control;
        if (IsCancelOrShutdown(board_, pdMS_TO_TICKS(250), &control)) {
            esp_wifi_stop();
            return control;
        }
    }
    esp_wifi_stop();
    update.state = ZectrixTestState::kFail;
    SetText(update.hint, sizeof(update.hint), "RF test timed out");
    Publish(callback, update);
    return ZectrixTestResult::kFail;
}

ZectrixTestResult ZectrixSelfTest::RunAudio(const UpdateCallback& callback) {
    auto update = MakeUpdate(ZectrixTestId::kAudio,
                             ZectrixTestState::kRunning,
                             "Playing, recording and decoding AFSK...");
    Publish(callback, update);
    std::array<uint8_t, 6> mac = {};
    esp_read_mac(mac.data(), ESP_MAC_WIFI_STA);
    AudioCodec* codec = board_->PrepareAudio();
    const AcousticSelftestSummary summary = AcousticSelftest().Run(codec, mac);
    update.state = summary.pass ? ZectrixTestState::kPass
                                : ZectrixTestState::kFail;
    SetText(update.hint, sizeof(update.hint), "%s",
            summary.pass ? "Speaker and microphone loopback passed"
                         : "Audio loopback failed");
    SetText(update.details[0].data(), update.details[0].size(),
            "RESULT: %s", summary.pass ? "PASS" : "FAIL");
    SetText(update.details[1].data(), update.details[1].size(),
            "ROUND: %d", summary.round);
    SetText(update.details[2].data(), update.details[2].size(),
            "CENTER FREQUENCY: %d Hz", summary.fc);
    SetText(update.details[3].data(), update.details[3].size(),
            "REASON: %s", AcousticSelftest::FailureReasonToString(summary.reason));
    Publish(callback, update);
    return summary.pass ? ZectrixTestResult::kPass
                        : ZectrixTestResult::kFail;
}

ZectrixTestResult ZectrixSelfTest::RunRtc(const UpdateCallback& callback) {
    auto update = MakeUpdate(ZectrixTestId::kRtc,
                             ZectrixTestState::kRunning,
                             "Waiting for a 1 second RTC interrupt...");
    Publish(callback, update);
    RtcPcf8563* rtc = board_->rtc();
    if (rtc == nullptr) {
        update.state = ZectrixTestState::kFail;
        SetText(update.hint, sizeof(update.hint), "PCF8563 was not detected");
        Publish(callback, update);
        return ZectrixTestResult::kFail;
    }

    for (int attempt = 1; attempt <= 3; ++attempt) {
        bool fired = false;
        if (rtc->StartCountdownTimer(1)) {
            const int64_t deadline = esp_timer_get_time() + 2000000;
            while (esp_timer_get_time() < deadline) {
                const bool gpio_hit = gpio_get_level(ZECTRIX_RTC_INT) == 0;
                const bool flag_hit = rtc->IsTimerFired();
                SetText(update.details[0].data(), update.details[0].size(),
                        "ATTEMPT: %d/3", attempt);
                SetText(update.details[1].data(), update.details[1].size(),
                        "INT GPIO: %s", gpio_hit ? "ACTIVE" : "WAIT");
                SetText(update.details[2].data(), update.details[2].size(),
                        "TIMER FLAG: %s", flag_hit ? "SET" : "CLEAR");
                Publish(callback, update);
                if (gpio_hit || flag_hit) {
                    fired = true;
                    break;
                }
                ZectrixTestResult control;
                if (IsCancelOrShutdown(board_, pdMS_TO_TICKS(50), &control)) {
                    rtc->StopCountdownTimer();
                    return control;
                }
            }
        }
        rtc->StopCountdownTimer();
        rtc->ClearTimerFlag();
        if (fired) {
            update.state = ZectrixTestState::kPass;
            SetText(update.hint, sizeof(update.hint), "RTC timer interrupt passed");
            Publish(callback, update);
            return ZectrixTestResult::kPass;
        }
    }
    update.state = ZectrixTestState::kFail;
    SetText(update.hint, sizeof(update.hint), "RTC timer did not fire");
    Publish(callback, update);
    return ZectrixTestResult::kFail;
}

ZectrixTestResult ZectrixSelfTest::RunCharge(const UpdateCallback& callback) {
    auto update = MakeUpdate(ZectrixTestId::kCharge,
                             ZectrixTestState::kRunning,
                             "Connect USB power to verify charging");
    const int64_t deadline = esp_timer_get_time() + kInteractiveTimeoutUs;
    while (esp_timer_get_time() < deadline) {
        const ZectrixPowerSnapshot power = board_->ReadPowerSnapshot();
        SetText(update.details[0].data(), update.details[0].size(),
                "USB POWER: %s", power.charge.power_present ? "PRESENT" : "ABSENT");
        SetText(update.details[1].data(), update.details[1].size(),
                "CHARGING: %s   FULL: %s",
                power.charge.charging ? "YES" : "NO",
                power.charge.full ? "YES" : "NO");
        SetText(update.details[2].data(), update.details[2].size(),
                "BATTERY: %s%u%%", power.battery_valid ? "" : "-- / ",
                power.battery_valid ? power.battery_percent : 0);
        SetText(update.details[3].data(), update.details[3].size(),
                "VOLTAGE: %u mV%s", power.battery_mv,
                power.charge.no_battery ? "  NO BATTERY" : "");
        Publish(callback, update);
        const bool pass = power.charge.charging ||
                          (power.charge.full && power.battery_valid &&
                           power.battery_percent > 97);
        if (pass && !power.charge.no_battery) {
            update.state = ZectrixTestState::kPass;
            SetText(update.hint, sizeof(update.hint), "Power and charging path passed");
            Publish(callback, update);
            return ZectrixTestResult::kPass;
        }
        if (power.charge.fault) {
            break;
        }
        ZectrixTestResult control;
        if (IsCancelOrShutdown(board_, pdMS_TO_TICKS(300), &control)) {
            return control;
        }
    }
    update.state = ZectrixTestState::kFail;
    SetText(update.hint, sizeof(update.hint), "Charging was not detected");
    Publish(callback, update);
    return ZectrixTestResult::kFail;
}

ZectrixTestResult ZectrixSelfTest::RunLed(const UpdateCallback& callback) {
    auto update = MakeUpdate(ZectrixTestId::kLed,
                             ZectrixTestState::kRunning,
                             "Is the power LED blinking?");
    SetText(update.details[0].data(), update.details[0].size(),
            "LED GPIO: 3");
    SetText(update.details[1].data(), update.details[1].size(),
            "OK = PASS");
    SetText(update.details[2].data(), update.details[2].size(),
            "DOWN = FAIL");
    Publish(callback, update);
    bool led_on = false;
    TickType_t last_toggle = xTaskGetTickCount();
    const int64_t deadline = esp_timer_get_time() + kInteractiveTimeoutUs;
    while (esp_timer_get_time() < deadline) {
        const TickType_t now = xTaskGetTickCount();
        if (now - last_toggle >= pdMS_TO_TICKS(500)) {
            led_on = !led_on;
            board_->SetPowerLed(led_on);
            last_toggle = now;
        }
        ZectrixButtonEvent event;
        if (!board_->WaitButton(&event, pdMS_TO_TICKS(50))) {
            continue;
        }
        if (event.button == ZectrixButton::kDown &&
            event.action == ZectrixButtonAction::kLongPress) {
            board_->SetPowerLed(false);
            return ZectrixTestResult::kShutdown;
        }
        if (event.button == ZectrixButton::kOk &&
            event.action == ZectrixButtonAction::kLongPress) {
            board_->SetPowerLed(false);
            return ZectrixTestResult::kCancelled;
        }
        if (event.action == ZectrixButtonAction::kClick &&
            event.button == ZectrixButton::kOk) {
            board_->SetPowerLed(false);
            update.state = ZectrixTestState::kPass;
            SetText(update.hint, sizeof(update.hint), "LED confirmed by operator");
            Publish(callback, update);
            return ZectrixTestResult::kPass;
        }
        if (event.action == ZectrixButtonAction::kClick &&
            event.button == ZectrixButton::kDown) {
            board_->SetPowerLed(false);
            update.state = ZectrixTestState::kFail;
            SetText(update.hint, sizeof(update.hint), "LED rejected by operator");
            Publish(callback, update);
            return ZectrixTestResult::kFail;
        }
    }
    board_->SetPowerLed(false);
    update.state = ZectrixTestState::kFail;
    SetText(update.hint, sizeof(update.hint), "LED confirmation timed out");
    Publish(callback, update);
    return ZectrixTestResult::kFail;
}

ZectrixTestResult ZectrixSelfTest::RunButtons(const UpdateCallback& callback) {
    auto update = MakeUpdate(ZectrixTestId::kButtons,
                             ZectrixTestState::kRunning,
                             "Press the requested buttons in order");
    constexpr std::array<ZectrixButton, 3> sequence = {
        ZectrixButton::kOk, ZectrixButton::kUp, ZectrixButton::kDown};
    constexpr std::array<const char*, 3> names = {"OK", "UP", "DOWN"};
    size_t stage = 0;
    const int64_t deadline = esp_timer_get_time() + kInteractiveTimeoutUs;
    while (stage < sequence.size() && esp_timer_get_time() < deadline) {
        for (size_t i = 0; i < names.size(); ++i) {
            SetText(update.details[i].data(), update.details[i].size(),
                    "%s  %s", i < stage ? "PASS" : (i == stage ? ">>" : "--"),
                    names[i]);
        }
        Publish(callback, update);
        ZectrixButtonEvent event;
        if (!board_->WaitButton(&event, pdMS_TO_TICKS(200))) {
            continue;
        }
        if (event.button == ZectrixButton::kDown &&
            event.action == ZectrixButtonAction::kLongPress) {
            return ZectrixTestResult::kShutdown;
        }
        if (event.button == ZectrixButton::kOk &&
            event.action == ZectrixButtonAction::kLongPress) {
            return ZectrixTestResult::kCancelled;
        }
        if (event.action != ZectrixButtonAction::kClick) {
            continue;
        }
        if (event.button == sequence[stage]) {
            ++stage;
        } else {
            stage = 0;
            SetText(update.hint, sizeof(update.hint),
                    "Wrong order - sequence restarted");
        }
    }
    update.state = stage == sequence.size() ? ZectrixTestState::kPass
                                            : ZectrixTestState::kFail;
    SetText(update.hint, sizeof(update.hint), "%s",
            stage == sequence.size() ? "All three buttons passed"
                                     : "Button test timed out");
    Publish(callback, update);
    return stage == sequence.size() ? ZectrixTestResult::kPass
                                    : ZectrixTestResult::kFail;
}

ZectrixTestResult ZectrixSelfTest::RunNfc(const UpdateCallback& callback) {
    auto update = MakeUpdate(ZectrixTestId::kNfc,
                             ZectrixTestState::kRunning,
                             "Backing up NFC memory...");
    Publish(callback, update);
    ZectrixNfc* nfc = board_->nfc();
    if (nfc == nullptr) {
        update.state = ZectrixTestState::kFail;
        SetText(update.hint, sizeof(update.hint), "NFC device was not detected");
        Publish(callback, update);
        return ZectrixTestResult::kFail;
    }

    std::vector<uint8_t> backup(nfc->GetUserDataCapacity());
    if (nfc->ReadUserData(0, backup.data(), backup.size()) != ESP_OK) {
        update.state = ZectrixTestState::kFail;
        SetText(update.hint, sizeof(update.hint), "Could not back up NFC memory");
        Publish(callback, update);
        return ZectrixTestResult::kFail;
    }

    const std::string url = CONFIG_ZECTRIX_DEMO_NFC_URL;
    const std::vector<uint8_t> expected_ndef = BuildUriNdef(url);
    const std::vector<uint8_t> expected_raw = BuildNdefStorage(expected_ndef);
    SetText(update.hint, sizeof(update.hint), "Writing and verifying NDEF URL...");
    SetText(update.details[0].data(), update.details[0].size(), "URL: %s", url.c_str());
    Publish(callback, update);

    const esp_err_t write = nfc->WriteUriNdef(url);
    std::vector<uint8_t> actual_raw(expected_raw.size());
    std::vector<uint8_t> actual_ndef;
    const esp_err_t raw_read = write == ESP_OK
                                   ? nfc->ReadUserData(0, actual_raw.data(), actual_raw.size())
                                   : write;
    const esp_err_t ndef_read = raw_read == ESP_OK
                                    ? nfc->ReadNdef(&actual_ndef)
                                    : raw_read;
    const bool verified = write == ESP_OK && raw_read == ESP_OK &&
                          ndef_read == ESP_OK && actual_raw == expected_raw &&
                          actual_ndef == expected_ndef;
    SetText(update.details[1].data(), update.details[1].size(),
            "WRITE: %s", esp_err_to_name(write));
    SetText(update.details[2].data(), update.details[2].size(),
            "RAW + NDEF: %s", verified ? "VERIFIED" : "FAILED");
    Publish(callback, update);
    if (!verified) {
        nfc->WriteUserData(0, backup.data(), backup.size());
        update.state = ZectrixTestState::kFail;
        SetText(update.hint, sizeof(update.hint), "NFC write/read verification failed");
        Publish(callback, update);
        return ZectrixTestResult::kFail;
    }

    SetText(update.hint, sizeof(update.hint), "Tap a phone on the NFC antenna");
    const int64_t deadline = esp_timer_get_time() + kInteractiveTimeoutUs;
    int stable = 0;
    while (esp_timer_get_time() < deadline && stable < 3) {
        const bool field = nfc->HasField();
        stable = field ? stable + 1 : 0;
        SetText(update.details[3].data(), update.details[3].size(),
                "PHONE FIELD: %s  %d/3", field ? "DETECTED" : "WAIT", stable);
        Publish(callback, update);
        ZectrixTestResult control;
        if (IsCancelOrShutdown(board_, pdMS_TO_TICKS(200), &control)) {
            nfc->WriteUserData(0, backup.data(), backup.size());
            return control;
        }
    }

    const esp_err_t restore = nfc->WriteUserData(0, backup.data(), backup.size());
    const bool pass = stable >= 3 && restore == ESP_OK;
    update.state = pass ? ZectrixTestState::kPass
                        : ZectrixTestState::kFail;
    SetText(update.hint, sizeof(update.hint), "%s",
            pass ? "NFC passed; original data restored"
                 : (stable < 3 ? "Phone field was not detected"
                               : "NFC passed but restore failed"));
    SetText(update.details[3].data(), update.details[3].size(),
            "RESTORE: %s", esp_err_to_name(restore));
    Publish(callback, update);
    return pass ? ZectrixTestResult::kPass : ZectrixTestResult::kFail;
}
