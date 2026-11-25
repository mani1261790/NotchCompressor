#!/usr/bin/env python3
"""Create a local, offline comparison page beside compare-encoders.py results."""
import argparse
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('comparison', type=Path)
    args = parser.parse_args()
    root = args.comparison.resolve(strict=True)
    result = json.loads((root / 'results.json').read_text())
    sources = list(root.glob('input.*'))
    if len(sources) != 1 or sources[0].resolve().parent != root:
        parser.error('Expected one staged input file')
    labels = {
        'hevc-bitrate': 'HEVC・通常エンコード', 'hevc-fast': 'HEVC・速度優先',
        'h264-bitrate': 'H.264', 'hevc-quality-50': 'HEVC・品質指定50（実験）',
        'hevc-quality-65': 'HEVC・品質指定65（実験）', 'hevc-quality-80': 'HEVC・品質指定80（実験）',
    }
    clips = [dict(file=sources[0].name, label='元動画', bytes=result['original_bytes'], variant='source')]
    seen = set()
    for trial in result['trials']:
        if trial['status'] != 'passed' or trial['variant'] in seen:
            continue
        # Only serve comparison outputs inside this directory, never arbitrary paths.
        name = trial['output']
        if Path(name).name != name or not (root / name).is_file() or (root / name).resolve().parent != root:
            parser.error('Missing or invalid comparison output')
        seen.add(trial['variant'])
        clips.append(dict(file=name, label=labels.get(trial['variant'], trial['variant']),
                          variant=trial['variant'], bytes=trial['bytes']))
    data = dict(clips=clips, width=result['width'], height=result['height'],
                fps=result['fps'], seconds=result['seconds'],
                frameRatePolicy=result.get('frame_rate_policy', 'source'),
                preset=result.get('video_bitrate_preset', 'balanced'))
    template = Path(__file__).with_name('quality-review.html').read_text()
    encoded = json.dumps(data, ensure_ascii=False).replace('<', '\\u003c')
    output = root / 'quality-review.html'
    with output.open('x') as f:
        f.write(template.replace('__COMPARISON_DATA__', encoded))
    print(output)


if __name__ == '__main__':
    main()
