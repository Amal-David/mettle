import test from 'node:test';
import assert from 'node:assert/strict';
import {compileScene,compileTransition,affine,inverse,multiply,easing} from '../src/compiler.mjs';
const fill={type:'SOLID',color:{r:1,g:0,b:0}};
const frame=(id='a')=>({id,name:'Frame',type:'FRAME',width:100,height:100,relativeTransform:[[1,0,200],[0,1,300]],opacity:1,
  fillGeometry:[{data:'M0 0 H100 V100 H0 Z',windingRule:'NONZERO'}],fills:[fill],children:[]});
const binding=(values=[0,100],times=[0,1],type='FLOAT')=>({baseValue:{type,value:values[0]},timelineDuration:1,
  tracks:[{id:'track',keyframeOperation:'SET',keyframes:values.map((v,i)=>({id:String(i),timelinePosition:times[i],value:{type,value:v},easing:{type:'LINEAR'}}))}]});
const errors=d=>d.diagnostics.filter(x=>x.severity==='error');
const clone=x=>structuredClone(x);
test('actual source geometry is preserved, root canvas translation removed',()=>{
  const s=frame();const d=compileScene(s);assert.equal(errors(d).length,0);assert.deepEqual(d.scenes[0].root.draws[0].paths,s.fillGeometry);assert.equal(d.scenes[0].root.transform.tx,0);
});
test('matrix ordering and inverse',()=>{const m=affine([[2,0,10],[0,3,20]]);const i=multiply(inverse(m),m);assert.equal(i.a,1);assert.ok(Math.abs(i.ty)<1e-12);assert.throws(()=>inverse({a:0,b:0,c:0,d:0,tx:0,ty:0}));});
test('child translation retained',()=>{const s=frame();const c=frame('c');c.relativeTransform=[[1,0,10],[0,1,20]];s.children=[c];assert.equal(compileScene(s).scenes[0].root.children[0].transform.tx,10);});
test('fill order is bottom-to-top while source paint index survives',()=>{const s=frame();s.fills=[fill,{type:'SOLID',color:{r:0,g:0,b:1}}];const draws=compileScene(s).scenes[0].root.draws;assert.equal(draws[0].paintIndex,1);assert.equal(draws[1].paintIndex,0);});
test('gradient source transform and stops preserved',()=>{const s=frame();s.fills=[{type:'GRADIENT_LINEAR',gradientTransform:[[2,0,-.5],[0,1,0]],gradientStops:[{position:0,color:{r:1,g:0,b:0,a:1}},{position:1,color:{r:0,g:0,b:1,a:1}}]}];const d=compileScene(s);assert.equal(errors(d).length,0);assert.equal(d.scenes[0].root.draws[0].paint.transform.tx,-.5);});
test('no automatic raster fallback for images, shaders, blur or masks',()=>{const s=frame();s.fills=[{type:'IMAGE'}];s.effects=[{type:'LAYER_BLUR',visible:true}];s.isMask=true;const codes=errors(compileScene(s)).map(x=>x.code);for(const code of ['UNSUPPORTED_PAINT','EFFECTS','SIBLING_MASK'])assert.ok(codes.includes(code));});
test('hidden unsupported child does not block export',()=>{const s=frame();s.children=[{...frame('hidden'),visible:false,fills:[{type:'VIDEO'}]}];assert.equal(errors(compileScene(s)).length,0);});
test('resolved motion wins over manual fallback and uses seconds',()=>{const s=frame();s.animations={TRANSLATION_X:binding()};s.manualKeyframeTracks={TRANSLATION_X:{baseValue:{type:'FLOAT',value:0},keyframes:[]}};const d=compileScene(s);assert.equal(errors(d).length,0);assert.equal(d.scenes[0].duration,1);assert.equal(d.scenes[0].root.bindings[0].tracks[0].keyframes[1].time,1);});
test('vector translations split into independent scalar tracks',()=>{const s=frame();s.animations={TRANSLATION_XY:binding([{x:1,y:2},{x:3,y:4}],[0,2],'VECTOR')};const b=compileScene(s).scenes[0].root.bindings;assert.equal(b.length,2);assert.deepEqual(b[1].tracks[0].keyframes[1].value,[4]);});
test('source SET/OFFSET/SCALE operations not merged incorrectly',()=>{const s=frame();const b=binding();b.tracks.push({...b.tracks[0],keyframeOperation:'OFFSET'},{...b.tracks[0],keyframeOperation:'SCALE'});s.animations={OPACITY:b};assert.deepEqual(compileScene(s).scenes[0].root.bindings[0].tracks.map(t=>t.operation),['set','offset','scale']);});
test('HOLD is retained',()=>{assert.deepEqual(easing({type:'HOLD'}),{kind:'hold',control:[]});});
test('custom cubic values and overshoot retained',()=>{assert.deepEqual(easing({type:'CUSTOM_CUBIC_BEZIER',easingFunctionCubicBezier:{x1:.2,y1:1.6,x2:.7,y2:1.2}}).control,[.2,1.6,.7,1.2]);});
test('spring is not silently converted to a cubic',()=>{const s=frame();const b=binding();b.tracks[0].keyframes[0].easing={type:'CUSTOM_SPRING',easingFunctionSpring:{bounce:.4}};s.animations={TRANSLATION_X:b};const d=compileScene(s);assert.ok(errors(d).some(x=>x.code==='MOTION_BINDING'));assert.equal(d.sourceMotion.a.animations.TRANSLATION_X.tracks[0].keyframes[0].easing.type,'CUSTOM_SPRING');});
test('unsupported motion remains visible in report and source payload',()=>{const s=frame();s.animations={WIDTH:binding()};const d=compileScene(s);assert.equal(errors(d)[0].code,'UNSUPPORTED_MOTION_FIELD');assert.ok(d.sourceMotion.a.animations.WIDTH);});
test('multiple unrelated timelines block export',()=>{const s=frame();s.timelines=[{id:'a',duration:2},{id:'b',duration:3}];assert.ok(errors(compileScene(s)).some(x=>x.code==='MULTIPLE_TIMELINES'));});
test('manual fallback is explicit',()=>{const s=frame();s.manualKeyframeTracks={OPACITY:{baseValue:{type:'FLOAT',value:0},keyframes:[{timelinePosition:0,value:{type:'FLOAT',value:0},easing:{type:'LINEAR'}}]}};const d=compileScene(s);assert.equal(d.scenes[0].root.bindings.length,1);assert.ok(d.diagnostics.some(x=>x.code==='MANUAL_TRACK_FALLBACK'));});
test('two-frame source hierarchy matching and translation',()=>{const a=frame();a.children=[{...frame('child-a'),name:'Orb'}];const b=clone(a);b.id='b';b.children[0].id='child-b';b.children[0].relativeTransform[0][2]+=50;const d=compileTransition(a,b,{duration:.8});assert.equal(errors(d).length,0);const track=d.scenes[0].root.children[0].bindings[0];assert.equal(track.field,'translationX');assert.deepEqual(track.tracks[0].keyframes[1].value,[250]);});
test('two-frame solid alpha uses effective paint opacity once',()=>{const a=frame(),b=clone(a);b.fills[0].opacity=.5;const d=compileTransition(a,b);assert.equal(errors(d).length,0);assert.deepEqual(d.scenes[0].root.bindings[0].tracks[0].keyframes[1].value,[1,0,0,.5]);});
test('ambiguous sibling names are rejected rather than guessed',()=>{const a=frame();a.children=[frame('c'),frame('d')];assert.ok(errors(compileTransition(a,clone(a))).some(x=>x.code==='AMBIGUOUS_LAYER_NAMES'));});
test('path morph or resize cannot silently become a scale',()=>{const a=frame(),b=clone(a);b.width=200;b.fillGeometry[0].data='M0 0 H200 V100 H0 Z';const d=compileTransition(a,b);assert.ok(errors(d).some(x=>x.code==='TRANSITION_DRAW_GEOMETRY'));});
test('node count bound is enforced',()=>{const a=frame();a.children=Array.from({length:5001},(_,i)=>frame(`n${i}`));assert.throws(()=>compileScene(a),/budget/);});
