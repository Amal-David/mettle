/* Figma host UI adapter. FM/FMC are injected by build.mjs. */
figma.showUI(__html__, { width: 440, height: 590, themeColors: true });
let busy=false;
const capture=FMC.createCapture(figma);
const captureNode=capture.captureNode;
function transitionFrom(a,b) {
  for(const reaction of a.reactions??[]) for(const action of reaction.actions??(reaction.action?[reaction.action]:[])) {
    if(action.destinationId===b.id && action.transition?.type==='SMART_ANIMATE') return action.transition;
  }
  return null;
}
async function createTestFrames() {
  const a=figma.createFrame();a.name='Metal test — A';a.resize(480,320);a.fills=[{type:'SOLID',color:{r:.05,g:.07,b:.12}}];a.cornerRadius=24;
  const shape=figma.createEllipse();a.appendChild(shape);shape.name='Orb';shape.resize(120,120);shape.x=40;shape.y=100;
  shape.fills=[{type:'GRADIENT_LINEAR',gradientTransform:[[1,0,0],[0,1,0]],gradientStops:[{position:0,color:{r:.2,g:.9,b:.8,a:1}},{position:1,color:{r:.6,g:.35,b:1,a:1}}]}];
  const indicator=figma.createRectangle();a.appendChild(indicator);indicator.name='Indicator';indicator.resize(100,12);indicator.x=40;indicator.y=260;indicator.cornerRadius=6;
  indicator.fills=[{type:'SOLID',color:{r:1,g:.75,b:.35}}];
  const b=a.clone();b.name='Metal test — B';b.x=a.x+540;b.children[0].x=300;b.children[1].x=300;b.children[1].opacity=.35;
  await a.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId:b.id,navigation:'NAVIGATE',transition:{type:'SMART_ANIMATE',duration:.8,easing:{type:'EASE_IN_AND_OUT'}},preserveScrollPosition:false}]}]);
  figma.currentPage.selection=[a,b];figma.viewport.scrollAndZoomIntoView([a,b]);
  figma.ui.postMessage({type:'notice',text:'Created A/B test frames. Choose two-frame export. Timing is read from the prototype connection.'});
}
figma.ui.onmessage=async message=>{
  if(busy) return;
  busy=true;
  const originalSelection=Array.from(figma.currentPage.selection);
  try {
    if(message.type==='create-test') {await createTestFrames();return;}
    if(message.type!=='export') return;
    const selection=Array.from(figma.currentPage.selection);
    const expected=message.mode==='transition'?2:1;
    if(selection.length!==expected) throw new Error(`Select exactly ${expected} frame/component${expected===2?'s':''}.`);
    if(selection.some(n=>!('width' in n)||!('height' in n))) throw new Error('Selection must have a width and height.');
    // Use canvas left-to-right order, not unstable selection order, for A→B.
    if(expected===2) selection.sort((a,b)=>a.absoluteTransform[0][2]-b.absoluteTransform[0][2]);
    capture.reset();
    const snapshots=[];for(const node of selection) snapshots.push(await captureNode(node));
    const options={loop:message.loop,origin:message.origin};
    let document;
    if(expected===2) {
      const sourceTransition=transitionFrom(snapshots[0],snapshots[1]);
      document=FM.compileTransition(snapshots[0],snapshots[1],{...options,duration:sourceTransition?.duration??message.duration,easing:sourceTransition?.easing});
      if(!sourceTransition) document.diagnostics.push({severity:'info',code:'EXPLICIT_TRANSITION_TIMING',nodeID:snapshots[0].id,message:'No matching Smart Animate connection was found. Duration comes from the export panel.'});
    } else document=FM.compileScene(snapshots[0],options);
    const blocked=document.diagnostics.some(d=>d.severity==='error')&&!message.allowPartial;
    const filename=(selection[0].name.replace(/[^a-z0-9_-]+/gi,'-').slice(0,64)||'scene')+'.figmetal.json';
    figma.ui.postMessage({type:'result',document,filename,blocked});
  } catch(error) { figma.ui.postMessage({type:'failure',message:error.message??String(error)}); }
  finally {
    if(message.type!=='create-test') figma.currentPage.selection=originalSelection.filter(n=>!n.removed);
    busy=false;figma.ui.postMessage({type:'ready'});
  }
};
