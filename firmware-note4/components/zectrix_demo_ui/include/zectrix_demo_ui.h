#ifndef ZECTRIX_DEMO_UI_H_
#define ZECTRIX_DEMO_UI_H_

#include <array>
#include <cstddef>
#include <cstdint>

#include "esp_err.h"
#include "zectrix_board.h"
#include "zectrix_canvas.h"
#include "zectrix_epd.h"
#include "zectrix_self_test.h"

class ZectrixDemoUi {
public:
    explicit ZectrixDemoUi(zectrix_epd_handle_t epd) : epd_(epd) {}
    void SetEpd(zectrix_epd_handle_t epd) { epd_ = epd; }

    esp_err_t ShowSplash();
    esp_err_t ShowMenu(const char* title, const char* const* items,
                       size_t count, size_t selected, const char* footer,
                       bool full_refresh);
    esp_err_t ShowSceneInfo(const char* title, const char* mode,
                            const char* format, size_t bytes,
                            int64_t elapsed_ms, esp_err_t result);
    esp_err_t ShowTestMenu(
        size_t selected,
        const std::array<ZectrixTestState,
                         static_cast<size_t>(ZectrixTestId::kCount)>& states,
        bool full_refresh);
    esp_err_t ShowTestUpdate(
        const ZectrixTestUpdate& update,
        const std::array<ZectrixTestState,
                         static_cast<size_t>(ZectrixTestId::kCount)>& states,
        bool force = false);
    esp_err_t ShowTestSummary(
        const std::array<ZectrixTestState,
                         static_cast<size_t>(ZectrixTestId::kCount)>& states);
    esp_err_t ShowDeviceInfo(const ZectrixPowerSnapshot& power,
                             bool rtc_ready, bool nfc_ready,
                             const char* mac, uint32_t flash_mb,
                             uint32_t psram_mb);
    esp_err_t ShowAbout();
    esp_err_t ClearDisplay();

    ZectrixCanvas& canvas() { return canvas_; }
    esp_err_t RefreshFull();
    esp_err_t RefreshPartial(const zectrix_epd_rect_t& rect);

private:
    void DrawFrame(const char* title, const char* footer);
    void DrawTestStrip(
        ZectrixTestId current,
        const std::array<ZectrixTestState,
                         static_cast<size_t>(ZectrixTestId::kCount)>& states);
    static const char* StateText(ZectrixTestState state);

    zectrix_epd_handle_t epd_ = nullptr;
    ZectrixCanvas canvas_;
    std::array<uint8_t, 50 * 300> partial_buffer_ = {};
    int partial_count_ = 0;
    int64_t last_update_us_ = 0;
};

#endif  // ZECTRIX_DEMO_UI_H_
