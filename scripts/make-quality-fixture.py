#!/usr/bin/env python3
"""Create an original, local screen-content test clip; no screen capture or user files."""
import argparse
import json
import math
from pathlib import Path
import subprocess
from PIL import Image, ImageDraw, ImageFont

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--output', type=Path, required=True, help='New directory')
p.add_argument('--ffmpeg', type=Path, default=Path('/Applications/NotchCompressor.app/Contents/MacOS/ffmpeg'))
a = p.parse_args()
a.output.mkdir(parents=True, exist_ok=False)
w, h, fps, seconds = 1920, 1080, 60, 12
font_path = '/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc'
mono_path = '/System/Library/Fonts/Menlo.ttc'
font = lambda size: ImageFont.truetype(font_path, size)
mono = lambda size: ImageFont.truetype(mono_path, size)
base = Image.new('RGB', (w, h), '#f5f6f8')
d = ImageDraw.Draw(base)
d.rectangle((0, 0, w, 62), fill='#202734')
d.text((32, 16), 'NotchCompressor · Original quality test fixture', font=font(25), fill='white')
d.text((40, 90), '文字の読みやすさ / Text, motion and fine detail', font=font(34), fill='#152033')
for i, size in enumerate([10, 12, 14, 18, 24, 32]):
    y = 160 + i * 62
    d.text((40, y), f'{size}px  圧縮後も文字と数字を確認  0123456789  Il1 O0', font=font(size), fill='#172334')
    d.text((950, y), f'let value = items.filter {{ $0 > 0 }} // {size}px', font=mono(size), fill='#a12b55')
for i, color in enumerate(['#1e64ae', '#bd3b32', '#1b7a46', '#7b39a2']):
    d.text((40 + 460 * i, 560), '小さい色文字: abc 123 日本語', font=font(18), fill=color)
for x in range(40, 900, 4):
    d.line((x, 650, x, 760), fill='#242c38', width=1)
for x in range(950, 1850, 8):
    d.line((x, 650, x, 760), fill='#2774b6', width=2)
d.text((40, 795), 'Thin lines · 1 px / 2 px · inspect at 100% scale', font=font(20), fill='#172334')
page = Image.new('RGB', (1740, 2400), 'white')
pd = ImageDraw.Draw(page)
for i in range(65):
    pd.text((25, 10 + i * 36), f'{i+1:02d}  func compressVideo() {{ return validatedOutput }}  // スクロール時の文字と輪郭', font=font(19), fill=['#172334','#2459a1','#a12b55'][i % 3])
source = a.output / 'screen-content.mov'
command = [str(a.ffmpeg), '-nostdin', '-hide_banner', '-loglevel', 'error', '-n',
    '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-s', f'{w}x{h}', '-r', str(fps), '-i', 'pipe:0',
    '-f', 'lavfi', '-i', "aevalsrc=if(lt(mod(t\\,1)\\,0.1)\\,0.2*sin(2*PI*880*t)\\,0):s=48000",
    '-t', str(seconds), '-c:v', 'h264_videotoolbox', '-allow_sw', '0', '-b:v', '40000000',
    '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '192000', '-movflags', '+faststart', str(source)]
with (a.output / 'generation.log').open('wb') as log:
    proc = subprocess.Popen(command, stdin=subprocess.PIPE, stderr=log)
    try:
        for n in range(fps * seconds):
            t = n / fps
            frame = base.copy()
            fd = ImageDraw.Draw(frame)
            if 3 <= t < 6:
                offset = int((t - 3) * 350)
                frame.paste(page.crop((0, offset, 1740, offset + 760)), (90, 145))
            elif 6 <= t < 9:
                fd.rectangle((40, 145, 1880, 900), fill='#162238')
                for k in range(12):
                    x = 100 + ((t - 6) * (180 + k * 25) + k * 130) % 1700
                    y = 210 + k * 54
                    fd.rounded_rectangle((x, y, x + 80, y + 35), radius=12, fill=(40+k*15,160,220-k*9))
                fd.text((80, 840), '60 fps motion / 滑らかさと残像を比較', font=font(26), fill='white')
            elif t >= 9:
                offset = int((t - 9) * 450)
                frame.paste(page.crop((0, offset, 860, offset + 650)), (50, 210))
                for k in range(35):
                    x = 970 + k * 25
                    y = 540 + 230 * math.sin(t * 3 + k / 5)
                    fd.ellipse((x, y, x + 18, y + 18), fill='#246cc1')
            fd.rectangle((0, 940, w, h), fill='#e4e9ef')
            fd.text((40, 965), f'{t:05.2f}s · scene {n // (fps * 3) + 1}/4 · 1920×1080 / 60 fps', font=mono(24), fill='#152033')
            flash = t % 1 < 0.1
            fd.rectangle((1650, 960, 1860, 1040), fill='#ffffff' if flash else '#152033')
            if n in [60, 270, 450, 630]:
                frame.save(a.output / f'reference-{n}.png')
            proc.stdin.write(frame.tobytes())
    finally:
        proc.stdin.close()
    if proc.wait() != 0:
        raise SystemExit('Fixture encoding failed; see generation.log')
(a.output / 'manifest.json').write_text(json.dumps(dict(width=w, height=h, fps=fps, seconds=seconds,
    scenes=['static Japanese/English text and thin lines', 'scrolling code', 'moving shapes', 'scrolling and animation'],
    audio='880 Hz beep and white flash for first 100 ms of each second',
    source_encoding='H.264 VideoToolbox 40 Mbps target, AAC 192 kbps; source is not lossless',
    scope='Original synthetic screen-content fixture, not an actual user recording. Does not prove universal defaults.'), indent=2))
print(source)
