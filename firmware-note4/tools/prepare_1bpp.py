#!/usr/bin/env python3
"""Prepare a 400x300, packed 1bpp image for the Zectrix EPD demo."""

import argparse
from pathlib import Path

from PIL import Image, ImageOps


WIDTH = 400
HEIGHT = 300


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path, help="source image")
    parser.add_argument("preview", type=Path, help="black-and-white preview PNG")
    parser.add_argument("output", type=Path, help="packed 1bpp output")
    parser.add_argument(
        "--threshold",
        type=int,
        default=160,
        help="pixels below this value become black (default: 160)",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.threshold < 0 or args.threshold > 255:
        raise ValueError("threshold must be between 0 and 255")

    source = Image.open(args.input).convert("L")
    resized = ImageOps.fit(
        source,
        (WIDTH, HEIGHT),
        method=Image.Resampling.LANCZOS,
        centering=(0.5, 0.5),
    )
    resized = ImageOps.autocontrast(resized)
    pixels = bytes(
        0 if value < args.threshold else 1 for value in resized.tobytes()
    )

    preview = Image.frombytes(
        "L", (WIDTH, HEIGHT), bytes(255 if value else 0 for value in pixels)
    )
    packed = bytearray(WIDTH * HEIGHT // 8)
    for index, white in enumerate(pixels):
        if white:
            packed[index // 8] |= 1 << (7 - (index & 7))

    args.preview.parent.mkdir(parents=True, exist_ok=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    preview.save(args.preview, optimize=True)
    args.output.write_bytes(packed)
    black_pixels = len(pixels) - sum(pixels)
    print(
        f"wrote {args.preview} and {args.output} "
        f"({len(packed)} bytes, threshold={args.threshold}, "
        f"black={black_pixels * 100 / len(pixels):.1f}%)"
    )


if __name__ == "__main__":
    main()
