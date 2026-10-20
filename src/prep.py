"""Upscale the source photo 2x (Lanczos + gentle unsharp) for the macro shots."""
import os
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
im = Image.open(os.path.join(ROOT, "src", "car.jpg")).convert("RGB")
up = im.resize((im.width * 2, im.height * 2), Image.LANCZOS)
up = up.filter(ImageFilter.UnsharpMask(radius=2.2, percent=60, threshold=2))
up.save(os.path.join(ROOT, "src", "car_2x.jpg"), quality=97)
print(up.size)
