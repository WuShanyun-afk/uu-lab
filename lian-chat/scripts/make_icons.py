# -*- coding: utf-8 -*-
"""Generate Lian app icons from one deterministic source design."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
ICONS = ROOT / "assets" / "icons"
ICONS.mkdir(parents=True, exist_ok=True)


def make_icon(size: int) -> Image.Image:
    scale = 4
    s = size * scale
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    radius = int(s * 0.235)
    d.rounded_rectangle((0, 0, s - 1, s - 1), radius=radius, fill=(17, 17, 17, 255))
    # A quiet inner hairline keeps the mark crisp at small sizes.
    inset = int(s * 0.045)
    d.rounded_rectangle(
        (inset, inset, s - inset - 1, s - inset - 1),
        radius=max(1, radius - inset),
        outline=(255, 255, 255, 24),
        width=max(1, int(s * 0.008)),
    )
    font = ImageFont.truetype(r"C:\Windows\Fonts\georgia.ttf", int(s * 0.60))
    box = d.textbbox((0, 0), "L", font=font)
    tw, th = box[2] - box[0], box[3] - box[1]
    tx = (s - tw) / 2 - box[0]
    ty = (s - th) / 2 - box[1] - int(s * 0.015)
    d.text((tx, ty), "L", font=font, fill=(250, 250, 248, 255))
    # Status dot: green only as a tiny accent, not a cartoon element.
    r = int(s * 0.065)
    cx, cy = int(s * 0.755), int(s * 0.755)
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(6, 199, 85, 255))
    d.ellipse(
        (cx - r, cy - r, cx + r, cy + r),
        outline=(17, 17, 17, 255),
        width=max(1, int(s * 0.012)),
    )
    return img.resize((size, size), Image.Resampling.LANCZOS).convert("RGB")


def main():
    for size in (180, 192, 512):
        make_icon(size).save(ICONS / f"icon-{size}.png", optimize=True)
    make_icon(64).save(ICONS / "favicon.png", optimize=True)
    svg = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
  <rect width="512" height="512" rx="120" fill="#111111"/>
  <rect x="23" y="23" width="466" height="466" rx="100" fill="none" stroke="#ffffff" stroke-opacity=".08" stroke-width="4"/>
  <text x="256" y="365" text-anchor="middle" font-family="Georgia, serif" font-size="310" fill="#FAFAF8">L</text>
  <circle cx="387" cy="387" r="33" fill="#06C755" stroke="#111111" stroke-width="7"/>
</svg>"""
    (ICONS / "icon.svg").write_text(svg, encoding="utf-8")
    print("icons written")


if __name__ == "__main__":
    main()
