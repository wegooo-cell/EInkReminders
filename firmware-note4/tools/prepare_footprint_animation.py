#!/usr/bin/env python3
"""Build deterministic partial-refresh patches for the footprint scene."""

import argparse
import math
from pathlib import Path
import struct

from PIL import Image, ImageChops, ImageOps


WIDTH = 400
HEIGHT = 300
THRESHOLD = 160
SPRITE_WIDTH = 64
SPRITE_HEIGHT = 160
MAGIC = b"ZFP1"

CENTERLINE = [
    (125, 284),
    (146, 258),
    (162, 232),
    (181, 207),
    (199, 184),
    (219, 163),
]
HEIGHTS = [48, 45, 42, 39, 36, 33]
OFFSETS = [11, 10, 9, 8, 7, 6]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("background", type=Path, help="400x300 1bpp background")
    parser.add_argument("boot_source", type=Path, help="isolated boot-print image")
    parser.add_argument("boot_output", type=Path, help="normalized 1bpp boot sprite")
    parser.add_argument("preview_output", type=Path, help="final route preview PNG")
    parser.add_argument("animation_output", type=Path, help="packed animation data")
    return parser.parse_args()


def threshold(image: Image.Image) -> Image.Image:
    return image.convert("L").point(
        lambda value: 0 if value < THRESHOLD else 255
    )


def prepare_boot(source: Image.Image) -> Image.Image:
    binary = threshold(ImageOps.autocontrast(source.convert("L")))
    bounding_box = ImageOps.invert(binary).getbbox()
    if bounding_box is None:
        raise ValueError("boot source does not contain any black pixels")
    cropped = binary.crop(bounding_box)
    return threshold(
        ImageOps.fit(
            cropped,
            (SPRITE_WIDTH, SPRITE_HEIGHT),
            method=Image.Resampling.LANCZOS,
            centering=(0.5, 0.5),
        )
    )


def pack_1bpp(image: Image.Image) -> bytes:
    if image.width % 8 != 0:
        raise ValueError("packed image width must be divisible by eight")
    pixels = image.load()
    output = bytearray(image.width * image.height // 8)
    for y in range(image.height):
        for x in range(image.width):
            if pixels[x, y] >= 128:
                index = y * (image.width // 8) + x // 8
                output[index] |= 1 << (7 - (x & 7))
    return bytes(output)


def render_step(
    frame: Image.Image, boot: Image.Image, index: int
) -> tuple[Image.Image, tuple[int, int, int, int], bytes]:
    center_x, center_y = CENTERLINE[index]
    previous = CENTERLINE[max(0, index - 1)]
    following = CENTERLINE[min(len(CENTERLINE) - 1, index + 1)]
    direction_x = following[0] - previous[0]
    direction_y = following[1] - previous[1]
    direction_length = math.hypot(direction_x, direction_y)
    normal_x = -direction_y / direction_length
    normal_y = direction_x / direction_length
    side = 1 if index % 2 == 0 else -1
    center_x = round(center_x + side * OFFSETS[index] * normal_x)
    center_y = round(center_y + side * OFFSETS[index] * normal_y)

    sprite_height = HEIGHTS[index]
    sprite_width = max(8, round(sprite_height * boot.width / boot.height))
    sprite = ImageOps.fit(
        boot,
        (sprite_width, sprite_height),
        method=Image.Resampling.LANCZOS,
        centering=(0.5, 0.5),
    )
    if index % 2 == 0:
        sprite = ImageOps.mirror(sprite)
    angle = -math.degrees(math.atan2(direction_x, -direction_y))
    sprite = threshold(
        sprite.rotate(
            angle,
            resample=Image.Resampling.BICUBIC,
            expand=True,
            fillcolor=255,
        )
    )

    paste_x = center_x - sprite.width // 2
    paste_y = center_y - sprite.height // 2
    ink_box = ImageOps.invert(sprite).getbbox()
    if ink_box is None:
        raise ValueError(f"step {index + 1} has no black pixels")
    layer = Image.new("L", frame.size, 255)
    layer.paste(sprite, (paste_x, paste_y))
    frame = ImageChops.darker(frame, layer)

    x0 = max(0, (paste_x + ink_box[0] - 2) & ~7)
    x1 = min(WIDTH, (paste_x + ink_box[2] + 2 + 7) & ~7)
    y0 = max(0, paste_y + ink_box[1] - 2)
    y1 = min(HEIGHT, paste_y + ink_box[3] + 2)
    rect = (x0, y0, x1 - x0, y1 - y0)
    patch = pack_1bpp(frame.crop((x0, y0, x1, y1)))
    return frame, rect, patch


def main() -> None:
    args = parse_args()
    background = threshold(Image.open(args.background))
    if background.size != (WIDTH, HEIGHT):
        raise ValueError(f"background must be {WIDTH}x{HEIGHT}")
    boot = prepare_boot(Image.open(args.boot_source))

    frame = background.copy()
    records = []
    for index in range(len(CENTERLINE)):
        frame, rect, patch = render_step(frame, boot, index)
        x, y, width, height = rect
        expected_size = width * height // 8
        if len(patch) != expected_size:
            raise ValueError(f"step {index + 1} has invalid patch size")
        records.append((rect, (index + 1) & 1, patch))

    animation = bytearray(MAGIC)
    animation.extend(struct.pack("<HH", len(records), 0))
    for (x, y, width, height), foot, patch in records:
        animation.extend(
            struct.pack("<HHHHBBH", x, y, width, height, foot, 0, len(patch))
        )
        animation.extend(patch)

    for path in (args.boot_output, args.preview_output, args.animation_output):
        path.parent.mkdir(parents=True, exist_ok=True)
    boot.save(args.boot_output, optimize=True)
    frame.save(args.preview_output, optimize=True)
    args.animation_output.write_bytes(animation)
    print(
        f"wrote {len(records)} steps, {len(animation)} animation bytes, "
        f"max patch={max(len(record[2]) for record in records)} bytes"
    )


if __name__ == "__main__":
    main()
