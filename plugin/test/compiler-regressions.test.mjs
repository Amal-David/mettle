import test from 'node:test';
import assert from 'node:assert/strict';
import {compileScene,compileTransition} from '../src/compiler.mjs';

const shape=(id='a')=>({id,name:id,type:'RECTANGLE',width:40,height:20,visible:true,opacity:1,
  relativeTransform:[[1,0,10],[0,1,20]],fills:[{type:'SOLID',color:{r:1,g:0,b:0}}],
  fillGeometry:[{data:'M0 0 H40 V20 H0 Z',windingRule:'NONZERO'}],children:[]});
const key=(time,value)=>({timelinePosition:time,easing:{type:'LINEAR'},value:{type:'FLOAT',value}});
const manual=(id='manual',values=[0,1])=>({id,baseValue:{type:'FLOAT',value:values[0]},keyframes:values.map((value,time)=>key(time,value))});
const resolved=(binding=manual())=>({baseValue:binding.baseValue,timelineDuration:1,tracks:[{id:binding.id,keyframeOperation:'SET',keyframes:binding.keyframes}]});
const errors=document=>document.diagnostics.filter(d=>d.severity==='error');

test('partially resolved animations cannot silently drop another manual field',()=>{
  const source=shape();source.manualKeyframeTracks={TRANSLATION_X:manual('x',[0,40]),OPACITY:manual('alpha')};
  source.animations={OPACITY:resolved(source.manualKeyframeTracks.OPACITY)};
  const document=compileScene(source);
  assert.ok(errors(document).some(d=>d.code==='UNRESOLVED_MANUAL_TRACK'&&d.message.includes('TRANSLATION_X')));
  assert.deepEqual(document.sourceMotion.a.manualKeyframeTracks,source.manualKeyframeTracks);
});

test('manual paint tracks receive the same partial-resolution guard',()=>{
  const source=shape();source.manualKeyframeTracks={fills:{0:manual('paint')}};source.animations={OPACITY:resolved()};
  assert.ok(errors(compileScene(source)).some(d=>d.code==='UNRESOLVED_MANUAL_TRACK'&&d.message.includes('fills.0')));
});

test('style tracks on a field do not conceal its unresolved manual track',()=>{
  const source=shape();source.manualKeyframeTracks={OPACITY:manual('manual-alpha')};source.animations={OPACITY:resolved(manual('style-alpha'))};
  assert.ok(errors(compileScene(source)).some(d=>d.code==='UNRESOLVED_MANUAL_TRACK'));
});

test('a resolved manual track is compiled exactly once',()=>{
  const source=shape();source.manualKeyframeTracks={OPACITY:manual()};source.animations={OPACITY:resolved(source.manualKeyframeTracks.OPACITY)};
  const document=compileScene(source);assert.deepEqual(errors(document),[]);
  assert.equal(document.scenes[0].root.bindings.length,1);assert.equal(document.scenes[0].root.bindings[0].tracks.length,1);
});

test('empty resolved track arrays block at export instead of producing an unloadable file',()=>{
  const source=shape();source.animations={OPACITY:{...resolved(),tracks:[]}};
  assert.ok(errors(compileScene(source)).some(d=>d.code==='MOTION_BINDING'&&d.message.includes('Empty')));
});

test('nested prototype reactions remain visible in source provenance and diagnostics',()=>{
  const source=shape(),child=shape('hotspot');source.children=[child];
  child.reactions=[{trigger:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId:'b'}]}];
  const before=structuredClone(source),document=compileScene(source);
  assert.ok(document.diagnostics.some(d=>d.code==='PROTOTYPE_EVENTS_NOT_EXPORTED'&&d.nodeID==='hotspot'));
  assert.deepEqual(document.sourceMotion.hotspot.reactions,child.reactions);
  assert.deepEqual(source,before);
  assert.equal(document.scenes[0].root.children[0].bindings.length,0);
});

test('a selected hidden node cannot be resurrected by its opacity binding',()=>{
  const source=shape();source.visible=false;source.animations={OPACITY:resolved(manual('alpha',[1,1]))};
  const root=compileScene(source).scenes[0].root;assert.equal(root.opacity,0);assert.deepEqual(root.bindings,[]);
});

test('source timeout is placed once before a bounded A→B clip',()=>{
  const from=shape('from');from.children=[shape('orb')];const to=structuredClone(from);to.id='to';to.children[0].relativeTransform[0][2]=110;
  const document=compileTransition(from,to,{duration:.4,delay:.001,easing:{type:'LINEAR'}});
  assert.deepEqual(errors(document),[]);assert.equal(document.scenes[0].duration,.401);
  const track=document.scenes[0].root.children[0].bindings[0].tracks[0];
  assert.equal(track.timelineOffset,.001);assert.deepEqual(track.keyframes.map(k=>k.time),[0,.4]);
  assert.deepEqual(track.keyframes.map(k=>k.value),[[10],[110]]);
});

