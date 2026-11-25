#!/usr/bin/env python3
"""Create local synthetic Japanese speech over an existing generated test video.

Requires the installed macOS Eddy Japanese voice and development FFmpeg.
Generated speech/media is for local evaluation, not a public redistribution asset.
"""
import argparse
from array import array
import json
import math
from pathlib import Path
import subprocess
import wave

TEXT = ('これは、動画を圧縮した後の音声を確認するための文章です。'
        '小さな声や、さしすせそ、ぱぴぷぺぽの聞こえ方を比べます。'
        '画面の文字を読みながら、最初から最後まで音が途切れないか確認してください。')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--video', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--ffmpeg', default='/Applications/NotchCompressor.app/Contents/MacOS/ffmpeg')
    p.add_argument('--decoder', default='/opt/homebrew/bin/ffmpeg')
    a = p.parse_args()
    source = a.video.resolve(strict=True)
    a.output.mkdir(parents=True, exist_ok=False, mode=0o700)
    def run(args):
        subprocess.run(args, check=True, timeout=120)
    run(['/usr/bin/say', '-v', 'Eddy (Japanese (Japan))', '-r', '185',
         '-o', str(a.output/'speech.aiff'), TEXT])
    run([a.decoder, '-nostdin', '-v', 'error', '-n', '-i', str(a.output/'speech.aiff'),
         '-ar', '48000', '-ac', '1', '-c:a', 'pcm_s16le', str(a.output/'speech.wav')])
    with wave.open(str(a.output/'speech.wav'), 'rb') as f:
        speech = array('h', f.readframes(f.getnframes()))
    stereo = array('h')
    for n in range(96000):
        t = n/48000
        phase = t % 1
        tone = int(6000*math.sin(2*math.pi*880*t)*min(1, phase/.005, (.1-phase)/.005)) if phase < .1 else 0
        stereo.extend((tone, 0) if t < 1 else (0, tone))
    for sample in speech:
        stereo.extend((sample, sample))
    with wave.open(str(a.output/'stereo.wav'), 'wb') as f:
        f.setnchannels(2)
        f.setsampwidth(2)
        f.setframerate(48000)
        f.writeframes(stereo.tobytes())
    run([a.ffmpeg, '-nostdin', '-v', 'error', '-n', '-stream_loop', '-1', '-i', str(source),
         '-i', str(a.output/'stereo.wav'), '-map', '0:v:0', '-map', '1:a:0', '-c:v', 'copy',
         '-c:a', 'aac', '-b:a', '256000', '-shortest', '-movflags', '+faststart', str(a.output/'source.mov')])
    manifest = dict(scope='Original synthetic Japanese speech; not microphone audio or music. Keep media local.',
                    voice='Eddy (Japanese (Japan))', rate=185, text=TEXT,
                    preamble='880 Hz for 100 ms: left at 0 s, right at 1 s; dual-mono speech from 2 s',
                    seconds=len(stereo)/2/48000, source_audio='AAC 256 kbps target, not lossless')
    (a.output/'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n')
    print(a.output/'source.mov')


if __name__ == '__main__':
    main()
