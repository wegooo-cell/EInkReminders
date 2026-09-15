#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIRMWARE_DIR="$(cd "${SCRIPT_DIR}/../firmware" && pwd)"
BUILD_DIR="${FIRMWARE_DIR}/.pio/build/waveshare_epaper_esp32"
OUTPUT_BIN="${SCRIPT_DIR}/dist/firmware/eink-reminders-esp32.bin"
PIO_DATA_DIR="${PLATFORMIO_CORE_DIR:-${HOME}/.platformio}"
FRAMEWORK_DIR="${PIO_DATA_DIR}/packages/framework-arduinoespressif32"
ESPTOOL="${PIO_DATA_DIR}/packages/tool-esptoolpy/esptool.py"
PIO_BIN="$(command -v pio || true)"
if [[ -z "${PIO_BIN}" ]]; then
  PIO_BIN="${PIO_DATA_DIR}/penv/bin/platformio"
fi
if [[ ! -x "${PIO_BIN}" ]]; then
  echo "PlatformIO not found: ${PIO_BIN}" >&2
  exit 1
fi
PIO_PYTHON="$(dirname "${PIO_BIN}")/python"

cd "${FIRMWARE_DIR}"
"${PIO_BIN}" run

"${PIO_PYTHON}" "${ESPTOOL}" --chip esp32 merge_bin \
  -o "${OUTPUT_BIN}" \
  --flash_mode dio \
  --flash_freq 40m \
  --flash_size 4MB \
  0x1000 "${BUILD_DIR}/bootloader.bin" \
  0x8000 "${BUILD_DIR}/partitions.bin" \
  0xe000 "${FRAMEWORK_DIR}/tools/partitions/boot_app0.bin" \
  0x10000 "${BUILD_DIR}/firmware.bin"

echo "Web firmware ready: ${OUTPUT_BIN}"
