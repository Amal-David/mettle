import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
import {compileScene,compileTransition,easing} from '../src/compiler.mjs';
import {resolveMotionVariables,trackPlacement} from '../src/motion.mjs';
import {createCapture} from '../src/capture.mjs';
const clone=x=>structuredClone(x);
const key=(time,value,curve={type:'LINEAR'})=>({timelinePosition:time,value:{type:'FLOAT',value},easing:curve});
const style=(id,offset,duration)=>({id,styleId:'user-defined/opaque-id',name:'Custom brand motion',timelineOffset:offset,duration,props:{delay:offset}});
const track=(s,values=[-24,0],operation='OFFSET')=>({id:s.id+'-track',animationPreset:clone(s),keyframeOperation:operation,keyframes:values.map((v,i)=>key(i*s.duration,v))});
const binding=(tracks,base=40)=>({baseValue:{type:'FLOAT',value:base},timelineDuration:2,tracks});
const shape=()=>({id:'node',name:'Layer',type:'RECTANGLE',width:100,height:64,relativeTransform:[[1,0,40],[0,1,40]],visible:true,
  fills:[{type:'SOLID',color:{r:.5,g:.4,b:1}}],fillGeometry:[{data:'M0 0 L100 0 L100 64 L0 64 Z',windingRule:'NONZERO'}],strokes:[]});
const errors=d=>d.diagnostics.filter(i=>i.severity==='error');
function custom(){const s=shape(),a=style('custom:a',.2,.8),b=style('custom:b',1.5,.4);s.animationStyles=[a,b];s.animations={TRANSLATION_X:binding([track(a),track(b,[0,24])])};return s;}

