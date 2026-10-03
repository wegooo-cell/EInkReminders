#!/usr/bin/env python3
"""Build NOTE4 dog-cow frames from the single approved reference image.

The head, ears, muzzle, back patch, torso and tail are copied directly from
the supplied reference. Walking poses are made by shearing only the two
lower-leg regions; no alternate dog drawing or generated pose is used.
"""

from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "previews" / "moof-dog-reference.png"
OUTPUT = ROOT / "firmware-note4" / "main" / "moof_dog_frames.bin"
PREVIEW = ROOT / "previews" / "moof-dog-reference-animation.gif"
SHEET = ROOT / "previews" / "moof-dog-reference-poses.png"

SPRITE_WIDTH = 104
SPRITE_HEIGHT = 83
FRAME_DELTAS = ((0, 0), (3, -3), (5, -5), (0, 0), (-3, 3), (-5, 5))


def threshold(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    white = Image.new("RGBA", rgba.size, "white")
    white.alpha_composite(rgba)
    return white.convert("L").point(lambda value: 0 if value < 128 else 255, "1")


def approved_sprite() -> Image.Image:
    source = threshold(Image.open(SOURCE))
    black = source.point(lambda value: 255 if value == 0 else 0, "1")
    bounds = black.getbbox()
    if bounds is None:
        raise RuntimeError("approved dog reference contains no black pixels")
    left, top, right, bottom = bounds
    crop = source.crop((left - 1, top - 1, right + 1, bottom + 1))
    crop.thumbnail((SPRITE_WIDTH, SPRITE_HEIGHT), Image.Resampling.NEAREST)
    sprite = Image.new("1", (SPRITE_WIDTH, SPRITE_HEIGHT), 1)
    sprite.paste(crop, ((SPRITE_WIDTH - crop.width) // 2, SPRITE_HEIGHT - crop.height))
    return sprite


def shear_lower_leg(frame: Image.Image, x0: int, x1: int, delta: int) -> None:
    """Move a lower leg while leaving its hip and the whole body untouched."""
    if delta == 0:
        return
    joint_y = 57
    bottom_y = SPRITE_HEIGHT - 1
    pixels = frame.load()
    points: list[tuple[int, int]] = []
    for y in range(joint_y, SPRITE_HEIGHT):
        for x in range(x0, x1):
            if pixels[x, y] == 0:
                points.append((x, y))
                pixels[x, y] = 1
    for x, y in points:
        amount = round(delta * (y - joint_y) / max(1, bottom_y - joint_y))
        moved_x = max(0, min(SPRITE_WIDTH - 1, x + amount))
        pixels[moved_x, y] = 0


def poses() -> list[Image.Image]:
    base = approved_sprite()
    result: list[Image.Image] = []
    for front_delta, rear_delta in FRAME_DELTAS:
        frame = base.copy()
        # Only these two rectangles may change; the approved head, back patch,
        # torso and tail remain bit-identical in every pose.
        shear_lower_leg(frame, 18, 44, front_delta)
        shear_lower_leg(frame, 72, 103, rear_delta)
        result.append(frame)
    return result


def pack_frame(image: Image.Image) -> bytes:
    packed = bytearray([0xFF] * (SPRITE_WIDTH // 8 * SPRITE_HEIGHT))
    pixels = image.load()
    for y in range(SPRITE_HEIGHT):
        for x in range(SPRITE_WIDTH):
            if pixels[x, y] == 0:
                offset = y * (SPRITE_WIDTH // 8) + x // 8
                packed[offset] &= ~(0x80 >> (x & 7))
    return bytes(packed)


def write_previews(frames: list[Image.Image]) -> None:
    sheet = Image.new("1", (SPRITE_WIDTH * len(frames), SPRITE_HEIGHT), 1)
    for index, frame in enumerate(frames):
        sheet.paste(frame, (index * SPRITE_WIDTH, 0))
    sheet.resize((sheet.width * 3, sheet.height * 3), Image.Resampling.NEAREST).save(SHEET)

    animation: list[Image.Image] = []
    for step in range(48):
        canvas = Image.new("1", (400, 300), 1)
        pose = frames[step % len(frames)]
        # The approved dog faces left, so it must travel from right to left.
        x = 400 - round(step * (400 + SPRITE_WIDTH) / 47)
        y = 118 + (1 if step % 6 in (1, 4) else 0)
        canvas.paste(pose, (x, y))
        if step in (31, 32, 33):
            draw = ImageDraw.Draw(canvas)
            bx, by = min(325, x + 66), max(20, y - 28)
            draw.rectangle((bx, by, bx + 55, by + 23), fill=1, outline=0, width=1)
            draw.polygon(((bx + 12, by + 23), (bx + 18, by + 23), (bx + 15, by + 28)), fill=0)
            draw.text((bx + 7, by + 5), "Moof!", fill=0)
        animation.append(canvas.convert("P"))
    animation[0].save(
        PREVIEW,
        save_all=True,
        append_images=animation[1:],
        duration=110,
        loop=0,
        optimize=False,
        disposal=2,
    )


def main() -> None:
    frames = poses()
    packed = b"".join(pack_frame(frame) for frame in frames)
    expected = len(frames) * (SPRITE_WIDTH // 8) * SPRITE_HEIGHT
    if len(packed) != expected:
        raise RuntimeError(f"unexpected sprite size: {len(packed)} != {expected}")
    OUTPUT.write_bytes(packed)
    write_previews(frames)
    print(f"wrote {OUTPUT} ({len(packed)} bytes)")
    print(f"wrote {PREVIEW}")
    print(f"wrote {SHEET}")


if __name__ == "__main__":
    main()
