import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
import * as FME from '../src/export.mjs';
import {createCapture} from '../src/capture.mjs';

const fixtureRoot=new URL('../../fixtures/community/material3/',import.meta.url);
const source=slug=>JSON.parse(readFileSync(new URL(`${slug}.snapshot.json`,fixtureRoot),'utf8'));
const png=slug=>readFileSync(new URL(`reference/${slug}.png`,fixtureRoot));
const expectedSettings={format:'PNG',constraint:{type:'SCALE',value:1},contentsOnly:true,useAbsoluteBounds:false};
const scene=(id,x=80)=>({id,name:id,type:'FRAME',width:52,height:32,visible:true,
  relativeTransform:[[1,0,x],[0,1,400]],absoluteTransform:[[1,0,x],[0,1,400]],
  absoluteRenderBounds:{x,y:392,width:60,height:48},
  fills:[{type:'SOLID',color:{r:1,g:0,b:0}}],fillGeometry:[{data:'M0 0H52V32H0Z',windingRule:'NONZERO'}],children:[]});
function host(selection) {
  const messages=[],listeners={},figma={mixed:Symbol(),root:{name:'References'},currentPage:{selection},
    showUI(){},on(event,callback){listeners[event]=callback;},ui:{postMessage(message){messages.push(message);}}};
  vm.runInNewContext(readFileSync(new URL('../src/plugin.js',import.meta.url),'utf8'),{figma,__html__:'',FMC:{createCapture},FME});
  return {figma,messages,listeners};
}

test('Figma PNG header preserves independently observed overflow and fractional export origin',()=>{
  assert.deepEqual(FME.referenceViewport(source('switch-enabled'),png('switch-enabled')),{x:0,y:-8,width:60,height:48});
  assert.deepEqual(FME.referenceViewport(source('circular-wave-step-1'),png('circular-wave-step-1')),
    {x:-0.08150482177734375,y:-0.0849151611328125,width:49,height:49});
  assert.deepEqual(FME.referenceViewport(source('linear-flat-step-1'),png('linear-flat-step-1')),
    {x:0,y:0,width:404,height:12});
});

test('reference framing rejects transformed roots, missing bounds and invalid PNG headers',()=>{
  for(const transform of [[[0,-1,80],[1,0,400]],[[2,0,80],[0,2,400]],[[1,.01,80],[0,1,400]]]) {
    assert.throws(()=>FME.referenceViewport({...scene('A'),absoluteTransform:transform},png('switch-enabled')),/unrotated, unscaled/);
  }
  assert.throws(()=>FME.referenceViewport({...scene('A'),absoluteRenderBounds:null},png('switch-enabled')),/visible render bounds/);
  assert.throws(()=>FME.referenceViewport(scene('A'),new Uint8Array(33)),/valid PNG/);
  const header=Buffer.from(png('switch-enabled').subarray(0,33));header.writeUInt32BE(0,16);
  assert.throws(()=>FME.referenceViewport(scene('A'),header),/dimensions/);
});

test('nominal camera warns about real overflow while ignoring captured floating point noise',()=>{
  for(const slug of ['switch-enabled','circular-wave-step-1']) {
    const snapshot=source(slug);
    assert.ok(FME.makeCapture([snapshot],{mode:'static'}).notes.some(note=>note.code==='CONTENT_OUTSIDE_CANVAS'));
    const viewport=FME.referenceViewport(snapshot,png(slug));
    assert.ok(!FME.makeCapture([snapshot],{mode:'static',viewport}).notes.some(note=>note.code==='CONTENT_OUTSIDE_CANVAS'));
  }
  assert.ok(!FME.makeCapture([source('linear-flat-step-1')],{mode:'static'}).notes.some(note=>note.code==='CONTENT_OUTSIDE_CANVAS'));
});

