# Zectrix EPD component API

Copy `components/zectrix_epd` into an ESP-IDF 5.4+ project and add
`zectrix_epd` to the consuming component's `REQUIRES` list. The public API is
the C header `zectrix_epd.h`, so it can be called from C or C++.

## Lifecycle

```c
zectrix_epd_config_t config;
zectrix_epd_get_default_config(&config);

zectrix_epd_handle_t epd = NULL;
ESP_ERROR_CHECK(zectrix_epd_new(&config, &epd));
ESP_ERROR_CHECK(zectrix_epd_power_on(epd));

// Perform one or more valid refresh operations here.

ESP_ERROR_CHECK(zectrix_epd_power_off(epd));
ESP_ERROR_CHECK(zectrix_epd_del(epd));
```

`zectrix_epd_new()` configures GPIO and SPI but leaves the external display
rail off. All refresh functions are synchronous: they return after the BUSY
handshake completes or the configured timeout expires.

## Full 1bpp refresh

```c
uint8_t frame[ZECTRIX_EPD_1BPP_FRAME_BYTES];
memset(frame, 0xFF, sizeof(frame));  // White
ESP_ERROR_CHECK(zectrix_epd_refresh_full_1bpp(epd, frame, sizeof(frame)));
```

The image is 400 x 300, row-major and MSB first. `0` is black, `1` is white.
The buffer must be exactly 15,000 bytes.

## Partial 1bpp refresh

```c
zectrix_epd_rect_t rect = {.x = 80, .y = 96, .width = 64, .height = 32};
uint8_t patch[(64 / 8) * 32];
memset(patch, 0x00, sizeof(patch));
ESP_ERROR_CHECK(zectrix_epd_refresh_partial_1bpp(
    epd, &rect, patch, sizeof(patch)));
```

A successful full 1bpp refresh must establish the base image before any
partial update. The patch is tightly packed by row. Keep coordinates inside
the 400 x 300 panel and supply `ceil(width / 8) * height` bytes. Applications
should occasionally perform a full refresh to control ghosting.

## Full 4bpp refresh

```c
uint8_t gray[ZECTRIX_EPD_4BPP_FRAME_BYTES];
memset(gray, 0xFF, sizeof(gray));
ESP_ERROR_CHECK(zectrix_epd_refresh_full_4bpp(epd, gray, sizeof(gray)));
```

The image is 400 x 300 with two pixels per byte. The high nibble is the left
pixel. Values range from `0` black to `15` white. The buffer must be exactly
60,000 bytes.

For the cleanest transition, perform a white full 1bpp refresh before 4bpp.
After 4bpp, establish another full 1bpp base before using partial refresh.

## Error handling

The API returns standard `esp_err_t` values. Common errors include
`ESP_ERR_INVALID_ARG`, `ESP_ERR_INVALID_SIZE`, `ESP_ERR_INVALID_STATE` and
`ESP_ERR_TIMEOUT`. Avoid `ESP_ERROR_CHECK` in a long-running product UI if a
recoverable screen error should not reboot the device; log and handle the
return value instead.

## SPI ownership

The default configuration initializes the SPI bus. Set
`initialize_spi_bus = false` only when the application already owns and has
configured the selected SPI host with compatible pins and DMA settings.
