#!/usr/bin/env python3
"""Prepare a 400x300, packed 4bpp image for the Zectrix EPD demo."""

import argparse
from pathlib import Path

from PIL import Image, ImageEnhance, ImageOps


WIDTH = 400
HEIGHT = 300


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path, help="source image")
    parser.add_argument("preview", type=Path, help="16-gray preview PNG")
    parser.add_argument("output", type=Path, help="packed 4bpp output")
    parser.add_argument(
        "--contrast",
        type=float,
        default=1.55,
        help="contrast multiplier applied before quantization (default: 1.55)",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.contrast <= 0:
        raise ValueError("contrast must be greater than zero")
    source = Image.open(args.input).convert("L")
    resized = ImageOps.fit(
        source,
        (WIDTH, HEIGHT),
        method=Image.Resampling.LANCZOS,
        centering=(0.5, 0.5),
    )
    resized = ImageOps.autocontrast(resized)
    resized = ImageEnhance.Contrast(resized).enhance(args.contrast)

    levels = [(value * 15 + 127) // 255 for value in resized.tobytes()]
    preview = Image.frombytes(
        "L", (WIDTH, HEIGHT), bytes(level * 17 for level in levels)
    )
    packed = bytearray()
    for index in range(0, len(levels), 2):
        packed.append((levels[index] << 4) | levels[index + 1])

    args.preview.parent.mkdir(parents=True, exist_ok=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    preview.save(args.preview, optimize=True)
    args.output.write_bytes(packed)
    print(
        f"wrote {args.preview} and {args.output} "
        f"({len(packed)} bytes, levels={len(set(levels))}, "
        f"contrast={args.contrast:.2f})"
    )


if __name__ == "__main__":
    main()
