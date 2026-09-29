import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
import * as FM from '../src/compiler.mjs';
const host=readFileSync(new URL('../src/plugin.js',import.meta.url),'utf8');
const node=()=>({id:'host:rectangle',name:'Rectangle',type:'RECTANGLE',visible:true,
  width:40,height:20,relativeTransform:[[1,0,10],[0,1,30]],
  fills:[{type:'SOLID',color:{r:1,g:0,b:0}}],strokes:[],
  fillGeometry:[{data:'M0 0 H40 V20 H0 Z',windingRule:'NONZERO'}],children:[]});
function runtime(selected) {
  const messages=[];
  const figma={showUI(){},mixed:Symbol('mixed'),currentPage:{selection:[selected]},
    ui:{postMessage(message){messages.push(message);}}};
  const context=vm.createContext({figma,FM,__html__:'',selected});
  vm.runInContext(host,context);
  return {context,figma,messages};
}
const plain=x=>JSON.parse(JSON.stringify(x));
test('host adapter reads structured source geometry and transforms',async()=>{
  const source=node(),{context}=runtime(source);
  const snapshot=await vm.runInContext('captureNode(selected)',context);
  assert.deepEqual(plain(snapshot.fillGeometry),source.fillGeometry);
  assert.deepEqual(plain(snapshot.relativeTransform),source.relativeTransform);
});
test('missing Motion API is reported instead of invented animation',async()=>{
  const {context}=runtime(node());
  const snapshot=await vm.runInContext('captureNode(selected)',context);
  assert.ok(snapshot.captureDiagnostics.some(d=>d.code==='MOTION_API_UNAVAILABLE'));
  assert.deepEqual(plain(snapshot.animations),{});
});
test('failing source getter is not silently interpreted as static content',async()=>{
  const source=node();Object.defineProperty(source,'animations',{get(){throw new Error('Unavailable in this host');}});
  const {context}=runtime(source);
  await assert.rejects(vm.runInContext('captureNode(selected)',context),/Cannot read source property animations/);
});
test('host export failure reports an error, restores selection, and becomes ready',async()=>{
  const source=node();Object.defineProperty(source,'effects',{get(){throw new Error('Read failed');}});
  const {figma,messages}=runtime(source);
  await figma.ui.onmessage({type:'export',mode:'motion'});
  assert.ok(messages.some(m=>m.type==='failure'&&m.message.includes('effects')));
  assert.equal(messages.at(-1).type,'ready');
  assert.equal(figma.currentPage.selection[0],source);
});