test('live host returns byte-preserved independent references and a replayable shared viewport',async()=>{
  const a=scene('A'),b=scene('B',200),original=png('switch-enabled'),calls=[];
  a.reactions=[{trigger:{type:'ON_CLICK'},actions:[{type:'NODE',navigation:'NAVIGATE',destinationId:b.id,
    transition:{type:'SMART_ANIMATE',duration:.2,easing:{type:'LINEAR'}}}]}];
  for(const node of [a,b]) node.exportAsync=async settings=>{calls.push(structuredClone(settings));return new Uint8Array(original);};
  const {figma,messages}=host([a,b]);
  await figma.ui.onmessage({type:'export',mode:'transition',referenceBounds:true});
  const result=messages.find(message=>message.type==='result');assert.ok(result,messages.find(message=>message.type==='failure')?.message);
  assert.equal(result.blocked,false);assert.deepEqual(calls,[expectedSettings,expectedSettings]);
  assert.deepEqual(result.source.options.viewport,{x:0,y:-8,width:60,height:48});
  assert.equal(result.source.nodes[0].width,52);assert.equal(result.source.nodes[0].height,32);
  assert.equal(result.document.scenes[0].width,60);assert.equal(result.document.scenes[0].height,48);
  assert.equal(result.document.scenes[0].root.transform.ty,8);
  assert.equal(result.source.provenance.referenceExports.length,2);
  assert.deepEqual(result.source.provenance.referenceExports[0].exportSettings,expectedSettings);
  assert.ok(!('bytes' in result.source.provenance.referenceExports[0]));
  assert.deepEqual(Buffer.from(result.referenceFrames[0].bytes),original);
  assert.deepEqual(FME.compileCapture(JSON.parse(JSON.stringify(result.source))),result.document);
  assert.equal(messages.at(-1).type,'ready');
});

test('reference capture rejects differently framed states, Motion mode and oversized transfers',async()=>{
  const a=scene('A'),b=scene('B',200);b.absoluteRenderBounds.y=391;
  for(const node of [a,b]) node.exportAsync=async()=>png('switch-enabled');
  const mismatch=host([a,b]);
  await mismatch.figma.ui.onmessage({type:'export',mode:'transition',startNodeID:a.id,referenceBounds:true});
  assert.match(mismatch.messages.find(message=>message.type==='failure').message,/different local viewports/);
  assert.ok(!mismatch.messages.some(message=>message.type==='result'));
  const motion=scene('Motion');Object.defineProperty(motion,'animations',{get(){throw new Error('Motion getter must not run');}});
  const animated=host([motion]);
  await animated.figma.ui.onmessage({type:'export',mode:'motion',referenceBounds:true});
  assert.match(animated.messages.find(message=>message.type==='failure').message,/single PNG cannot establish/);
  const large=scene('Large');large.exportAsync=async()=>({length:32*1024*1024+1});
  const oversized=host([large]);
  await oversized.figma.ui.onmessage({type:'export',mode:'static',referenceBounds:true});
  assert.match(oversized.messages.find(message=>message.type==='failure').message,/32 MiB/);
});

test('ordinary export avoids PNG APIs and deliberate diagnostic reveal has a distinct selection reason',async()=>{
  const a=scene('A'),target=scene('Issue');a.exportAsync=async()=>{throw new Error('Reference export was not requested');};
  const {figma,messages,listeners}=host([a]);
  await figma.ui.onmessage({type:'export',mode:'static'});
  const result=messages.find(message=>message.type==='result');assert.ok(result);
  assert.equal(result.referenceFrames.length,0);
  assert.ok(result.document.diagnostics.some(issue=>issue.code==='CONTENT_OUTSIDE_CANVAS'));
  figma.getNodeByIdAsync=async()=>target;figma.viewport={scrollAndZoomIntoView(){}};
  await figma.ui.onmessage({type:'reveal-node',nodeID:target.id});
  assert.equal(messages.at(-2).reason,'reveal');assert.equal(figma.currentPage.selection[0],target);
  listeners.selectionchange({type:'selectionchange'});
  assert.equal(messages.at(-1).reason,'selection');
});
