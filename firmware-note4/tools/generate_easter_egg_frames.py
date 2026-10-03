#!/usr/bin/env python3
"""Pack the four full-screen Apple-inspired animations for NOTE4."""

from pathlib import Path

from PIL import Image, ImageSequence


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "firmware-note4" / "main" / "easter_egg_frames.bin"
WIDTH = 400
HEIGHT = 300
FRAME_BYTES = WIDTH * HEIGHT // 8

ANIMATIONS = (
    ROOT / "previews" / "apple-pixel-macintosh-boot-v2.gif",
    ROOT / "previews" / "apple-pixel-macintosh-blink-v2.gif",
    ROOT / "previews" / "apple-pixel-hello.gif",
    ROOT / "previews" / "apple-pixel-mac-wallpaper.gif",
)


def pack_frame(image: Image.Image) -> bytes:
    if image.size != (WIDTH, HEIGHT):
        raise RuntimeError(f"unexpected frame size {image.size}")
    mono = image.convert("L").point(lambda value: 0 if value < 128 else 255, "1")
    pixels = mono.load()
    packed = bytearray([0xFF] * FRAME_BYTES)
    stride = WIDTH // 8
    for y in range(HEIGHT):
        row = y * stride
        for x in range(WIDTH):
            if pixels[x, y] == 0:
                packed[row + x // 8] &= ~(0x80 >> (x & 7))
    return bytes(packed)


def main() -> None:
    output = bytearray()
    for path in ANIMATIONS:
        animation = Image.open(path)
        frames = [frame.copy() for frame in ImageSequence.Iterator(animation)]
        if len(frames) != 6:
            raise RuntimeError(f"{path.name}: expected 6 frames, found {len(frames)}")
        for frame in frames:
            output.extend(pack_frame(frame))
    expected = len(ANIMATIONS) * 6 * FRAME_BYTES
    if len(output) != expected:
        raise RuntimeError(f"unexpected packed size {len(output)} != {expected}")
    OUTPUT.write_bytes(output)
    print(f"wrote {OUTPUT} ({len(output)} bytes, {len(ANIMATIONS)} animations)")


if __name__ == "__main__":
    main()
