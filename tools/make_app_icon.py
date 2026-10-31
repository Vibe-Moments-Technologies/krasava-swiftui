#!/usr/bin/env python3
"""
tools/make_app_icon.py — рисует иконку приложения.

Почему кодом, а не картинкой из редактора: иконка должна быть
воспроизводимой. Поменяли акцентный цвет в Assets — перегенерировали
иконку той же командой, и она снова совпадает с интерфейсом.

Что рисуется: скруглённый календарь на градиенте акцентного цвета.
Система сама обрежет квадрат по своей маске, поэтому фон заливается
на всю площадь.

Использование:
    python3 tools/make_app_icon.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

# Работаем в увеличенном масштабе и уменьшаем в конце: у Pillow нет
# сглаживания для фигур, и без этого края были бы ступенчатыми.
SIZE = 1024
SS = 2
CANVAS = SIZE * SS

BACKGROUND_TOP = (58, 126, 140)
BACKGROUND_BOTTOM = (27, 71, 82)
SHEET = (255, 255, 255)
BAND = (21, 47, 55)
DOT = (198, 214, 218)
DOT_ACTIVE = (46, 108, 120)

APP_ICON = Path(
    "KrasavaSwiftUI/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
)
BRAND_ICON = Path(
    "KrasavaSwiftUI/Resources/Assets.xcassets/BrandIcon.imageset/BrandIcon-1024.png"
)


def vertical_gradient(size: int, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    image = Image.new("RGB", (1, size))
    pixels = image.load()
    for y in range(size):
        ratio = y / max(size - 1, 1)
        pixels[0, y] = tuple(
            round(top[channel] + (bottom[channel] - top[channel]) * ratio)
            for channel in range(3)
        )
    return image.resize((size, size))


def draw_icon() -> Image.Image:
    canvas = Image.new("RGB", (CANVAS, CANVAS))
    canvas.paste(vertical_gradient(CANVAS, BACKGROUND_TOP, BACKGROUND_BOTTOM), (0, 0))

    draw = ImageDraw.Draw(canvas)

    # Лист календаря: чуть выше центра, чтобы снизу осталось «воздуха».
    sheet_width = round(CANVAS * 0.60)
    sheet_height = round(CANVAS * 0.56)
    left = (CANVAS - sheet_width) // 2
    top = round(CANVAS * 0.24)
    radius = round(CANVAS * 0.075)

    # Тень под листом — без неё белый прямоугольник выглядит наклеенным.
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [left, top + round(CANVAS * 0.012), left + sheet_width, top + sheet_height + round(CANVAS * 0.012)],
        radius=radius,
        fill=(0, 0, 0, 70),
    )
    from PIL import ImageFilter

    shadow = shadow.filter(ImageFilter.GaussianBlur(radius / 2))
    canvas.paste(Image.alpha_composite(canvas.convert("RGBA"), shadow).convert("RGB"), (0, 0))

    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle(
        [left, top, left + sheet_width, top + sheet_height],
        radius=radius,
        fill=SHEET,
    )

    # Шапка календаря.
    band_height = round(sheet_height * 0.26)
    draw.rounded_rectangle(
        [left, top, left + sheet_width, top + band_height],
        radius=radius,
        fill=BAND,
    )
    # Нижние углы шапки должны быть прямыми — перекрываем их листом.
    draw.rectangle(
        [left, top + band_height - radius, left + sheet_width, top + band_height],
        fill=BAND,
    )

    # Кольца-пружины над шапкой.
    ring_radius = round(CANVAS * 0.022)
    ring_y = top - round(CANVAS * 0.005)
    for offset in (0.28, 0.72):
        ring_x = left + sheet_width * offset
        draw.rounded_rectangle(
            [ring_x - ring_radius, ring_y - ring_radius * 2,
             ring_x + ring_radius, ring_y + ring_radius * 2],
            radius=ring_radius,
            fill=BAND,
        )

    # Сетка дней: 4 колонки, 3 строки. Один день выделен акцентом —
    # 「сегодня」 в иконке читается как расписание, а не как пустой календарь.
    columns, rows = 4, 3
    grid_left = left + round(sheet_width * 0.13)
    grid_right = left + sheet_width - round(sheet_width * 0.13)
    grid_top = top + band_height + round(sheet_height * 0.14)
    grid_bottom = top + sheet_height - round(sheet_height * 0.12)

    cell_w = (grid_right - grid_left) / (columns - 1)
    cell_h = (grid_bottom - grid_top) / (rows - 1)
    dot_radius = round(CANVAS * 0.026)

    for row in range(rows):
        for column in range(columns):
            cx = grid_left + cell_w * column
            cy = grid_top + cell_h * row
            active = (row, column) == (0, 1)
            draw.ellipse(
                [cx - dot_radius, cy - dot_radius, cx + dot_radius, cy + dot_radius],
                fill=DOT_ACTIVE if active else DOT,
            )

    return canvas.resize((SIZE, SIZE), Image.LANCZOS)


def main() -> int:
    icon = draw_icon()

    for target in (APP_ICON, BRAND_ICON):
        target.parent.mkdir(parents=True, exist_ok=True)
        icon.save(target, format="PNG", optimize=True)
        print(f"записано: {target}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())