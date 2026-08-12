"""生成 108拜 应用图标（self_improvement Material Icon）"""
import os
from PIL import Image, ImageDraw, ImageFont

FONT_PATH = r"D:\flutter_sdk\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf"
RES_DIR = r"d:\workspace\ShiXingXia\android\app\src\main\res"

BG_COLOR = (124, 77, 255, 255)      # deepPurpleAccent #7C4DFF
ICON_COLOR = (255, 255, 255, 255)    # white
SRC_SIZE = 512

# 渲染源图
img = Image.new('RGBA', (SRC_SIZE, SRC_SIZE), BG_COLOR)
draw = ImageDraw.Draw(img)

font = ImageFont.truetype(FONT_PATH, size=380)
text = '\ue56f'  # self_improvement

# 居中
bbox = draw.textbbox((0, 0), text, font=font)
x = (SRC_SIZE - (bbox[2] - bbox[0])) / 2 - bbox[0]
y = (SRC_SIZE - (bbox[3] - bbox[1])) / 2 - bbox[1]
draw.text((x, y), text, font=font, fill=ICON_COLOR)

# 各密度尺寸
sizes = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
}

for folder, sz in sizes.items():
    resized = img.resize((sz, sz), Image.LANCZOS)
    path = os.path.join(RES_DIR, folder, 'ic_launcher.png')
    resized.save(path, 'PNG')
    print(f"Saved {path} ({sz}x{sz})")

print("Done!")
