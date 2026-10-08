import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {compileScene,compileTransition} from '../src/compiler.mjs';

const source=step=>JSON.parse(readFileSync(new URL(`../../fixtures/community/material3/loading-step-${step}.snapshot.json`,import.meta.url),'utf8'));
const errors=document=>document.diagnostics.filter(issue=>issue.severity==='error');

test('genuine Material 3 loading endpoints retain exact vector paths and contain no invented keyframes',()=>{
  for(const step of [1,2,3,4,5,6,7]) {
    const snapshot=source(step),document=compileScene(snapshot,{includeMotion:false});
    assert.deepEqual(errors(document),[]);
    assert.equal(document.scenes[0].width,48);assert.equal(document.scenes[0].height,48);
    assert.equal(document.scenes[0].duration,0);
    const shape=document.scenes[0].root.children[0].children[0];
    assert.deepEqual(shape.draws[0].paths,snapshot.children[0].children[0].fillGeometry);
    assert.deepEqual(shape.bindings,[]);
  }
});

test('real Material morph/clip changes cannot produce a successful Smart Animate export',()=>{
  const from=source(1),to=source(2),reaction=from.reactions[0],transition=reaction.actions[0].transition;
  const document=compileTransition(from,to,{duration:transition.duration,easing:transition.easing,delay:reaction.trigger.timeout});
  assert.equal(document.scenes[0].duration,transition.duration+reaction.trigger.timeout);
  const codes=errors(document).map(issue=>issue.code);
  assert.ok(codes.includes('TRANSITION_GEOMETRY'));
  assert.ok(codes.includes('TRANSITION_DRAW_GEOMETRY'));
  assert.deepEqual(document.sourceMotion.from[from.id].reactions,from.reactions);
});

test('genuine Material Switch hover compiles its appearing state fill and thumb color from exact source timing',()=>{
  const read=name=>JSON.parse(readFileSync(new URL(`../../fixtures/community/material3/switch-${name}.snapshot.json`,import.meta.url),'utf8'));
  const from=read('enabled'),to=read('hovered');
  const flatten=node=>[node,...(node.children??[]).flatMap(flatten)];
  const hotspot=flatten(from).find(node=>node.reactions?.length),reaction=hotspot.reactions[0],transition=reaction.actions[0].transition;
  assert.equal(from.reactions.length,0);
  assert.equal(reaction.trigger.type,'ON_HOVER');
  assert.equal(reaction.actions[0].destinationId,to.sourceComponent.id);
  assert.notEqual(reaction.actions[0].destinationId,to.id);
  const document=compileTransition(from,to,{duration:transition.duration,easing:transition.easing});
  assert.deepEqual(errors(document),[]);
  assert.equal(document.scenes[0].duration,transition.duration);
  const nodes=flatten(document.scenes[0].root),state=nodes.find(node=>node.name==='State-layer'),thumb=nodes.find(node=>node.name==='Handle shape');
  assert.equal(state.bindings.length,1);assert.equal(thumb.bindings.length,1);
  assert.equal(state.bindings[0].base[3],0);
  assert.equal(state.bindings[0].tracks[0].keyframes.at(-1).value[3],.07999999821186066);
  assert.deepEqual(state.bindings[0].tracks[0].keyframes[0].easing.control,[.20000000298023224,0,0,1]);
  assert.deepEqual(thumb.bindings[0].tracks[0].keyframes.at(-1).value,[.9176470637321472,.8666666746139526,1,1]);
});

test('Material Switch camera uses its verified overflow bounds instead of clipping the hover state',()=>{
  const bounds=JSON.parse(readFileSync(new URL('../../fixtures/community/material3/source-bounds.json',import.meta.url),'utf8')).bounds;
  for(const slug of ['switch-enabled','switch-hovered']) {
    const snapshot=JSON.parse(readFileSync(new URL(`../../fixtures/community/material3/${slug}.snapshot.json`,import.meta.url),'utf8'));
    const viewport=bounds.find(entry=>entry.slug===slug).localRenderBounds;
    assert.deepEqual(viewport,{x:0,y:-8,width:60,height:48});
    const scene=compileScene(snapshot,{includeMotion:false,viewport}).scenes[0];
    assert.equal(scene.width,60);assert.equal(scene.height,48);assert.equal(scene.root.transform.ty,8);
    assert.deepEqual(scene.root.size,{x:52,y:32});assert.deepEqual(scene.root.clip,[]);
  }
});
