#!/usr/bin/env python3
"""Draw a truthful 400×300, 1-bit NOTE4 month-view feasibility preview."""

from datetime import date, timedelta
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "previews" / "note4-calendar-month-400x300.png"
FONT = ROOT / "macos" / "AppBundle" / "SourceHanSansSC-Regular.otf"
FONT_BOLD = ROOT / "macos" / "AppBundle" / "SourceHanSansSC-Bold.otf"
WIDTH, HEIGHT = 400, 300
GRID_TOP = 52
ROW_HEIGHT = 41
COLUMN_EDGES = [round(i * WIDTH / 7) for i in range(8)]
FIRST_DAY = date(2026, 8, 30)
TODAY = date(2026, 9, 23)
WEEKDAYS = ("周日", "周一", "周二", "周三", "周四", "周五", "周六")
LUNAR = {
    1: "二十", 7: "廿六", 10: "廿九", 11: "八月", 12: "初二",
    13: "初三", 14: "初四", 15: "初五", 16: "初六", 17: "初七",
    18: "初八", 20: "初十", 21: "十一", 22: "十二", 23: "十三",
    24: "十四", 25: "十五", 26: "十六", 27: "十七", 28: "十八",
    29: "十九", 30: "二十",
}
EVENTS = {
    1: ("客户会", 1), 7: ("白露", 1), 10: ("写报告", 18),
    11: ("看书", 23), 12: ("吃饭", 12), 13: ("外拍", 7),
    14: ("VR脚本", 5), 15: ("新事项", 10), 16: ("吃面条", 12),
    17: ("发布视频", 2), 18: ("带证件", 1), 20: ("国庆节", 3),
    21: ("出门", 2), 22: ("换牌申请", 4), 23: ("秋分", 1),
    25: ("中秋节", 2),
}


def main() -> None:
    image = Image.new("1", (WIDTH, HEIGHT), 1)
    draw = ImageDraw.Draw(image)
    heading = ImageFont.truetype(str(FONT_BOLD), 20)
    weekday_font = ImageFont.truetype(str(FONT), 10)
    date_font = ImageFont.truetype(str(FONT_BOLD), 12)
    lunar_font = ImageFont.truetype(str(FONT), 8)
    event_font = ImageFont.truetype(str(FONT), 8)
    count_font = ImageFont.truetype(str(FONT), 7)

    draw.text((8, 5), "2026年9月", font=heading, fill=0)
    draw.rounded_rectangle((309, 8, 350, 29), radius=10, outline=0)
    draw.text((315, 11), "今天", font=weekday_font, fill=0)
    draw.line(((365, 13), (359, 19), (365, 25)), fill=0, width=2)
    draw.line(((381, 13), (387, 19), (381, 25)), fill=0, width=2)
    for col, weekday in enumerate(WEEKDAYS):
        draw.text((COLUMN_EDGES[col] + 15, 35), weekday,
                  font=weekday_font, fill=0)
    draw.line(((0, GRID_TOP - 1), (WIDTH - 1, GRID_TOP - 1)), fill=0)

    for row in range(6):
        y = GRID_TOP + row * ROW_HEIGHT
        if row:
            draw.line(((0, y), (WIDTH - 1, y)), fill=0)
        for col in range(7):
            x = COLUMN_EDGES[col]
            right = COLUMN_EDGES[col + 1]
            if col:
                draw.line(((x, GRID_TOP), (x, HEIGHT - 1)), fill=0)
            day = FIRST_DAY + timedelta(days=row * 7 + col)
            in_month = day.month == 9
            lunar = LUNAR.get(day.day, "") if in_month else ""
            draw.text((x + 3, y + 3), lunar, font=lunar_font, fill=0)
            day_text = str(day.day)
            width = draw.textlength(day_text, font=date_font)
            text_x = right - width - 5
            if day == TODAY:
                draw.ellipse((right - 22, y + 2, right - 3, y + 21), fill=0)
                draw.text((text_x, y + 2), day_text, font=date_font, fill=1)
            else:
                draw.text((text_x, y + 2), day_text, font=date_font, fill=0)
            if in_month and day.day in EVENTS:
                title, count = EVENTS[day.day]
                draw.ellipse((x + 3, y + 24, x + 8, y + 29), outline=0)
                draw.text((x + 11, y + 21), title[:4], font=event_font, fill=0)
                if count > 1:
                    draw.text((x + 11, y + 31), f"+{count - 1}项",
                              font=count_font, fill=0)

    OUTPUT.parent.mkdir(exist_ok=True)
    image.save(OUTPUT)
    print(OUTPUT)


if __name__ == "__main__":
    main()