test('composed custom styles preserve local keys, placement, order and opaque IDs',()=>{
  const source=custom(),before=clone(source),doc=compileScene(source);assert.deepEqual(source,before);assert.equal(errors(doc).length,0);
  assert.equal(doc.version,2);const b=doc.scenes[0].root.bindings[0];assert.deepEqual(b.base,[0]);
  assert.deepEqual(b.tracks.map(t=>t.operation),['offset','offset']);assert.deepEqual(b.tracks.map(t=>t.timelineOffset),[.2,1.5]);
  assert.deepEqual(b.tracks[0].keyframes.map(k=>k.time),[0,.8]);assert.deepEqual(doc.sourceMotion.node.animationStyles,source.animationStyles);
});
test('duration includes style placement without double-adding props.delay',()=>{
  const s=custom();s.animationStyles[1].timelineOffset=3;s.animations.TRANSLATION_X.tracks[1].animationPreset.timelineOffset=3;
  assert.equal(compileScene(s).scenes[0].duration,3.4);
});
test('manual keys stay global; style delay is not applied to manual tracks',()=>{
  const s=custom();s.animations.OPACITY=binding([{keyframes:[key(.1,0),key(.9,1)],keyframeOperation:'SET'}],1);
  const b=compileScene(s).scenes[0].root.bindings.find(b=>b.field==='opacity');assert.equal(b.tracks[0].timelineOffset,undefined);assert.equal(b.tracks[0].keyframes[0].time,.1);
});
test('unresolved custom style blocks even when manual motion exists',()=>{
  const s=custom();s.animations={};s.manualKeyframeTracks={OPACITY:{baseValue:{type:'FLOAT',value:1},keyframes:[key(0,1),key(1,0)]}};
  const d=compileScene(s);assert.ok(errors(d).some(x=>x.code==='UNRESOLVED_ANIMATION_STYLE'));assert.equal(d.sourceMotion.node.animationStyles.length,2);
});
test('missing one style in a partially resolved host blocks rather than dropping it',()=>{
  const s=custom();s.animations.TRANSLATION_X.tracks.pop();assert.ok(errors(compileScene(s)).some(x=>x.code==='UNRESOLVED_ANIMATION_STYLE'));
});
test('style offset validation fails on missing, negative, nonfinite and global-looking keys',()=>{
  for(const offset of [undefined,-1,NaN,Infinity,86401])assert.throws(()=>trackPlacement({animationPreset:{id:'x',timelineOffset:offset},keyframes:[]}));
  assert.throws(()=>trackPlacement({animationPreset:style('x',2,1),keyframes:[key(2,0),key(3,1)]}),/beyond/);
});
test('exact Back curve including overshoot is retained, not generic CSS ease-out',()=>{
  const curve={type:'EASE_OUT_BACK',easingFunctionCubicBezier:{x1:.45,y1:1.45,x2:.8,y2:1}};
  assert.deepEqual(easing(curve),{kind:'cubic',control:[.45,1.45,.8,1]});assert.throws(()=>easing({type:'EASE_OUT_BACK'}),/exact/);
});
test('source cubic overrides generic named easing; HOLD ignores stale cubic',()=>{
  const c={x1:.1,y1:.2,x2:.6,y2:.7};assert.deepEqual(easing({type:'EASE_OUT',easingFunctionCubicBezier:c}).control,[.1,.2,.6,.7]);
  assert.equal(easing({type:'HOLD',easingFunctionCubicBezier:c}).kind,'hold');
});
test('spring with cached cubic is still rejected; nonfinite cubic fails closed',()=>{
  assert.throws(()=>easing({type:'CUSTOM_SPRING',easingFunctionCubicBezier:{x1:0,y1:0,x2:1,y2:1}}),/spring/);
  assert.throws(()=>easing({type:'EASE_OUT',easingFunctionCubicBezier:{x1:NaN,y1:0,x2:1,y2:1}}),/Invalid/);
});
test('duplicate XY and X fields cannot overwrite each other',()=>{
  const s=custom();s.animations.TRANSLATION_XY={baseValue:{type:'VECTOR',value:{x:0,y:0}},tracks:[{keyframes:[{timelinePosition:0,value:{type:'VECTOR',value:{x:0,y:0}}}],keyframeOperation:'SET'}]};
  assert.ok(errors(compileScene(s)).some(x=>x.code==='DUPLICATE_MOTION_FIELD'));
});
test('new text payloads block and remain in sourceMotion; no glyph positions invented',()=>{
  const s=shape();s.type='TEXT';s.animations={TEXT_DATA:{baseValue:{type:'TEXT_DATA',value:'one'},tracks:[{keyframes:[]}],timelineDuration:2}};
  const d=compileScene(s);assert.ok(errors(d).some(x=>x.code==='UNSUPPORTED_MOTION_FIELD'));assert.equal(d.sourceMotion.node.animations.TEXT_DATA.baseValue.value,'one');
});
test('unhandled timeline payload blocks; capability report does not certify absent audio',()=>{
  const s=shape();s.timelines=[{id:'t',duration:2,unrecognizedPayload:{future:true}}];const d=compileScene(s);
  assert.ok(errors(d).some(x=>x.code==='UNSUPPORTED_TIMELINE_DATA'));assert.ok(d.sourceMotion.node.timelines[0].unrecognizedPayload);
  assert.match(d.motionSupport.audioTimeline,/no published/);assert.match(d.motionSupport.textAnimation,/not supported/);
});
test('whole-node text opacity still uses native source paths',()=>{
  const s=shape();s.type='TEXT';const a=style('fade',.4,.5);s.animationStyles=[a];s.animations={OPACITY:binding([track(a,[0,1],'SCALE')],1)};
  const d=compileScene(s);assert.equal(errors(d).length,0);assert.deepEqual(d.scenes[0].root.draws[0].paths,s.fillGeometry);
});
test('A-to-B compiler retains absolute-coordinate behavior and scene version 2',()=>{
  const a=shape(),b=clone(a);b.relativeTransform[0][2]=100;const d=compileTransition(a,b);
  assert.equal(d.version,2);assert.equal(errors(d).length,0);
});
test('easing tokens resolve in consumer mode once per variable and keep raw source unchanged',async()=>{
  const consumer=shape(),alias={type:'VARIABLE_ALIAS',id:'easing'},raw={keys:[{easing:alias},{easing:alias}]},before=clone(raw);let calls=0;
  const f={variables:{async getVariableByIdAsync(id){calls++;assert.equal(id,'easing');return {resolveForConsumer(n){assert.equal(n,consumer);return {resolvedType:'EASING',value:{type:'EASE_OUT_BACK',easingFunctionCubicBezier:{x1:.45,y1:1.45,x2:.8,y2:1}}}}}}}};
  const result=await resolveMotionVariables(f,consumer,raw);assert.equal(calls,1);assert.equal(result.resolved.keys[0].easing.type,'EASE_OUT_BACK');assert.deepEqual(raw,before);assert.equal(result.resolutions.length,2);
});
test('timing variables are seconds and per-node caches do not leak modes',async()=>{
  const f={variables:{async getVariableByIdAsync(){return {resolveForConsumer(n){return {resolvedType:'TIMING',value:n.mode==='slow'?1.2:.2}}}}}};
  const raw={timelineOffset:{type:'VARIABLE_ALIAS',id:'duration'}};
  assert.equal((await resolveMotionVariables(f,{mode:'slow'},raw)).resolved.timelineOffset,1.2);
  assert.equal((await resolveMotionVariables(f,{mode:'fast'},raw)).resolved.timelineOffset,.2);
});
test('alias cycles, missing variables and missing resolver fail closed',async()=>{
  const alias={type:'VARIABLE_ALIAS',id:'x'};
  await assert.rejects(resolveMotionVariables({},shape(),alias),/cannot resolve/);
  await assert.rejects(resolveMotionVariables({variables:{async getVariableByIdAsync(){return null}}},shape(),alias),/unavailable/);
  await assert.rejects(resolveMotionVariables({variables:{async getVariableByIdAsync(){return {resolveForConsumer(){return {value:alias}}}}}},shape(),alias),/Cyclic/);
});
test('capture retains raw aliases and emits explicit errors on resolution failure',async()=>{
  const s=shape();s.animations={OPACITY:binding([{keyframeOperation:'SET',keyframes:[key(0,0,{type:'VARIABLE_ALIAS',id:'missing'}),key(1,1)]}],1)};
  const out=await createCapture({mixed:Symbol()}).captureNode(s);assert.equal(out.rawMotion.animations.OPACITY.tracks[0].keyframes[0].easing.type,'VARIABLE_ALIAS');
  assert.ok(out.captureDiagnostics.some(x=>x.code==='MOTION_VARIABLE_UNRESOLVED'));assert.ok(errors(compileScene(out)).length);
});
test('generated standalone plugin executes without ES module dependencies',async()=>{
  const messages=[],selected=custom();const figma={mixed:Symbol(),showUI(){},currentPage:{selection:[selected]},ui:{postMessage:m=>messages.push(m)}};
  vm.runInNewContext(readFileSync(new URL('../code.js',import.meta.url),'utf8'),{figma,__html__:''});
  await figma.ui.onmessage({type:'export',mode:'motion'});
  const r=messages.find(m=>m.type==='result');assert.ok(r);assert.equal(r.blocked,false);assert.equal(r.document.version,2);
});

test('live Figma style snapshot fingerprint and compiled timing stay intact',()=>{
  const source=JSON.parse(readFileSync(new URL('../../fixtures/motion-2026/styles.source.json',import.meta.url),'utf8'));
  const text=JSON.stringify(source.snapshot);let h=2166136261;for(let i=0;i<text.length;i++)h=Math.imul(h^text.charCodeAt(i),16777619)>>>0;
  assert.equal(h.toString(16),source.provenance.fnv1a);
  const d=compileScene(source.snapshot);assert.equal(errors(d).length,0);
  const x=d.scenes[0].root.children[0].bindings.find(b=>b.field==='translationX');
  assert.deepEqual(x.tracks.map(t=>t.timelineOffset),[.2,1.5]);
  assert.deepEqual(x.tracks[0].keyframes.map(k=>k.time),[0,.8]);
});
