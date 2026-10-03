#!/usr/bin/env python3
"""Turn the approved concept sheet into four monochrome preview GIFs."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageSequence


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "previews" / "apple-pixel-animation-concepts.png"
HAPPY_MAC_V2_SOURCE = ROOT / "previews" / "apple-pixel-happy-mac-v2-sheet.png"
HAPPY_MAC_REFERENCE = ROOT / "previews" / "apple-happy-mac-reference.png"
UPRIGHT_MAC_REFERENCE = ROOT / "previews" / "apple-macintosh-upright-reference.png"
OUT = ROOT / "previews"
CANVAS = (400, 300)


ROWS = {
    "apple-pixel-macintosh-boot.gif": {
        "boxes": [(35, 170, 195, 370), (205, 170, 365, 370), (375, 170, 535, 370),
                  (545, 170, 705, 370), (715, 170, 875, 370), (885, 160, 1080, 380)],
        "durations": [550, 450, 500, 650, 450, 900],
    },
    "apple-pixel-happy-mac.gif": {
        "boxes": [(35, 500, 195, 690), (205, 500, 365, 690), (375, 500, 535, 690),
                  (545, 500, 705, 690), (715, 500, 875, 690), (885, 500, 1050, 690)],
        "durations": [500, 280, 480, 480, 480, 800],
    },
    "apple-pixel-hello.gif": {
        "boxes": [(35, 850, 155, 1010), (185, 850, 325, 1010), (340, 850, 505, 1010),
                  (515, 850, 680, 1010), (685, 850, 860, 1010), (870, 840, 1080, 1020)],
        "durations": [330, 330, 330, 330, 420, 1000],
        "align": "left",
    },
    "apple-pixel-mac-wallpaper.gif": {
        "boxes": [(20, 1135, 190, 1375), (195, 1135, 370, 1375), (375, 1135, 545, 1375),
                  (550, 1135, 720, 1375), (725, 1135, 895, 1375), (900, 1135, 1075, 1375)],
        "durations": [420] * 6,
    },
}


def monochrome(image: Image.Image) -> Image.Image:
    return image.convert("L").point(lambda value: 0 if value < 150 else 255, "1")


def frame_from_crop(source: Image.Image, box: tuple[int, int, int, int], align: str) -> Image.Image:
    crop = monochrome(source.crop(box))
    inverted = crop.point(lambda value: 255 if value == 0 else 0, "1")
    content = inverted.getbbox()
    if content:
        crop = crop.crop(content)
    canvas = Image.new("1", CANVAS, 1)
    if align == "left":
        x = 58
    else:
        x = (CANVAS[0] - crop.width) // 2
    y = (CANVAS[1] - crop.height) // 2
    canvas.paste(crop, (x, y))
    return canvas.convert("P")


def main() -> None:
    source = Image.open(SOURCE)
    for filename, config in ROWS.items():
        align = config.get("align", "center")
        frames = [frame_from_crop(source, box, align) for box in config["boxes"]]
        output = OUT / filename
        frames[0].save(
            output,
            save_all=True,
            append_images=frames[1:],
            duration=config["durations"],
            loop=0,
            optimize=False,
            disposal=2,
        )
        print(output)

    # The refined Happy Mac sheet is transparent and contains six equal cells.
    # Composite each cell on white, crop to its visible Macintosh, and keep all
    # frames at a fixed e-paper-friendly size.
    refined = Image.open(HAPPY_MAC_V2_SOURCE).convert("RGBA")
    refined_frames: list[Image.Image] = []
    cell_width = refined.width / 6
    for index in range(6):
        left = round(index * cell_width)
        right = round((index + 1) * cell_width)
        rgba = refined.crop((left, 80, right, 700))
        white = Image.new("RGBA", rgba.size, "white")
        white.alpha_composite(rgba)
        mono = monochrome(white)
        inverted = mono.point(lambda value: 255 if value == 0 else 0, "1")
        content = inverted.getbbox()
        if content:
            mono = mono.crop(content)
        mono.thumbnail((225, 235), Image.Resampling.NEAREST)
        canvas = Image.new("1", CANVAS, 1)
        canvas.paste(mono, ((CANVAS[0] - mono.width) // 2, (CANVAS[1] - mono.height) // 2))
        refined_frames.append(canvas.convert("P"))
    refined_output = OUT / "apple-pixel-happy-mac-v2.gif"
    refined_frames[0].save(
        refined_output,
        save_all=True,
        append_images=refined_frames[1:],
        duration=[550, 450, 700, 300, 650, 900],
        loop=0,
        optimize=False,
        disposal=2,
    )
    print(refined_output)

    # V3 is derived directly from the user-provided Macintosh image.  The
    # yellow backdrop thresholds to white; all case and face pixels remain the
    # reference pixels.  Only the two eye rectangles change for blinking.
    reference = Image.open(HAPPY_MAC_REFERENCE).convert("L")
    reference = reference.point(lambda value: 0 if value < 100 else 255, "1")
    reference = reference.crop((30, 60, 312, 376))
    poses: list[tuple[Image.Image, int]] = []
    for index in range(6):
        pose = reference.copy()
        if index in (1, 4):
            draw = ImageDraw.Draw(pose)
            # Eye coordinates relative to the reference crop.  Do not alter
            # the central nose or smile.
            draw.rectangle((93, 70, 107, 95), fill=1)
            draw.rectangle((176, 70, 189, 95), fill=1)
            draw.rectangle((94, 83, 106, 87), fill=0)
            draw.rectangle((177, 83, 188, 87), fill=0)
        pose.thumbnail((210, 235), Image.Resampling.NEAREST)
        poses.append((pose, -2 if index == 5 else 0))
    v3_frames: list[Image.Image] = []
    for pose, y_offset in poses:
        canvas = Image.new("1", CANVAS, 1)
        x = (CANVAS[0] - pose.width) // 2
        y = (CANVAS[1] - pose.height) // 2 + y_offset
        canvas.paste(pose, (x, y))
        v3_frames.append(canvas.convert("P"))
    v3_output = OUT / "apple-pixel-happy-mac-v3.gif"
    v3_frames[0].save(
        v3_output,
        save_all=True,
        append_images=v3_frames[1:],
        duration=[650, 180, 850, 650, 180, 800],
        loop=0,
        optimize=False,
        disposal=2,
    )
    print(v3_output)

    # Keep the original boot sequence but replace the slanted concept-sheet
    # case with the user's clean front-facing Macintosh. The reference is
    # thresholded before nearest-neighbour scaling so every edge is a crisp
    # 1-bit pixel and the left wall remains vertical across every frame.
    original_boot = Image.open(OUT / "apple-pixel-macintosh-boot.gif")
    hybrid_frames = [frame.convert("1") for frame in ImageSequence.Iterator(original_boot)]
    upright = monochrome(Image.open(UPRIGHT_MAC_REFERENCE).crop((60, 60, 320, 390)))
    upright = upright.resize((180, 228), Image.Resampling.NEAREST)

    def place_mac(pose: Image.Image, y_offset: int = 0) -> Image.Image:
        frame = Image.new("1", CANVAS, 1)
        frame.paste(pose, ((CANVAS[0] - pose.width) // 2,
                           (CANVAS[1] - pose.height) // 2 + y_offset))
        # The screenshot has one-pixel bumps on the outer left casing. Replace
        # that narrow edge only, keeping the supplied face and CRT untouched.
        edge = ImageDraw.Draw(frame)
        edge.rectangle((109, 45 + y_offset, 121, 235 + y_offset), fill=1)
        edge.rectangle((114, 45 + y_offset, 120, 235 + y_offset), fill=0)
        return frame

    hybrid_frames[3] = place_mac(upright)
    hybrid_frames[4] = place_mac(upright, -1)
    hybrid_frames[5] = place_mac(upright, 1)
    hybrid_frames = [frame.convert("P") for frame in hybrid_frames]
    hybrid_output = OUT / "apple-pixel-macintosh-boot-v2.gif"
    hybrid_frames[0].save(
        hybrid_output,
        save_all=True,
        append_images=hybrid_frames[1:],
        duration=[550, 450, 500, 650, 450, 900],
        loop=0,
        optimize=False,
        disposal=2,
    )
    print(hybrid_output)

    # Matching blink loop: same first-version case and approved centered face.
    normal = place_mac(upright)
    blink_pose = upright.copy()
    blink_draw = ImageDraw.Draw(blink_pose)
    # Eye coordinates are mapped from the supplied upright reference crop.
    for x in (60, 115):
        blink_draw.rectangle((x - 2, 69, x + 8, 91), fill=1)
        blink_draw.rectangle((x, 81, x + 6, 83), fill=0)
    blink = place_mac(blink_pose)
    raised = place_mac(upright, -1)
    raised_blink = place_mac(blink_pose, -1)
    blink_frames = [normal, blink, normal, raised, raised_blink, normal]
    blink_frames = [frame.convert("P") for frame in blink_frames]
    blink_output = OUT / "apple-pixel-macintosh-blink-v2.gif"
    blink_frames[0].save(
        blink_output,
        save_all=True,
        append_images=blink_frames[1:],
        duration=[700, 180, 900, 700, 180, 900],
        loop=0,
        optimize=False,
        disposal=2,
    )
    print(blink_output)


if __name__ == "__main__":
    main()
