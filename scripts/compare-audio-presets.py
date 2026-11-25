#!/usr/bin/env python3
"""Compare app AAC presets on a private local video copy; never replace the input.

Signal checks detect gross loss only. They do not certify speech intelligibility,
music quality, or perceived synchronization.
"""
import argparse
from array import array
import importlib.util
import json
import math
from pathlib import Path
import subprocess
import sys
import shutil

spec = importlib.util.spec_from_file_location('encoder_comparison', Path(__file__).with_name('compare-encoders.py'))
shared = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shared)


def missing_active_bins(baseline, decoded):
    return [i for i, rms in enumerate(baseline['rms_20ms']) if rms > .01
            and (i >= len(decoded['rms_20ms']) or decoded['rms_20ms'][i] < .001)]


def signal(path, decoder):
    pcm = subprocess.run([str(decoder), '-nostdin', '-v', 'error', '-i', str(path),
                          '-map', '0:a:0', '-ar', '48000', '-ac', '2', '-c:a', 'pcm_f32le',
                          '-f', 'f32le', 'pipe:1'], capture_output=True, check=True, timeout=120).stdout
    samples = array('f', pcm)
    if sys.byteorder != 'little':
        samples.byteswap()
    if not samples or not all(math.isfinite(x) for x in samples):
        raise ValueError('Empty or non-finite decoded audio')
    bins = []
    for i in range(0, len(samples), 1920):  # 20 ms at 48 kHz stereo
        chunk = samples[i:i+1920]
        bins.append(math.sqrt(sum(x*x for x in chunk)/len(chunk)))
    pilots = []
    for second in [0, 1]:
        start = second * 48000 * 2
        chunk = samples[start:start+4800*2]
        pilots.append([math.sqrt(sum(x*x for x in chunk[c::2])/4800) for c in [0, 1]])
    return dict(samples_per_channel=len(samples)//2, peak=max(abs(x) for x in samples),
                rms_20ms=bins, pilot_channel_rms=pilots)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('input', type=Path)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--tools', type=Path, default=Path('/Applications/NotchCompressor.app/Contents/MacOS'))
    p.add_argument('--decoder', type=Path, default=Path('/opt/homebrew/bin/ffmpeg'))
    a = p.parse_args()
    source = a.input.resolve(strict=True)
    if not source.is_file() or source.suffix.lower() not in ['.mov', '.mp4', '.m4v']:
        p.error('Expected a video container')
    a.output.mkdir(parents=True, exist_ok=False, mode=0o700)
    original_hash = shared.digest(source)
    staged = a.output / ('input'+source.suffix.lower())
    shutil.copyfile(source, staged)
    if shared.digest(staged) != original_hash:
        raise ValueError('Input changed during staging')
    ffmpeg, ffprobe = a.tools/'ffmpeg', a.tools/'ffprobe'
    media, _ = shared.probe(ffprobe, staged, 120)
    if not 0 < float(media['format']['duration']) <= 120:
        raise ValueError('Use a short comparison sample, at most 120 seconds')
    audios = [s for s in media['streams'] if s['codec_type'] == 'audio']
    if len(audios) != 1 or audios[0].get('channels') not in [1, 2]:
        raise ValueError('Expected one mono or stereo audio stream')
    if len(media['streams']) != 2 or sum(s['codec_type'] == 'video' for s in media['streams']) != 1:
        raise ValueError('Expected one video and one audio stream without other tracks')
    def video_packets(path):
        raw, _ = shared.run([str(ffprobe), '-v', 'error', '-select_streams', 'v:0',
                            '-show_packets', '-show_data_hash', 'sha256', '-show_entries',
                            'packet=data_hash,pts_time,dts_time', '-of', 'json', str(path)], 120)
        return json.loads(raw)['packets']
    video = video_packets(staged)
    baseline = signal(staged, a.decoder)
    report = dict(scope='Audio-only signal/timing checks; no listening verdict. Document input provenance separately.',
                  encoder=shared.run([str(ffmpeg), '-version'], 30)[0].splitlines()[0],
                  decoder=shared.run([str(a.decoder), '-version'], 30)[0].splitlines()[0],
                  original_bytes=staged.stat().st_size, original_sha256=original_hash,
                  source_audio_bps=int(audios[0].get('bit_rate', 128000)),
                  source_signal=baseline, source_channels=audios[0]['channels'], trials=[])
    for quality, requested in [('gentle', 128000), ('balanced', 96000), ('compact', 64000)]:
        target = max(32000, min(requested, report['source_audio_bps']))
        dest = a.output/(quality+source.suffix.lower())
        _, encode = shared.run([str(ffmpeg), '-nostdin', '-v', 'error', '-xerror', '-n',
                               '-i', str(staged), '-map', '0:v:0', '-map', '0:a:0',
                               '-map_metadata', '0', '-map_chapters', '0', '-c:v', 'copy',
                               '-c:a', 'aac', '-b:a', str(target), '-movflags', '+faststart', str(dest)], 120)
        out, _ = shared.probe(ffprobe, dest, 120)
        _, validation = shared.run([str(ffmpeg), '-nostdin', '-v', 'error', '-xerror',
                                    '-err_detect', 'explode', '-i', str(dest), '-f', 'null', '-'], 120)
        decoded = signal(dest, a.decoder)
        oa = next(s for s in out['streams'] if s['codec_type'] == 'audio')
        missing = missing_active_bins(baseline, decoded)
        checks = dict(video_packets_and_timestamps_unchanged=video_packets(dest) == video,
                      channels_preserved=oa['channels'] == audios[0]['channels'],
                      duration_within_50ms=abs(float(out['format']['duration'])-float(media['format']['duration'])) < .05,
                      no_gross_audio_dropouts=not missing)
        row = dict(preset=quality, target_bps=target, output_bytes=dest.stat().st_size,
                   output_audio_bps=int(oa.get('bit_rate', 0)), encode_seconds=encode,
                   validation_seconds=validation, checks=checks, passed=all(checks.values()),
                   missing_active_20ms_bins=missing, signal=decoded)
        report['trials'].append(row)
        (a.output/'audio-results.json').write_text(json.dumps(report, indent=2)+'\n')
        print(quality, dest.stat().st_size, checks, flush=True)
    report['source_unchanged'] = shared.digest(source) == original_hash
    (a.output/'audio-results.json').write_text(json.dumps(report, indent=2)+'\n')
    if not report['source_unchanged'] or not all(t['passed'] for t in report['trials']):
        raise SystemExit('Comparison failed; inspect audio-results.json')


if __name__ == '__main__':
    main()