test('transition delay validation rejects invalid timing and leaves zero delay backward compatible',()=>{
  const from=shape();from.children=[shape('orb')];const to=structuredClone(from);to.children[0].relativeTransform[0][2]=110;
  for(const delay of [-1,Infinity,NaN,3601,'0.1']) assert.throws(()=>compileTransition(from,to,{delay}),/delay/);
  const document=compileTransition(from,to,{duration:.4,delay:0});
  assert.equal(document.scenes[0].duration,.4);assert.equal(document.scenes[0].root.children[0].bindings[0].tracks[0].timelineOffset,undefined);
});

test('a solid fill can appear on unchanged source geometry with alpha applied once',()=>{
  const from=shape(),to=structuredClone(from);from.fills=[];to.fills[0].opacity=.08;
  const document=compileTransition(from,to),root=document.scenes[0].root;
  assert.deepEqual(errors(document),[]);assert.equal(root.draws.length,1);
  assert.deepEqual(root.draws[0].paths,to.fillGeometry);assert.equal(root.draws[0].paint.opacity,0);
  assert.deepEqual(root.bindings[0].base,[1,0,0,0]);
  assert.deepEqual(root.bindings[0].tracks[0].keyframes.at(-1).value,[1,0,0,.08]);
  assert.deepEqual(from.fills,[]);
});

test('disappearing fills and paint visibility changes keep source stack indices',()=>{
  const from=shape(),to=structuredClone(from);to.fills=[];
  const removed=compileTransition(from,to);assert.deepEqual(errors(removed),[]);
  assert.deepEqual(removed.scenes[0].root.bindings[0].tracks[0].keyframes.at(-1).value,[1,0,0,0]);
  from.fills=[{...from.fills[0],visible:false},{type:'SOLID',color:{r:0,g:1,b:0}}];
  to.fills=structuredClone(from.fills);to.fills[0].visible=true;
  const added=compileTransition(from,to);assert.deepEqual(errors(added),[]);
  assert.deepEqual(added.scenes[0].root.draws.map(draw=>draw.paintIndex),[0,1]);
  assert.equal(added.scenes[0].root.bindings[0].field,'fills:0');
});

test('fill appearance cannot conceal a path change or an unsupported gradient addition',()=>{
  const from=shape(),to=structuredClone(from);from.fills=[];to.fillGeometry[0].data='M0 0 L40 20 L0 20 Z';
  assert.ok(errors(compileTransition(from,to)).some(d=>d.code==='TRANSITION_DRAW_GEOMETRY'));
  to.fillGeometry=structuredClone(from.fillGeometry);to.fills=[{type:'GRADIENT_LINEAR',gradientTransform:[[1,0,0],[0,1,0]],gradientStops:[{position:0,color:{r:1,g:0,b:0,a:1}},{position:1,color:{r:0,g:0,b:1,a:1}}]}];
  assert.ok(errors(compileTransition(from,to)).some(d=>d.code==='TRANSITION_DRAW_COUNT'));
});

test('an explicit local viewport preserves overflow without scaling source geometry',()=>{
  const source=shape();source.children=[shape('child')];const before=structuredClone(source);
  const scene=compileScene(source,{viewport:{x:-3,y:-8,width:60,height:48}}).scenes[0];
  assert.equal(scene.width,60);assert.equal(scene.height,48);
  assert.deepEqual(scene.root.transform,{a:1,b:0,c:0,d:1,tx:3,ty:8});
  assert.deepEqual(scene.root.size,{x:40,y:20});
  assert.deepEqual(scene.root.children[0].transform,{a:1,b:0,c:0,d:1,tx:10,ty:20});
  assert.deepEqual(scene.root.draws[0].paths,source.fillGeometry);
  assert.deepEqual(source,before);
});

test('a shared transition viewport cannot become spurious root translation motion',()=>{
  const from=shape();from.children=[shape('child')];const to=structuredClone(from);to.children[0].relativeTransform[0][2]+=20;
  const scene=compileTransition(from,to,{viewport:{x:0,y:-8,width:60,height:48}}).scenes[0];
  assert.equal(scene.root.transform.ty,8);assert.deepEqual(scene.root.bindings,[]);
  assert.deepEqual(scene.root.children[0].bindings[0].tracks[0].keyframes.map(k=>k.value),[[10],[30]]);
});

test('invalid or implicit content viewports cannot silently change framing',()=>{
  for(const viewport of [null,'content',{},[],{x:0,y:0,width:0,height:1},{x:NaN,y:0,width:1,height:1},{x:0,y:0,width:1,height:Infinity},{x:0,y:0,width:16385,height:1}]) {
    assert.throws(()=>compileScene(shape(),{viewport}),/Viewport/);
  }
});
