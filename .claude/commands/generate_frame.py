#!/usr/bin/env python3
"""
Generate iPhone device frame template PNG.
Output: assets/device_frame.png — standalone device image (not positioned on canvas).
compose.py positions this dynamically based on text height.
"""

from PIL import Image, ImageDraw, ImageChops

# ── Device dimensions ───────────────────────────────────────────────
# Width is ~80% of 1290 canvas, matching reference screenshots
DEVICE_W = 1030
DEVICE_H = 2800           # tall enough to bleed off any canvas
DEVICE_CORNER_R = 77
BEZEL = 15
SCREEN_CORNER_R = 62
DI_W = 130               # Dynamic Island width
DI_H = 38                # Dynamic Island height
DI_TOP = 14              # offset from top of screen

SCREEN_W = DEVICE_W - 2 * BEZEL
SCREEN_H = DEVICE_H - 2 * BEZEL


def generate():
    frame = Image.new("RGBA", (DEVICE_W, DEVICE_H), (0, 0, 0, 0))
    fd = ImageDraw.Draw(frame)

    # ── Device body (dark grey outer, darker inner) ─────────────────
    fd.rounded_rectangle(
        [0, 0, DEVICE_W - 1, DEVICE_H - 1],
        radius=DEVICE_CORNER_R,
        fill=(30, 30, 30, 255),
    )
    fd.rounded_rectangle(
        [1, 1, DEVICE_W - 2, DEVICE_H - 2],
        radius=DEVICE_CORNER_R - 1,
        fill=(20, 20, 20, 255),
    )

    # ── Screen cutout (transparent) ─────────────────────────────────
    screen_x = BEZEL
    screen_y = BEZEL

    cutout = Image.new("L", (DEVICE_W, DEVICE_H), 255)
    ImageDraw.Draw(cutout).rounded_rectangle(
        [screen_x, screen_y, screen_x + SCREEN_W, screen_y + SCREEN_H],
        radius=SCREEN_CORNER_R,
        fill=0,
    )
    frame.putalpha(ImageChops.multiply(frame.getchannel("A"), cutout))

    # ── Dynamic Island ──────────────────────────────────────────────
    di_x = (DEVICE_W - DI_W) // 2
    di_y = screen_y + DI_TOP
    ImageDraw.Draw(frame).rounded_rectangle(
        [di_x, di_y, di_x + DI_W, di_y + DI_H],
        radius=DI_H // 2,
        fill=(0, 0, 0, 255),
    )

    # ── Side buttons ────────────────────────────────────────────────
    btn_color = (25, 25, 25, 255)
    fd2 = ImageDraw.Draw(frame)

    # Power button (right side)
    fd2.rounded_rectangle(
        [DEVICE_W, 340, DEVICE_W + 4, 460],
        radius=2, fill=btn_color,
    )
    # Volume up (left side)
    fd2.rounded_rectangle(
        [-4, 280, 0, 360],
        radius=2, fill=btn_color,
    )
    # Volume down (left side)
    fd2.rounded_rectangle(
        [-4, 380, 0, 460],
        radius=2, fill=btn_color,
    )
    # Silent switch (left side)
    fd2.rounded_rectangle(
        [-4, 180, 0, 220],
        radius=2, fill=btn_color,
    )

    out = "assets/device_frame.png"
    frame.save(out, "PNG")
    print(f"✓ {out} ({DEVICE_W}×{DEVICE_H})")
    print(f"  BEZEL={BEZEL}, SCREEN_W={SCREEN_W}, SCREEN_H={SCREEN_H}")
    print(f"  SCREEN_CORNER_R={SCREEN_CORNER_R}")


if __name__ == "__main__":
    generate()
