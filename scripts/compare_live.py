#!/usr/bin/env python3
"""Compare native Metal pixels with independent Figma oracles. Pillow only.
Thresholds catch regressions, NOT certify universal/pixel-perfect compatibility.
PNG errors use premultiplied RGBA (transparent RGB is not meaningful).
H264 references are lossy; we also check position and opacity-sensitive RGB.
"""
from __future__ import annotations
import argparse, json, math, subprocess, sys
from pathlib import Path
from PIL import Image, ImageChops, ImageStat, ImageFilter
ROOT=Path(__file__).resolve().parents[1]
REGIONS={'linear':(24,24,184,124),'radial':(212,24,352,124),'paint-stack':(390,24,570,124),
         'hole':(24,152,154,252),'group-clip':(205,152,365,252),'outside-stroke':(390,133,565,250),
         'glyphs':(24,296,70,325),'smoothed-corners':(24,346,194,388)}
def pixels(im):
    return im.get_flattened_data() if hasattr(im,'get_flattened_data') else im.getdata()
def metrics(reference:Image.Image,actual:Image.Image)->dict:
    if reference.size!=actual.size:raise ValueError(f'Size mismatch: {reference.size} != {actual.size}')
    # Pillow RGBa performs premultiplication without color-space reinterpretation.
    a=reference.convert('RGBA').convert('RGBa');b=actual.convert('RGBA').convert('RGBa')
    diff=ImageChops.difference(a,b);stats=ImageStat.Stat(diff)
    hist=[0]*256
    for px in pixels(diff):hist[max(px)]+=1
    total=reference.width*reference.height
    def percentile(p):
        acc=0
        for i,n in enumerate(hist):
            acc+=n
            if acc>=p*total:return i
        return 255
    return {'rgbMAE':round(sum(stats.mean[:3])/3,6),'alphaMAE':round(stats.mean[3],6),
            'p95MaxChannelError':percentile(.95),'p99MaxChannelError':percentile(.99),
            'pixelsOver8Percent':round(100*sum(hist[9:])/total,6),
            'maxError':max(i for i,n in enumerate(hist) if n)}
