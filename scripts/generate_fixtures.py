#!/usr/bin/env python3
"""Generate deterministic SYNTHETIC test scenes. These are not Figma golden images."""
import json, math
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
I = dict(a=1,b=0,c=0,d=1,tx=0,ty=0)
def point(x=0,y=0): return dict(x=x,y=y)
def color(r,g,b,a=1): return dict(r=r,g=g,b=b,a=a)
def solid(c): return dict(kind='solid',color=c,opacity=1,transform=I,stops=[])
def gradient(a,b,kind='linear'):
    return dict(kind=kind,color=color(1,1,1),opacity=1,transform=I,stops=[dict(position=0,color=a),dict(position=1,color=b)])
def path(d,rule='NONZERO'): return dict(data=d,windingRule=rule)
def rect(w,h,r=0):
    r=min(r,w/2,h/2); k=.5522847498
    if not r: return f'M0 0 H{w} V{h} H0 Z'
    q=r*(1-k)
    return f'M{r} 0 H{w-r} C{w-q} 0 {w} {q} {w} {r} V{h-r} C{w} {h-q} {w-q} {h} {w-r} {h} H{r} C{q} {h} 0 {h-q} 0 {h-r} V{r} C0 {q} {q} 0 {r} 0 Z'
def ellipse(w,h):
    x=w/2;y=h/2;k=.5522847498
    return f'M{w} {y} C{w} {y+y*k} {x+x*k} {h} {x} {h} C{x-x*k} {h} 0 {y+y*k} 0 {y} C0 {y-y*k} {x-x*k} 0 {x} 0 C{x+x*k} 0 {w} {y-y*k} {w} {y} Z'
def draw(d,p,w,h,rule='NONZERO',role='fills'):
    return dict(paths=[path(d,rule)],paint=p,transform=I,size=point(w,h),paintIndex=0,role=role)
def node(id,x=0,y=0,w=100,h=100,draws=None,children=None,bindings=None,clip=None,opacity=1):
    return dict(id=id,name=id,transform=dict(I,tx=x,ty=y),size=point(w,h),origin=point(w/2,h/2),opacity=opacity,draws=draws or [],children=children or [],bindings=bindings or [],clip=clip or [])
def binding(field,base,values,times=None,ease=None):
    times=times or [0,1,2,3,4][:len(values)]
    return dict(field=field,base=[base] if isinstance(base,(int,float)) else base,tracks=[dict(operation='set',keyframes=[dict(time=t,value=[v] if isinstance(v,(int,float)) else v,easing=ease or dict(kind='cubic',control=[.4,0,.2,1])) for t,v in zip(times,values)])])
bg = gradient(color(.035,.05,.09),color(.07,.10,.15))
cyan=color(.25,.92,.84); violet=color(.56,.39,1); gold=color(1,.74,.35)
children=[]
# Left: independently animated vectors inside a real rounded clipping layer.
orb=node('orb',x=40,y=40,w=210,h=210,draws=[draw(ellipse(210,210),gradient(cyan,color(.05,.18,.32),'radial'),210,210)],bindings=[binding('translationY',40,[40,70,40],[0,2,4])])
donut=ellipse(145,145)+' '+ellipse(77,77)
# Centered hole encoded as a distinct even-odd subpath.
def shift_path_for_hole():
    outer=ellipse(145,145)
    inner=f'M111 72.5 C111 93.763 93.763 111 72.5 111 C51.237 111 34 93.763 34 72.5 C34 51.237 51.237 34 72.5 34 C93.763 34 111 51.237 111 72.5 Z'
    return outer+' '+inner
ring=node('ring',x=100,y=85,w=145,h=145,draws=[draw(shift_path_for_hole(),gradient(violet,gold),145,145,'EVENODD')],bindings=[binding('rotation',0,[0,180,360],[0,2,4],dict(kind='linear',control=[]))])
left=node('left-panel',x=24,y=24,w=320,h=350,draws=[draw(rect(320,350,28),solid(color(.08,.12,.18)),320,350)],children=[orb,ring],clip=[path(rect(320,350,28))])
children.append(left)
# Right: source-style independent scale tracks, anchored at bottom of each bar.
bars=[]
for i in range(12):
    height=50+(i*37)%135
    n=node(f'bar-{i}',x=22+i*23,y=245-height,w=12,h=height,draws=[draw(rect(12,height,6),gradient(cyan,violet),12,height)],bindings=[binding('scaleY',1,[1,.35+(i%4)*.2,1.1,1],[0,1.3,2.7,4])])
    n['origin']=point(6,height);bars.append(n)
right=node('right-panel',x=360,y=24,w=336,h=350,draws=[draw(rect(336,350,28),solid(color(.08,.12,.18)),336,350)],children=bars,clip=[path(rect(336,350,28))])
children.append(right)
# Group opacity regression: overlap remains uniform after isolation.
chips=[node('chip-a',x=0,y=0,w=72,h=28,draws=[draw(rect(72,28,14),solid(cyan),72,28)]),node('chip-b',x=44,y=0,w=72,h=28,draws=[draw(rect(72,28,14),solid(cyan),72,28)])]
children.append(node('opacity-group',x=28,y=410,w=116,h=28,children=chips,opacity=.65))
children.append(node('progress-track',x=172,y=421,w=470,h=5,draws=[draw(rect(470,5,2.5),solid(color(.15,.23,.30)),470,5)]))
children.append(node('moving-marker',x=172,y=415,w=18,h=18,draws=[draw(ellipse(18,18),solid(gold),18,18)],bindings=[binding('translationX',172,[172,624,172],[0,2,4])]))
root=node('demo-root',w=720,h=480,draws=[draw(rect(720,480,24),bg,720,480)],children=children)
doc=dict(format='figma-metal',version=1,scenes=[dict(name='Synthetic renderer conformance demo',width=720,height=480,duration=4,loop='loop',root=root)],diagnostics=[])
for dest in [ROOT/'examples/demo.figmetal.json',ROOT/'Sources/FigmaMetalDemo/Resources/demo.figmetal.json']:
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(doc,indent=2)+'\n')
print('Generated examples/demo.figmetal.json (synthetic fixture)')
