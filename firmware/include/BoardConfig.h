#pragma once

// Waveshare E-Paper ESP32 Driver Board (classic ESP32-WROOM-32E revision).
// Verify the silkscreen/pinout before flashing if your board is a newer revision.
constexpr int PIN_EPD_SCK = 13;
constexpr int PIN_EPD_MOSI = 14;
constexpr int PIN_EPD_CS = 15;
constexpr int PIN_EPD_DC = 27;
constexpr int PIN_EPD_RST = 26;
constexpr int PIN_EPD_BUSY = 25;
constexpr int PIN_BOOT_BUTTON = 0;

constexpr int DISPLAY_WIDTH = 648;
constexpr int DISPLAY_HEIGHT = 480;
constexpr size_t DISPLAY_BYTES = DISPLAY_WIDTH * DISPLAY_HEIGHT / 8;

