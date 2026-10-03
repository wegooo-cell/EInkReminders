#!/usr/bin/env python3
"""Render the five native-resolution monochrome snooze-menu selections."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "firmware-note4" / "main" / "snooze_menu_frames.bin"
FONT = ROOT / "macos" / "AppBundle" / "SourceHanSansSC-Regular.otf"
WIDTH, HEIGHT = 96, 128
LABELS = ("5分钟", "10分钟", "15分钟", "30分钟", "1小时")


def pack(image: Image.Image) -> bytes:
    pixels = image.load()
    output = bytearray([0xFF] * (WIDTH * HEIGHT // 8))
    for y in range(HEIGHT):
        for x in range(WIDTH):
            if pixels[x, y] == 0:
                output[(y * WIDTH + x) // 8] &= ~(0x80 >> (x & 7))
    return bytes(output)


def main() -> None:
    font = ImageFont.truetype(str(FONT), 13)
    output = bytearray()
    for selected in range(len(LABELS)):
        image = Image.new("1", (WIDTH, HEIGHT), 1)
        draw = ImageDraw.Draw(image)
        draw.rounded_rectangle((0, 0, WIDTH - 1, 119), radius=10, fill=1,
                               outline=0, width=2)
        for index, label in enumerate(LABELS):
            top = 5 + index * 22
            if index == selected:
                draw.rounded_rectangle((5, top, WIDTH - 6, top + 20),
                                       radius=8, fill=0)
            box = draw.textbbox((0, 0), label, font=font)
            x = (WIDTH - (box[2] - box[0])) // 2 - box[0]
            y = top + (20 - (box[3] - box[1])) // 2 - box[1]
            draw.text((x, y), label, font=font,
                      fill=1 if index == selected else 0)
        # A thin white pointer like the preview, connected to the panel.
        draw.line(((41, 119), (48, 126), (55, 119)), fill=0, width=2)
        output.extend(pack(image))
    OUTPUT.write_bytes(output)
    print(f"wrote {OUTPUT} ({len(output)} bytes)")


if __name__ == "__main__":
    main()