def bbox(im):
    rgb=im.convert('RGB');bg=rgb.getpixel((3,3));mask=Image.new('L',im.size)
    mask.putdata([255 if max(abs(p[c]-bg[c]) for c in range(3))>18 else 0 for p in pixels(rgb)])
    # Suppress isolated compression ringing; card silhouette remains.
    return mask.filter(ImageFilter.MedianFilter(3)).getbbox()
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--native',type=Path,default=ROOT/'artifacts/phase2/native.png')
    ap.add_argument('--frames',type=Path,default=ROOT/'artifacts/phase2/motion-native')
    ap.add_argument('--output',type=Path,default=ROOT/'artifacts/phase2');args=ap.parse_args();args.output.mkdir(parents=True,exist_ok=True)
    ref=Image.open(ROOT/'fixtures/live/conformance.reference.png').convert('RGBA');native=Image.open(args.native).convert('RGBA')
    summary={'scope':'Live Figma-generated conformance fixtures, not a production animation; 600x420 PNG and 320x180 30fps H264 video.',
             'static':metrics(ref,native),'regions':{},'gates':[], 'limitations':'Different edge antialiasing and channel rounding remain. Thresholds are engineering regression gates, not pixel-perfect certification.'}
    for name,box in REGIONS.items():summary['regions'][name]=metrics(ref.crop(box),native.crop(box))
    def gate(name,actual,maximum):summary['gates'].append({'name':name,'actual':actual,'maximum':maximum,'pass':actual<=maximum})
    gate('static RGB MAE (8-bit levels)',summary['static']['rgbMAE'],.75)
    gate('static pixels over 8 levels (%)',summary['static']['pixelsOver8Percent'],1.5)
    gate('glyph region RGB MAE (8-bit levels)',summary['regions']['glyphs']['rgbMAE'],5)
    # These interior probes isolate semantics from antialiasing.
    probes=[(100,70),(275,70),(400,50),(225,175),(290,210),(80,190),(445,170),(100,367)]
    max_probe=max(abs(ref.getpixel(p)[c]-native.getpixel(p)[c]) for p in probes for c in range(4))
    gate('interior probe max channel error',max_probe,4)
    ImageChops.difference(ref,native).convert('RGB').point(lambda n:min(255,n*4)).save(args.output/'difference-4x.png')
    ref.save(args.output/'reference.png');native.save(args.output/'native.png')
    video=ROOT/'fixtures/live/motion.reference.mp4'
    reference_dir=args.output/'motion-reference';reference_dir.mkdir(exist_ok=True)
    subprocess.run(['ffmpeg','-v','error','-y','-i',str(video),'-fps_mode','passthrough','-start_number','0',str(reference_dir/'%04d.png')],check=True)
    manifest=json.loads((args.frames/'manifest.json').read_text())
    if abs(manifest['fps']-30)>1e-9:raise ValueError('Reference timeline requires exactly 30 fps')
    refs=sorted(reference_dir.glob('*.png'))
    if len(refs)!=len(manifest['frames']):raise ValueError(f'Frame count mismatch {len(refs)} vs {len(manifest["frames"])}')
    summary['motion']=[];panels=[]
    for entry,ref_file in zip(manifest['frames'],refs):
        r=Image.open(ref_file).convert('RGBA');n=Image.open(args.frames/entry['file']).convert('RGBA')
        rb,nb=bbox(r),bbox(n)
        error=max(abs(x-y) for x,y in zip(rb,nb)) if rb and nb else 1e9
        summary['motion'].append({'frame':entry['index'],'time':entry['time'],**metrics(r,n),'referenceBounds':rb,'nativeBounds':nb,'boundsError':error})
        if entry['index'] in [0,15,30,45,59]:
            panel=Image.new('RGB',(640,180));panel.paste(r,(0,0));panel.paste(n,(320,0));panels.append(panel)
    strip=Image.new('RGB',(640,180*len(panels)))
    for i,p in enumerate(panels):strip.paste(p,(0,180*i))
    strip.save(args.output/'motion-comparison.png')
    gate('all video frames bounding-box error (pixels)',max(x['boundsError'] for x in summary['motion']),2)
    gate('worst video frame RGB MAE (8-bit levels)',max(x['rgbMAE'] for x in summary['motion']),2.5)
    summary['pass']=all(x['pass'] for x in summary['gates'])
    (args.output/'comparison.json').write_text(json.dumps(summary,indent=2)+'\n')
    rows=''.join(f'<tr><td>{k}</td><td>{v["rgbMAE"]:.3f}</td><td>{v["p99MaxChannelError"]}</td><td>{v["pixelsOver8Percent"]:.2f}%</td></tr>' for k,v in summary['regions'].items())
    gates=''.join(f'<li>{"PASS" if g["pass"] else "FAIL"} — {g["name"]}: {g["actual"]} (limit {g["maximum"]})</li>' for g in summary['gates'])
    html=f'''<!doctype html><meta charset="utf-8"><title>Mettle 0.2 — live fidelity</title>
<style>body{{font:16px system-ui;max-width:1280px;margin:48px auto;padding:0 24px;color:#e7eef6;background:#0b1018}}h1{{font-size:40px}}p{{max-width:900px;line-height:1.6}}.grid{{display:grid;grid-template-columns:1fr 1fr;gap:24px}}img{{width:100%;height:auto;background:repeating-conic-gradient(#182433 0% 25%,#111a25 0% 50%) 50%/16px 16px}}table{{border-collapse:collapse;width:100%;max-width:900px}}td,th{{padding:10px;text-align:left;border-bottom:1px solid #2a3748}}li{{margin:8px 0}}.wide{{max-width:640px}}@media(max-width:700px){{.grid{{display:block}}}}</style>
<h1>Mettle 0.2</h1><p>Native Metal vs independent live Figma renders. No reference PNG or video is loaded by the runtime. Source geometry, fills and animation tracks drive every native frame.</p>
<div class="grid"><section><h2>Figma reference</h2><img src="reference.png"></section><section><h2>Native Metal</h2><img src="native.png"></section></div>
<h2>Measured—not pixel-perfect</h2><p>{summary['limitations']} The small “Ag8” label exercises glyph holes and curves, not text layout breadth. The lab fixtures were created in Figma for this project, not taken from a production design.</p><ul>{gates}</ul>
<table><tr><th>Region</th><th>RGB MAE /255</th><th>P99 max-channel error</th><th>Pixels &gt;8 levels</th></tr>{rows}</table>
<h2>Difference ×4</h2><img style="max-width:600px" src="difference-4x.png"><p>Amplified RGB differences; alpha error is measured separately. Rasterizers differ at edges.</p>
<h2>Motion: all {len(summary['motion'])} frames checked</h2><p>Representative frames at 0, 0.5, 1, 1.5 and 59/30 seconds. Figma H264 reference on the left, native Metal on the right. H264 is lossy; source timestamps, shape bounds and pixel errors are checked separately.</p><img class="wide" src="motion-comparison.png">
<p>Full measurements: <a href="comparison.json">comparison.json</a>. Source: Mettle — Native Fidelity Lab, file flxINzepb5BgRcRfGj0Tl5.</p>'''
    (args.output/'index.html').write_text(html)
    print(json.dumps({k:summary[k] for k in ['static','regions','gates','pass']},indent=2))
    return 0 if summary['pass'] else 1
if __name__=='__main__':sys.exit(main())
