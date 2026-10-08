import test from 'node:test';
import assert from 'node:assert/strict';
import {createCapture} from '../src/capture.mjs';

const shape=(id='a')=>({id,name:id,type:'RECTANGLE',width:40,height:20,visible:true,
  relativeTransform:[[1,0,10],[0,1,20]],fills:[],strokes:[],fillGeometry:[],children:[]});
const reaction={trigger:{type:'AFTER_TIMEOUT',timeout:.1},actions:[{type:'NODE',navigation:'CHANGE_TO',destinationId:'b',transition:{type:'SMART_ANIMATE',duration:.4,easing:{type:'LINEAR'}}}]};

test('explicit endpoint capture avoids gated Motion getters at every depth and keeps source reactions',async()=>{
  const root=shape(),child=shape('child');root.children=[child];child.reactions=[reaction];let reads=0;
  for(const node of [root,child]) for(const property of ['animations','manualKeyframeTracks','animationStyles','timelines']) {
    Object.defineProperty(node,property,{get(){reads++;throw new Error(`"${property}" is not a supported API`);}});
  }
  const snapshot=await createCapture({mixed:Symbol()}).captureNode(root,{includeMotion:false});
  assert.equal(reads,0);
  assert.equal(snapshot.motionCapture,'not-requested');
  assert.equal(snapshot.children[0].motionCapture,'not-requested');
  assert.deepEqual(snapshot.children[0].reactions,[reaction]);
  assert.deepEqual(snapshot.children[0].relativeTransform,child.relativeTransform);
  assert.deepEqual(snapshot.captureDiagnostics,[]);
});

test('motion capture still fails closed when a present beta getter throws',async()=>{
  const root=shape();Object.defineProperty(root,'animations',{get(){throw new Error('"animations" is not a supported API');}});
  await assert.rejects(createCapture({mixed:Symbol()}).captureNode(root),/Cannot read source property animations/);
});

test('static capture still exposes geometry read failures',async()=>{
  const root=shape();Object.defineProperty(root,'fillGeometry',{get(){throw new Error('geometry unavailable');}});
  await assert.rejects(createCapture({mixed:Symbol()}).captureNode(root,{includeMotion:false}),/Cannot read source property fillGeometry/);
});

test('static endpoint capture neither reads nor resolves unrequested motion variables',async()=>{
  const root=shape();root.animations={OPACITY:{type:'VARIABLE_ALIAS',id:'bad-token'}};
  const snapshot=await createCapture({mixed:Symbol(),variables:{getVariableByIdAsync(){throw new Error('must not resolve');}}}).captureNode(root,{includeMotion:false});
  assert.deepEqual(snapshot.rawMotion.animations,{});
  assert.deepEqual(snapshot.motionVariableResolutions,[]);
  assert.deepEqual(snapshot.captureDiagnostics,[]);
});

test('instance capture records the asynchronous main variant identity without cloning its node graph',async()=>{
  const root=shape('instance');root.type='INSTANCE';let calls=0;
  const component={id:'variant:off',name:'State=Off',key:'published-component-key'};component.parent={children:[component]};
  root.getMainComponentAsync=async()=>{calls++;return component;};
  Object.defineProperty(root,'mainComponent',{get(){throw new Error('Synchronous getter is write-only in dynamic-page');}});
  const snapshot=await createCapture({mixed:Symbol()}).captureNode(root,{includeMotion:false});
  assert.equal(calls,1);
  assert.deepEqual(snapshot.sourceComponent,{id:'variant:off',name:'State=Off',key:'published-component-key'});
  assert.deepEqual(snapshot.captureDiagnostics,[]);
  assert.doesNotThrow(()=>JSON.stringify(snapshot));
});

test('unavailable source variant identity is explicit while source geometry remains exportable',async()=>{
  const root=shape('instance');root.type='INSTANCE';root.getMainComponentAsync=async()=>null;
  const snapshot=await createCapture({mixed:Symbol()}).captureNode(root,{includeMotion:false});
  assert.equal(snapshot.sourceComponent,undefined);
  assert.deepEqual(snapshot.relativeTransform,root.relativeTransform);
  assert.ok(snapshot.captureDiagnostics.some(d=>d.severity==='warning'&&d.code==='INSTANCE_COMPONENT_UNAVAILABLE'));
});

test('capture retains selected-root bounds as source evidence without deriving a camera from descendants',async()=>{
  const root=shape(),child=shape('child');root.children=[child];
  root.absoluteTransform=[[1,0,80],[0,1,400]];
  root.absoluteBoundingBox={x:80,y:400,width:40,height:20};
  root.absoluteRenderBounds={x:80,y:392,width:60,height:48};
  Object.defineProperty(child,'absoluteRenderBounds',{get(){throw new Error('No descendant bounds lookup needed');}});
  const snapshot=await createCapture({mixed:Symbol()}).captureNode(root,{includeMotion:false});
  assert.deepEqual(snapshot.absoluteTransform,root.absoluteTransform);
  assert.deepEqual(snapshot.absoluteRenderBounds,root.absoluteRenderBounds);
  assert.deepEqual(snapshot.absoluteBoundingBox,root.absoluteBoundingBox);
  assert.equal(snapshot.children[0].absoluteRenderBounds,undefined);
});
