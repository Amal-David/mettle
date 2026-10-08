#!/usr/bin/env python3
"""Bounded v0.3 style regression against a Figma video, never a native golden.
Requires pre-rendered native frames at 10 fps and Pillow/ffmpeg. H264 is lossy;
thresholds are regression gates, not general pixel-perfect certification.
"""
from pathlib import Path
from PIL import Image, ImageChops
from compare_live import metrics
import argparse, hashlib, json, subprocess, sys
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'artifacts/motion-2026'
REGIONS = {'stacked':(0,20,180,130), 'scale':(190,0,350,145),
           'rotation':(380,0,580,165), 'back':(0,175,185,310)}
REFERENCE_SHA = '89133c560c84369011f8edce719b1ea172db5de8ba0f5bc2693462ab0b69f69b'
def bounds(image, region):
    crop = image.crop(region).getchannel('B')
    background = image.getpixel((599,319))[2]
    return ImageChops.difference(crop, Image.new('L',crop.size,background)).point(lambda v:255 if v>12 else 0).getbbox()
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=OUT)
    args = parser.parse_args()
    out = args.output
    video = ROOT / 'fixtures/motion-2026/styles.reference.mp4'
    if hashlib.sha256(video.read_bytes()).hexdigest() != REFERENCE_SHA:
        raise ValueError('Independent Figma reference changed; do not replace it with native output.')
    manifest = json.loads((out / 'native/manifest.json').read_text())
    if manifest['fps'] != 10 or len(manifest['frames']) != 21:
        raise ValueError('Expected 21 endpoint-inclusive frames at 10 fps.')
    refdir = out / 'reference'; refdir.mkdir(parents=True, exist_ok=True)
    subprocess.run(['ffmpeg','-v','error','-y','-i',str(video),'-fps_mode','passthrough',
                    '-start_number','0',str(refdir/'%04d.png')],check=True)
    rows = []
    for index, entry in enumerate(manifest['frames']):
        if entry['index'] != index or abs(entry['time']-index/10) > 1e-9:
            raise ValueError('Native timestamps do not match the independent Figma timeline.')
        reference = Image.open(refdir/f'{index:04}.png').convert('RGB')
        native = Image.open(out/'native'/entry['file']).convert('RGB')
        if reference.size != (600,320) or native.size != reference.size:
            raise ValueError('Unexpected frame dimensions.')
        row = {'index':index,'time':entry['time'], 'rgbMAE':metrics(reference,native)['rgbMAE'], 'regions':{}}
        for name,region in REGIONS.items():
            a,b = bounds(reference,region),bounds(native,region)
            error = 0 if a is None and b is None else 999 if a is None or b is None else max(abs(x-y) for x,y in zip(a,b))
            row['regions'][name] = {'rgbMAE':metrics(reference.crop(region),native.crop(region))['rgbMAE'],
                                    'referenceBounds':a,'nativeBounds':b,'boundsError':error}
        rows.append(row)
    if len({str(row['regions']['stacked']['nativeBounds']) for row in rows}) < 4:
        raise ValueError('Native motion did not advance; matching blank frames do not establish support.')
    summary = {'scope':'Live Figma style probe, 600x320, 10 fps, 21 frames; H264 is lossy.',
               'referenceSHA256':REFERENCE_SHA, 'frames':rows,
               'worstRGBMAE':max(r['rgbMAE'] for r in rows),
               'worstRegionRGBMAE':max(v['rgbMAE'] for r in rows for v in r['regions'].values()),
               'worstBoundsError':max(v['boundsError'] for r in rows for v in r['regions'].values()),
               'limitations':'Engine regression gates only. This does not certify arbitrary custom styles or all rotation/scale pivots.'}
    summary['pass'] = summary['worstRGBMAE']<=2.5 and summary['worstRegionRGBMAE']<=3 and summary['worstBoundsError']<=2
    (out/'style-comparison.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(json.dumps({k:v for k,v in summary.items() if k!='frames'},indent=2))
    return 0 if summary['pass'] else 1
if __name__ == '__main__':
    sys.exit(main())
