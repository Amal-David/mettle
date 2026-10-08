import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
import {createCapture} from '../src/capture.mjs';
import * as FME from '../src/export.mjs';

const shape=id=>({id,name:id,type:'RECTANGLE',visible:true,width:20,height:20,
  relativeTransform:[[1,0,0],[0,1,0]],fills:[{type:'SOLID',color:{r:1,g:0,b:0}}],
  fillGeometry:[{data:'M0 0H20V20H0Z',windingRule:'NONZERO'}],children:[]});

function setup({outlines=false,outlineFails=false}={}) {
  const captured={...shape('captured'),type:'INSTANCE'},later=shape('user-selected');
  let begin,release,selection=[captured],serial=0;
  const started=new Promise(resolve=>{begin=resolve;}),wait=new Promise(resolve=>{release=resolve;});
  captured.getMainComponentAsync=async()=>{begin();await wait;return {id:'main',name:'Main',key:'published-key'};};
  const listeners={},messages=[],temporary=[];
  const page={get selection(){return selection;},set selection(value){selection=value;listeners.selectionchange?.();}};
  function remove(node) {
    node.removed=true;
    for(const child of node.children??[]) remove(child);
    page.selection=selection.filter(node=>!node.removed);
  }
  function temporaryNode() {
    const node=shape(`temporary:${++serial}`);node.remove=()=>remove(node);temporary.push(node);
    // Exercise hosts that notify immediately, before the factory returns its
    // new node to the capture helper for registration.
    page.selection=[node];return node;
  }
  const figma={mixed:Symbol(),root:{name:'Race test'},currentPage:page,showUI(){},
    on(event,callback){listeners[event]=callback;},ui:{postMessage(message){messages.push(message);}},
    createFrame(){
      const stage=temporaryNode();
      stage.appendChild=node=>{stage.children.push(node);node.parent=stage;};
      return stage;
    }};
  if(outlines) {
    captured.strokes=[{type:'SOLID',color:{r:1,g:0,b:0}}];
    captured.outlineStroke=()=>{throw new Error('Only a temporary copy may be outlined');};
    captured.clone=()=>{
      const copy=temporaryNode();
      copy.outlineStroke=()=>{
        if(outlineFails) throw new Error('Source stroke outline unavailable');
        const result=temporaryNode();copy.parent.appendChild(result);return result;
      };
      return copy;
    };
  }
  let capture;
  const FMC={createCapture(api){capture=createCapture(api);return capture;}};
  vm.runInNewContext(readFileSync(new URL('../src/plugin.js',import.meta.url),'utf8'),{figma,__html__:'',FMC,FME});
  return {figma,messages,captured,later,temporary,started,release,get capture(){return capture;}};
}

test('a user selection made during asynchronous capture survives and invalidates the earlier selection context',async()=>{
  const run=setup(),pending=run.figma.ui.onmessage({type:'export',mode:'static'});
  await run.started;run.figma.currentPage.selection=[run.later];run.release();await pending;
  assert.equal(run.figma.currentPage.selection[0],run.later);
  const result=run.messages.find(message=>message.type==='result');assert.equal(result.source.nodes[0].id,run.captured.id);
  const final=run.messages.filter(message=>message.type==='selection').at(-1);
  assert.equal(final.reason,'selection');assert.equal(final.nodes[0].id,run.later.id);
  assert.ok(run.messages.indexOf(final)>run.messages.indexOf(result));
  assert.equal(run.messages.at(-1).type,'ready');
});

test('deselecting everything while a capture read is pending never reselects the old source',async()=>{
  const run=setup(),pending=run.figma.ui.onmessage({type:'export',mode:'static'});
  await run.started;run.figma.currentPage.selection=[];run.release();await pending;
  assert.equal(run.figma.currentPage.selection.length,0);
  assert.equal(run.messages.filter(message=>message.type==='selection').at(-1).nodes.length,0);
});

test('temporary outline selections restore the latest real selection and remove every temporary node',async()=>{
  for(const selection of ['original','later','empty']) {
    const run=setup({outlines:true}),pending=run.figma.ui.onmessage({type:'export',mode:'static'});
    await run.started;
    const expected=selection==='empty'?[]:[selection==='original'?run.captured:run.later];
    run.figma.currentPage.selection=expected;run.release();await pending;
    assert.deepEqual(run.figma.currentPage.selection.map(node=>node.id),expected.map(node=>node.id),selection);
    assert.equal(run.temporary.length,3);
    assert.ok(run.temporary.every(node=>node.removed&&run.capture.ownsTemporaryNode(node.id)));
    assert.ok(!run.captured.removed&&!run.later.removed);
    assert.deepEqual(new Set(run.capture.audit.created),new Set(run.capture.audit.removed));
    assert.equal(run.messages.find(message=>message.type==='result').blocked,false);
  }
});

test('failed temporary outlining still restores the later user selection and leaves a blocked source report',async()=>{
  const run=setup({outlines:true,outlineFails:true}),pending=run.figma.ui.onmessage({type:'export',mode:'static'});
  await run.started;run.figma.currentPage.selection=[run.later];run.release();await pending;
  assert.equal(run.figma.currentPage.selection[0],run.later);
  assert.ok(run.temporary.every(node=>node.removed));
  const result=run.messages.find(message=>message.type==='result');
  assert.equal(result.blocked,true);
  assert.ok(result.document.diagnostics.some(issue=>issue.code==='STROKE_OUTLINE_FAILED'));
  assert.equal(run.messages.filter(message=>message.type==='selection').at(-1).nodes[0].id,run.later.id);
});
