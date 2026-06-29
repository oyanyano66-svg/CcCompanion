#!/usr/bin/env python3
"""Generate CcCompanion app icon — clean Mediterranean design."""
from PIL import Image, ImageDraw, ImageFont
import math

SIZE = 1024

# Mediterranean palette
CHALK      = (227, 214, 191)      # #E3D6BF
AMARANTH   = (147, 59, 91)        # #933B5B
THULIAN    = (181, 114, 138)      # #B5728A
BROOK      = (170, 186, 174)      # #AABAAE
POMELO     = (159, 150, 121)      # #9F9679

img = Image.new("RGBA", (SIZE, SIZE), CHALK)
draw = ImageDraw.Draw(img)

cx, cy = SIZE // 2, SIZE // 2

# Background: soft diagonal split — chalk top-left to slightly warmer bottom-right
for y in range(SIZE):
    for x in range(SIZE):
        frac = (x + y) / (2 * SIZE)
        r = int(CHALK[0] * (1 - 0.06 * frac))
        g = int(CHALK[1] * (1 - 0.06 * frac))
        b = int(CHALK[2] * (1 - 0.04 * frac))
        img.putpixel((x, y), (r, g, b, 255))

# Draw a heart shape — Amaranth
def heart_polygon(cx, cy, scale, n=200):
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        x = 16 * math.sin(t) ** 3
        y = -(13 * math.cos(t) - 5 * math.cos(2*t) - 2 * math.cos(3*t) - math.cos(4*t))
        pts.append((cx + x * scale, cy + y * scale))
    return pts

# Large heart — Amaranth
heart_lg = heart_polygon(cx, cy - 40, 17)
draw.polygon(heart_lg, fill=AMARANTH)

# Small flame/spark above heart — Thulian Pink
# Three small circles ascending like embers rising
for i, (dx, dy, r) in enumerate([
    (0, -330, 16),
    (-20, -365, 10),
    (15, -395, 7),
]):
    alpha = 255 - i * 50
    draw.ellipse(
        [cx + dx - r, cy + dy - r, cx + dx + r, cy + dy + r],
        fill=THULIAN,
    )

# Accent arc under heart — Brook Green
arc_y = cy + 240
draw.arc(
    [cx - 140, arc_y - 20, cx + 140, arc_y + 20],
    start=0, end=180,
    fill=BROOK, width=4,
)

# "Cc" monogram below — Pomelo Olive
try:
    font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf", 100)
except OSError:
    font = ImageFont.load_default()

text = "Cc"
bbox = draw.textbbox((0, 0), text, font=font)
tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
draw.text(
    (cx - tw // 2, cy + 260),
    text,
    fill=POMELO,
    font=font,
)

out = "/root/CcCompanion/AppIcon.png"
img.save(out, "PNG")
print(f"Saved {out}")
