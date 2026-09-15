# 墨水屏提醒事项 firmware for ZECTRIX NOTE4

[中文](README_zh.md) | English

This ESP-IDF firmware ports the local Apple Reminders bridge to the monochrome
ZECTRIX NOTE4 (ESP32-S3, 400 × 300 SSD2683). It retains the board, display and
button drivers from ZECTRIX Lab's MIT-licensed reference demo.

Controls: UP selects the previous item, DOWN selects the next item, and a short
OK click confirms the selected reminder. UP/DOWN wrap at either end. The Mac
bridge sends only the active view and renders selection frames on demand;
small screen changes use partial refreshes with periodic full refreshes.

Build with ESP-IDF 5.4 or newer:

```bash
idf.py set-target esp32s3
idf.py build
idf.py -p /dev/cu.usbmodemXXXX flash monitor
```

On first boot, scan the Wi-Fi QR code shown on the NOTE4 with an iPhone, then
choose a 2.4 GHz network in the Chinese captive portal. If the portal does not
open automatically, visit `http://192.168.4.1`. Credentials are saved only
after a successful connection. This target is for the monochrome NOTE4 only,
not NOTE4C.

Upstream: <https://github.com/itopinion/zectrix-note4-epd-demo>. The original
MIT license and third-party notices are preserved in this directory.
