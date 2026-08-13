from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT / "Resources" / "DICTATOR-1024.png"
ICONSET = ROOT / "Resources" / "DICTATOR.iconset"

size = 1024
im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
d = ImageDraw.Draw(im)

# Warm red command-card background.
d.rounded_rectangle((42, 42, 982, 982), radius=220, fill="#D64A3A")
d.rounded_rectangle((78, 78, 946, 946), radius=190, fill="#F4D9B7")

ink = "#201A19"
red = "#D64A3A"
cream = "#F4D9B7"

# Peaked cap and red band.
d.polygon([(270, 295), (340, 155), (684, 155), (754, 295)], fill=ink)
d.rounded_rectangle((218, 275, 806, 360), radius=40, fill=ink)
d.rounded_rectangle((322, 228, 702, 285), radius=24, fill=red)
d.ellipse((476, 230, 548, 302), fill=cream)
d.ellipse((496, 250, 528, 282), fill=red)

# Microphone head.
d.rounded_rectangle((342, 318, 682, 705), radius=164, fill=ink)
for y in (405, 490, 575):
    d.rounded_rectangle((402, y, 622, y + 28), radius=14, fill=cream)

# Comically severe moustache.
d.polygon([(512, 508), (455, 472), (340, 488), (255, 432), (287, 538), (410, 582), (512, 525)], fill=red)
d.polygon([(512, 508), (569, 472), (684, 488), (769, 432), (737, 538), (614, 582), (512, 525)], fill=red)

# Mic cradle + stand.
d.arc((250, 420, 774, 836), start=0, end=180, fill=ink, width=44)
d.rounded_rectangle((490, 702, 534, 850), radius=22, fill=ink)
d.rounded_rectangle((356, 824, 668, 878), radius=27, fill=ink)

# Tiny sound marks: dictating, not saluting.
for x, side in ((186, -1), (838, 1)):
    d.arc((x - 90 if side < 0 else x, 430, x if side < 0 else x + 90, 610),
          start=270 if side < 0 else 90, end=90 if side < 0 else 270, fill=ink, width=24)

im.save(MASTER)
ICONSET.mkdir(exist_ok=True)
for points, scale, name in [
    (16,1,"icon_16x16.png"),(16,2,"icon_16x16@2x.png"),
    (32,1,"icon_32x32.png"),(32,2,"icon_32x32@2x.png"),
    (128,1,"icon_128x128.png"),(128,2,"icon_128x128@2x.png"),
    (256,1,"icon_256x256.png"),(256,2,"icon_256x256@2x.png"),
    (512,1,"icon_512x512.png"),(512,2,"icon_512x512@2x.png")]:
    px = points * scale
    im.resize((px, px), Image.Resampling.LANCZOS).save(ICONSET / name)
print(MASTER)
