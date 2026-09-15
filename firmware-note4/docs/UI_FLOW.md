# UI interaction specification

## Design goals

- Demonstrate capability before implementation detail.
- Keep every screen readable in black and white without antialiasing.
- Reserve partial refresh for small, repeated state changes.
- Keep shutdown accessible without adding a dedicated settings screen.

## Navigation model

UP and DOWN change selection as soon as the debounced press is detected. OK
confirms on release, a 1.5-second OK hold returns or cancels, and a 3-second
DOWN hold requests global shutdown. Selection wraps at the top and bottom of
each menu.

The home menu contains:

1. **AUTO SHOWCASE** — unattended rotation of all three display modes.
2. **DISPLAY GALLERY** — individual display demonstrations and measurements.
3. **HARDWARE TESTS** — run all tests or choose one test.
4. **DEVICE INFO** — live board and power information.
5. **ABOUT & LICENSE** — project ownership and license.

After 15 seconds of home-screen inactivity, Auto Showcase starts. Any click
leaves the unattended sequence at the next safe point.

## Refresh policy

- Splash, page changes, scene reports and summaries use full 1bpp refresh.
- Menu selection and live test content use partial 1bpp refresh.
- After eight UI partial refreshes, the next update is promoted to full refresh.
- Test updates are throttled to 500 ms unless a PASS/FAIL state must be shown.
- Full 4bpp content is preceded by a white full 1bpp refresh.

## Display gallery

Each scene displays content first, then an information page with refresh mode,
pixel format, frame-buffer bytes, measured duration and ESP-IDF result name.

| Scene | Initial operation | Animated operation |
| --- | --- | --- |
| Lighthouse | Full 1bpp image | None |
| Footprints | Full 1bpp snowy path | Six cumulative partial 1bpp steps |
| Mountain | White full 1bpp clear | Full 4bpp, 16-gray image |

## Hardware-test screen

A full-width strip below the page title shows all seven tests and their
WAIT/RUN/PASS/FAIL state. The selected test uses an inverted cell. Instructions
and measurements use the full content width below the strip; exceptionally long
runtime values are shortened with an ellipsis instead of running off-screen.
Interactive tests use explicit operator prompts. Long OK cancels the active
test; long DOWN retains its global shutdown meaning.

## Shutdown sequence

1. Perform a white full 1bpp refresh and wait for completion.
2. Power off the display through the driver.
3. Turn off the indicator LED and audio rail.
4. Release the battery power latch.
5. Enter deep sleep as a USB-powered fallback.
