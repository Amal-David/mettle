import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync,mkdtempSync,writeFileSync,rmSync,symlinkSync,linkSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {makeCapture,compileCapture,findTransitions,summarize} from '../src/export.mjs';

const shape=(id,x=0)=>({id,name:id,type:'FRAME',width:60,height:40,visible:true,
  relativeTransform:[[1,0,x],[0,1,0]],absoluteTransform:[[1,0,x],[0,1,0]],
  fills:[{type:'SOLID',color:{r:1,g:0,b:0}}],fillGeometry:[{data:'M0 0H60V40H0Z',windingRule:'NONZERO'}],children:[]});
const connect=(node,destination,{duration=.2,delay=0,navigation='NAVIGATE'}={})=>{
  node.reactions=[{trigger:delay?{type:'AFTER_TIMEOUT',timeout:delay}:{type:'ON_CLICK'},actions:[{type:'NODE',navigation,
    destinationId:destination,transition:{type:'SMART_ANIMATE',duration,easing:{type:'LINEAR'}}}]}];
};
const clone=value=>structuredClone(value);

test('source connection chooses direction even when frames are laid out backwards',()=>{
  const a=shape('A',200),b=shape('B',0);connect(a,b.id);
  const record=makeCapture([b,a],{mode:'transition'});
  assert.deepEqual(record.nodes.map(node=>node.id),['A','B']);assert.equal(record.options.duration,.2);
});
test('ambiguous bidirectional and absent connections need an explicit start state',()=>{
  const a=shape('A'),b=shape('B');assert.throws(()=>makeCapture([a,b],{mode:'transition'}),/Choose the start frame/);
  connect(a,b.id);connect(b,a.id);
  assert.throws(()=>makeCapture([a,b],{mode:'transition'}),/Both frames/);
  assert.equal(makeCapture([a,b],{mode:'transition',startNodeID:b.id}).nodes[0].id,b.id);
  assert.throws(()=>makeCapture([a,b],{mode:'transition',startNodeID:'old'}),/no longer selected/);
});
test('verified main component identity resolves descendant CHANGE_TO but cannot masquerade as NAVIGATE',()=>{
  const a={...shape('A'),type:'INSTANCE',sourceComponent:{id:'variant:A'}},b={...shape('B'),type:'INSTANCE',sourceComponent:{id:'variant:B',key:'public-key'}};
  a.children=[shape('Target')];
  connect(a.children[0],'variant:B',{navigation:'CHANGE_TO'});
  assert.equal(findTransitions(a,b).length,1);assert.equal(makeCapture([b,a],{mode:'transition'}).transition.nodeID,'Target');
  a.children[0].reactions[0].actions[0].navigation='NAVIGATE';assert.equal(findTransitions(a,b).length,0);
});
test('nested CHANGE_TO uses the matching instance scope inside different wrapper roots',()=>{
  const a=shape('Screen A'),b=shape('Screen B');
  const from={...shape('instance:A'),name:'Power switch',type:'INSTANCE',sourceComponent:{id:'variant:A'},children:[shape('Target')]};
  const to={...shape('instance:B'),name:'Power switch',type:'INSTANCE',sourceComponent:{id:'variant:B'}};
  a.children=[from];b.children=[to];connect(from.children[0],'variant:B',{navigation:'CHANGE_TO'});
  assert.equal(findTransitions(a,b).length,1);
  assert.equal(makeCapture([b,a],{mode:'transition'}).transition.nodeID,'Target');
});
test('an unrelated destination instance cannot lend its component ID to another source scope',()=>{
  const a=shape('Screen A'),b=shape('Screen B');
  const from={...shape('instance:A'),name:'Power switch',type:'INSTANCE',sourceComponent:{id:'variant:A'},children:[shape('Target')]};
  a.children=[from];connect(from.children[0],'variant:B',{navigation:'CHANGE_TO'});
  b.children=[{...shape('instance:C'),name:'Power switch',type:'INSTANCE',sourceComponent:{id:'variant:C'}},
    {...shape('unrelated'),name:'Other switch',type:'INSTANCE',sourceComponent:{id:'variant:B'}}];
  assert.equal(findTransitions(a,b).length,0);
  assert.throws(()=>makeCapture([a,b],{mode:'transition'}),/No Smart Animate connection/);
});
test('ambiguous source or destination scope names and hidden reactions never select source timing',()=>{
  const a=shape('A'),b=shape('B');
  const from={...shape('instance:A'),name:'Switch',type:'INSTANCE',sourceComponent:{id:'variant:A'},children:[shape('Target')]};
  const to={...shape('instance:B'),name:'Switch',type:'INSTANCE',sourceComponent:{id:'variant:B'}};
  a.children=[from];b.children=[to,clone(to)];connect(from.children[0],'variant:B',{navigation:'CHANGE_TO'});
  assert.equal(findTransitions(a,b).length,0);
  b.children=[to];a.children.push(clone(from));assert.equal(findTransitions(a,b).length,0);
  a.children=[from];from.children[0].visible=false;assert.equal(findTransitions(a,b).length,0);
});
test('source timeout and easing survive capture and exact replay',()=>{
  const a=shape('A'),b=shape('B');a.children=[shape('Thumb',4)];b.children=[shape('Thumb',24)];connect(a,b.id,{duration:.4,delay:.125});
  const record=makeCapture([a,b],{mode:'transition'}),doc=compileCapture(record);
  const track=doc.scenes[0].root.children[0].bindings.find(binding=>binding.field==='translationX').tracks[0];
  assert.equal(doc.scenes[0].duration,.525);assert.equal(track.timelineOffset,.125);assert.equal(track.keyframes[0].time,0);
  assert.deepEqual(compileCapture(JSON.parse(JSON.stringify(record))),doc);
});
test('different timings on multiple source interactions cannot be guessed',()=>{
  const a=shape('A'),b=shape('B');connect(a,b.id);a.children=[shape('Nested')];connect(a.children[0],b.id,{duration:.8});
  assert.throws(()=>makeCapture([a,b],{mode:'transition'}),/different timing/);
});
test('manual A to B clips retain an explicit source warning',()=>{
  const a=shape('A'),b=shape('B');const record=makeCapture([a,b],{mode:'transition',startNodeID:a.id,duration:.7});
  assert.equal(record.options.duration,.7);assert.equal(record.transition,null);
  assert.ok(compileCapture(record).diagnostics.some(issue=>issue.code==='EXPLICIT_TRANSITION_TIMING'&&issue.severity==='warning'));
});
test('static library assets are never presented as imported motion',()=>{
  const doc=compileCapture(makeCapture([shape('Static')],{mode:'motion'}));
  assert.equal(summarize(doc).bindings,0);assert.ok(doc.diagnostics.some(issue=>issue.code==='NO_MOTION_TRACKS'));
  assert.ok(!compileCapture(makeCapture([shape('Static')],{mode:'static'})).diagnostics.some(issue=>issue.code==='NO_MOTION_TRACKS'));
});
test('capture preserves original source and applies an explicit viewport only to the compiled camera',()=>{
  const a=shape('A'),before=clone(a),viewport={x:0,y:-8,width:60,height:48};
  const record=makeCapture([a],{mode:'static',viewport}),doc=compileCapture(record);
  assert.deepEqual(a,before);assert.deepEqual(record.nodes[0],before);assert.equal(doc.scenes[0].height,48);assert.equal(doc.scenes[0].root.transform.ty,8);
});
test('generated plugin returns replayable raw source even when unsupported geometry blocks download',async()=>{
  const selected=shape('Effects');selected.effects=[{type:'DROP_SHADOW',visible:true}];
  Object.defineProperty(selected,'animations',{get(){throw new Error('gated Motion beta API');}});
  const messages=[],figma={mixed:Symbol(),root:{name:'Test'},showUI(){},currentPage:{selection:[selected]},ui:{postMessage:message=>messages.push(message)}};
  vm.runInNewContext(readFileSync(new URL('../code.js',import.meta.url),'utf8'),{figma,__html__:''});
  await figma.ui.onmessage({type:'export',mode:'static'});
  const result=messages.find(message=>message.type==='result');assert.ok(result);assert.equal(result.blocked,true);
  assert.equal(result.source.nodes[0].effects[0].type,'DROP_SHADOW');assert.ok(result.summary.errors>0);
  assert.equal(messages.at(-1).type,'ready');assert.equal(figma.currentPage.selection[0],selected);
});
test('replay CLI writes diagnostics but returns failure for blocked exports and protects its source file',()=>{
  const dir=mkdtempSync(join(tmpdir(),'mettle-replay-'));
  try {
    const input=join(dir,'source.json'),output=join(dir,'scene.json'),report=join(dir,'report.json');
    const node=shape('Bad');node.effects=[{type:'DROP_SHADOW',visible:true}];
    const original=JSON.stringify(makeCapture([node],{mode:'static'}));writeFileSync(input,original);
    const cli=new URL('../../scripts/compile_capture.mjs',import.meta.url);
    const result=spawnSync(process.execPath,[cli.pathname,input,'--output',output,'--report',report],{encoding:'utf8'});
    assert.equal(result.status,1,result.stderr);assert.ok(JSON.parse(readFileSync(report)).summary.errors>0);
    assert.match(JSON.parse(readFileSync(output)).provenance.sourceCaptureSHA256,/^[0-9a-f]{64}$/);
    const overwrite=spawnSync(process.execPath,[cli.pathname,input,'--output',input],{encoding:'utf8'});
    assert.equal(overwrite.status,2);assert.equal(readFileSync(input,'utf8'),original);
    for(const [name,link] of [['symbolic',symlinkSync],['hard',linkSync]]) {
      const alias=join(dir,name+'.json');link(input,alias);
      const attempt=spawnSync(process.execPath,[cli.pathname,input,'--output',alias],{encoding:'utf8'});
      assert.equal(attempt.status,2,attempt.stderr);assert.equal(readFileSync(input,'utf8'),original);
    }
  }finally{rmSync(dir,{recursive:true,force:true});}
});
