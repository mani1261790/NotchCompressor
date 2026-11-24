#!/usr/bin/env python3
"""Local-only video encoder comparison. Never replaces or uploads the input."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import random
import statistics
import subprocess
import time
import shutil


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def run(command, timeout):
    start = time.perf_counter()
    result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
    elapsed = time.perf_counter() - start
    if result.returncode:
        raise RuntimeError(result.stderr[-4000:])
    return result.stdout, elapsed


def probe(tool, path, timeout):
    raw, elapsed = run([str(tool), '-v', 'error', '-protocol_whitelist', 'file,pipe',
                        '-show_streams', '-show_format', '-of', 'json', str(path)], timeout)
    return json.loads(raw), elapsed


def packets(tool, path, timeout):
    raw, elapsed = run([str(tool), '-v', 'error', '-select_streams', 'a', '-show_packets',
                        '-show_data_hash', 'sha256', '-show_entries', 'packet=data_hash,pts_time',
                        '-of', 'json', str(path)], timeout)
    return json.loads(raw).get('packets', []), elapsed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('input', type=Path)
    parser.add_argument('--output', type=Path, required=True, help='New local directory; must not exist')
    parser.add_argument('--tools', type=Path, default=Path(__file__).resolve().parents[1] / '.build' / 'vendor' / ('install-' + platform.machine()) / 'bin')
    parser.add_argument('--repeats', type=int, default=3)
    parser.add_argument('--timeout', type=int, default=900, help='Seconds per subprocess')
    args = parser.parse_args()
    if not 1 <= args.repeats <= 10 or args.timeout <= 0:
        parser.error('repeats must be 1–10 and timeout positive')
    source = args.input.resolve(strict=True)
    if not source.is_file() or source.suffix.lower() not in ['.mov', '.mp4', '.m4v']:
        parser.error('Use a MOV/MP4/M4V file')
    ffmpeg = args.tools.resolve() / 'ffmpeg'
    ffprobe = args.tools.resolve() / 'ffprobe'
    # Private staging contains media and local error details; do not publish it.
    args.output.mkdir(parents=True, exist_ok=False, mode=0o700)
    output = args.output.resolve()
    staged = output / ('input' + source.suffix.lower())
    original_hash = digest(source)
    shutil.copyfile(source, staged)
    if digest(staged) != original_hash:
        raise RuntimeError('Source changed during copying; comparison stopped')
    info, analysis_time = probe(ffprobe, staged, args.timeout)
    videos = [s for s in info['streams'] if s['codec_type'] == 'video']
    audios = [s for s in info['streams'] if s['codec_type'] == 'audio']
    if len(videos) != 1 or len(audios) > 1 or len(info['streams']) != len(videos) + len(audios):
        raise RuntimeError('Only one video and at most one audio stream are supported')
    v = videos[0]
    if v.get('pix_fmt') not in ['yuv420p', 'yuvj420p', 'nv12', 'yuv422p', 'yuvj422p', 'yuv444p', 'yuvj444p'] or v.get('color_transfer') in ['smpte2084', 'arib-std-b67'] or v.get('color_primaries') == 'bt2020':
        raise RuntimeError('Only SDR, 8-bit, opaque video is supported')
    num, den = map(float, v['avg_frame_rate'].split('/'))
    fps = num / den
    duration = float(info['format']['duration'])
    source_rate = int(v.get('bit_rate', 0))
    target = int(max(150000, min(v['width'] * v['height'] * fps * 0.06,
                                  source_rate * 0.65 if source_rate > 0 else 12000000, 12000000)))
    audio_packets, _ = packets(ffprobe, staged, args.timeout)
    variants = [
        ('hevc-bitrate', 'hevc_videotoolbox', ['-b:v', str(target)]),
        ('hevc-fast', 'hevc_videotoolbox', ['-b:v', str(target), '-prio_speed', '1']),
        ('h264-bitrate', 'h264_videotoolbox', ['-b:v', str(target)]),
    ] + [(f'hevc-quality-{q}', 'hevc_videotoolbox', ['-q:v', str(q)]) for q in [50, 65, 80]]
    trials = [(repeat, variant) for repeat in range(1, args.repeats + 1) for variant in variants]
    random.Random(20261125).shuffle(trials)
    version, _ = run([str(ffmpeg), '-version'], args.timeout)
    report = dict(schema=1, ffmpeg=version.splitlines()[0], machine=platform.machine(),
                  os=platform.mac_ver()[0], width=v['width'], height=v['height'], fps=fps,
                  seconds=duration, original_bytes=staged.stat().st_size, target_bps=target,
                  analysis_seconds=analysis_time, seed=20261125, trials=[],
                  scope='Source fps preserved, audio copied. Copy and integrity hashing excluded from total. Not an end-to-end app benchmark.',
                  visual_review='pending; no optimal codec or quality is inferred from timing alone')
    for repeat, (label, codec, options) in trials:
        name = f'{label}-{repeat}'
        dest = output / (name + source.suffix.lower())
        row = dict(variant=label, repeat=repeat, output=dest.name, status='failed')
        try:
            command = [str(ffmpeg), '-nostdin', '-hide_banner', '-v', 'error', '-xerror', '-n',
                       '-protocol_whitelist', 'file,pipe', '-noautorotate', '-i', str(staged),
                       '-map', '0:v:0', '-map', '0:a?', '-map_metadata', '0', '-map_chapters', '0',
                       '-c:v', codec, '-allow_sw', '0', '-pix_fmt', 'yuv420p',
                       '-fps_mode:v', 'passthrough', '-enc_time_base:v', 'demux']
            if codec == 'hevc_videotoolbox':
                command += ['-tag:v', 'hvc1']
            command += options + ['-c:a', 'copy', '-movflags', '+faststart', '-f', 'mov' if source.suffix.lower() == '.mov' else 'mp4', str(dest)]
            _, encode = run(command, args.timeout)
            converted, output_probe = probe(ffprobe, dest, args.timeout)
            ov = next(s for s in converted['streams'] if s['codec_type'] == 'video')
            if (ov['width'], ov['height']) != (v['width'], v['height']) or abs(float(converted['format']['duration']) - duration) > max(0.25, 2 / fps):
                raise RuntimeError('Output dimensions or duration do not match')
            _, validate = run([str(ffmpeg), '-nostdin', '-v', 'error', '-xerror', '-err_detect', 'explode',
                               '-protocol_whitelist', 'file,pipe', '-i', str(dest), '-map', '0:v:0', '-map', '0:a?', '-f', 'null', '-'], args.timeout)
            converted_audio, audio_check = packets(ffprobe, dest, args.timeout)
            if converted_audio != audio_packets:
                raise RuntimeError('Copied audio packets or timing changed')
            row.update(status='passed', encode_seconds=encode, output_probe_seconds=output_probe,
                       validation_seconds=validate, audio_check_seconds=audio_check,
                       total_seconds=analysis_time + encode + output_probe + validate + audio_check,
                       bytes=dest.stat().st_size, smaller=dest.stat().st_size < staged.stat().st_size)
        except (RuntimeError, subprocess.TimeoutExpired) as error:
            (output / (name + '.error.txt')).write_text(str(error))
            row['error_file'] = name + '.error.txt'
        report['trials'].append(row)
        (output / 'results.json').write_text(json.dumps(report, indent=2))
        print(name, row['status'], flush=True)
    report['source_unchanged'] = digest(source) == original_hash
    report['summary'] = {}
    for label, _, _ in variants:
        passed = [r for r in report['trials'] if r['variant'] == label and r['status'] == 'passed']
        report['summary'][label] = dict(passed=len(passed), expected=args.repeats,
            median_total_seconds=statistics.median(r['total_seconds'] for r in passed) if passed else None,
            median_bytes=statistics.median(r['bytes'] for r in passed) if passed else None)
    (output / 'results.json').write_text(json.dumps(report, indent=2))
    (output / 'visual-review.md').write_text('# Visual review (not yet performed)\n\nCompare input and each candidate at 100% scale and during playback.\nRecord small text, colored text, scrolling, animation, audio sync, and any artifacts.\nChoose acceptable quality first, then compare size and total time.\n\n| Variant | Text | Motion | Sync | Acceptable? | Notes |\n|---|---|---|---|---|---|\n' + ''.join(f'| {label} | pending | pending | pending | pending | |\n' for label, _, _ in variants))
    if not report['source_unchanged']:
        raise RuntimeError('Input changed externally during comparison; results are not valid')
    if any(r['status'] != 'passed' for r in report['trials']):
        raise SystemExit('Some candidates failed or are unsupported; see local error files')


if __name__ == '__main__':
    main()
