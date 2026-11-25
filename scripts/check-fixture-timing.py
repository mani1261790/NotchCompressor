#!/usr/bin/env python3
"""Check timing of make-quality-fixture.py media, not arbitrary user videos.

Requires development FFmpeg with crop/scale/rawvideo/PCM support. Does not
modify media. This is objective timing evidence, not a playback quality rating.
"""
import argparse
from array import array
import hashlib
import json
from pathlib import Path
import subprocess
import sys


def run(command):
    return subprocess.run(command, check=True, capture_output=True, timeout=120).stdout


def inspect(path, ffmpeg, ffprobe):
    info = json.loads(run([ffprobe, '-v', 'error', '-show_streams', '-of', 'json', str(path)]))
    video = next(s for s in info['streams'] if s['codec_type'] == 'video')
    if (video['width'], video['height'], video['avg_frame_rate']) != (1920, 1080, '60/1'):
        raise ValueError('Expected the original 1080p60 fixture geometry')
    frames = json.loads(run([ffprobe, '-v', 'error', '-select_streams', 'v:0',
        '-show_frames', '-show_entries', 'frame=best_effort_timestamp_time',
        '-of', 'json', str(path)]))['frames']
    timestamps = [f['best_effort_timestamp_time'] for f in frames]
    audio_packets = json.loads(run([ffprobe, '-v', 'error', '-select_streams', 'a:0',
        '-show_packets', '-show_entries', 'packet=pts_time', '-of', 'json', str(path)]))['packets']
    audio_timestamps = [packet['pts_time'] for packet in audio_packets]
    if len(timestamps) != 720:
        raise ValueError(f'Expected 720 frames, got {len(timestamps)}')
    # Sample inside the flash rectangle, far from edges and all other content.
    pixels = run([ffmpeg, '-nostdin', '-v', 'error', '-i', str(path),
        '-map', '0:v:0', '-vf', 'crop=16:16:1740:990,scale=1:1',
        '-fps_mode', 'passthrough', '-pix_fmt', 'gray', '-f', 'rawvideo', 'pipe:1'])
    if len(pixels) != len(timestamps):
        raise ValueError('Decoded flash samples do not match frame count')
    flashes = [i for i, value in enumerate(pixels) if value > 180]
    pcm = run([ffmpeg, '-nostdin', '-v', 'error', '-i', str(path),
        '-map', '0:a:0', '-ac', '1', '-ar', '48000', '-c:a', 'pcm_s16le',
        '-f', 's16le', 'pipe:1'])
    samples = array('h', pcm)
    if sys.byteorder != 'little':
        samples.byteswap()
    # 10 ms bins, amplitude > 1% of full scale. AAC priming/ringing means
    # this is a coarse event detector, not a sample-perfect source sync claim.
    active = [max(abs(x) for x in samples[i:i+480]) > 328
              for i in range(0, len(samples), 480)]
    beep_bins = [i for i, on in enumerate(active) if on and (i == 0 or not active[i-1])]
    starts = [i for i in flashes if i == 0 or i-1 not in flashes]
    return dict(timestamps=timestamps, audio_timestamps=audio_timestamps, flash_frames=flashes,
                flash_start_seconds=[float(timestamps[i]) for i in starts],
                beep_start_seconds=[i / 100 for i in beep_bins],
                pcm_sha256=hashlib.sha256(pcm).hexdigest(), pcm_samples=len(samples))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('reference', type=Path)
    parser.add_argument('candidates', type=Path, nargs='+')
    parser.add_argument('--ffmpeg', default='/opt/homebrew/bin/ffmpeg')
    parser.add_argument('--ffprobe', default='/opt/homebrew/bin/ffprobe')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('Choose a new output file')
    reference = inspect(args.reference, args.ffmpeg, args.ffprobe)
    starts = reference['flash_start_seconds']
    beeps = reference['beep_start_seconds']
    if len(starts) != 12 or len(beeps) != 12:
        raise ValueError('Reference does not contain the expected 12 sync events')
    if any(abs(a-b) > 0.03 for a, b in zip(starts, beeps)):
        raise ValueError('Reference flash/beep alignment exceeds 30 ms tolerance')
    report = dict(scope='Objective checks for generated fixture; no subjective playback rating',
                  decoder=run([args.ffmpeg, '-version']).decode().splitlines()[0],
                  reference={k: v for k, v in reference.items() if k not in ['timestamps', 'audio_timestamps', 'flash_frames']},
                  candidates=[])
    for path in args.candidates:
        result = inspect(path, args.ffmpeg, args.ffprobe)
        checks = dict(frame_timestamps_match=result['timestamps'] == reference['timestamps'],
                      audio_timestamps_match=result['audio_timestamps'] == reference['audio_timestamps'],
                      flash_frames_match=result['flash_frames'] == reference['flash_frames'],
                      decoded_audio_matches=result['pcm_sha256'] == reference['pcm_sha256'],
                      audio_sample_count_matches=result['pcm_samples'] == reference['pcm_samples'])
        report['candidates'].append(dict(file=path.name, **checks, passed=all(checks.values())))
        print(path.name, checks, flush=True)
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    if not all(r['passed'] for r in report['candidates']):
        raise SystemExit('Timing mismatch; inspect report')


if __name__ == '__main__':
    main()
