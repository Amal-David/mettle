/* Figma host adapter. FM is injected by build.mjs. No network access or third-party code. */
figma.showUI(__html__, { width: 440, height: 590, themeColors: true });
let busy = false;
let captureCount = 0;
const cloneJSON = value => value == null ? value : JSON.parse(JSON.stringify(value));
const read = (node, key, fallback) => {
  try { const value=node[key]; return value===undefined?fallback:cloneJSON(value); }
  catch(error) { throw new Error(`Cannot read source property ${key} on ${node.id}: ${error.message??error}`); }
};
function capturePaints(node,key) {
  if(!(key in node)) return [];
  return node[key]===figma.mixed?'MIXED':cloneJSON(node[key]);
}
function geometrySnapshot(node) {
  const fills=capturePaints(node,'fills');
  return {width:node.width,height:node.height,relativeTransform:cloneJSON(node.relativeTransform),
    fillGeometry:read(node,'fillGeometry',[]),fills,
    regionalPaints:read(node,'vectorNetwork',{}).regions?.some(region=>region.fills?.length && JSON.stringify(region.fills)!==JSON.stringify(fills))??false};
}
async function outlineGeometry(node, text) {
  // Reparent a temporary copy out of auto layout before conversion. This avoids
  // baking transient auto-layout shifts into exported text/stroke coordinates.
  const width=node.width,height=node.height;
  let stage=null,copy=null,outline=null;
  try {
    stage=figma.createFrame();stage.name='__FigmaMetal temporary outline workspace';
    stage.visible=false;stage.fills=[];stage.clipsContent=false;
    copy=node.clone();stage.appendChild(copy);copy.relativeTransform=[[1,0,0],[0,1,0]];
    if((copy.width!==width||copy.height!==height)&&typeof copy.resizeWithoutConstraints==='function') copy.resizeWithoutConstraints(width,height);
    outline=text?figma.flatten([copy],stage):copy.outlineStroke();
    if(!outline) throw new Error('Source outline operation returned no geometry');
    const data=geometrySnapshot(outline),m=data.relativeTransform;
    data.localTransform={a:m[0][0],b:m[1][0],c:m[0][1],d:m[1][1],tx:m[0][2],ty:m[1][2]};
    if(data.regionalPaints) throw new Error('Outlined geometry contains independent regional paints');
    return data;
  } finally {
    if(stage&&!stage.removed)stage.remove();
    if(copy&&!copy.removed)copy.remove();
    if(outline&&!outline.removed)outline.remove();
  }
}
async function captureNode(node,depth=0) {
  if(depth>64||++captureCount>5000) throw new Error('Export exceeds 64 levels or 5000 nodes');
  const captureDiagnostics=[];
  const out={id:node.id,name:node.name,type:node.type,...geometrySnapshot(node),
    visible:node.visible,opacity:read(node,'opacity',1),blendMode:read(node,'blendMode','NORMAL'),
    strokes:capturePaints(node,'strokes'),strokeGeometry:read(node,'strokeGeometry',[]),strokeAlign:read(node,'strokeAlign','CENTER'),
    effects:read(node,'effects',[]),isMask:read(node,'isMask',false),clipsContent:read(node,'clipsContent',false),
    layoutMode:read(node,'layoutMode','NONE'),itemReverseZIndex:read(node,'itemReverseZIndex',false),
    animations:read(node,'animations',{}),manualKeyframeTracks:read(node,'manualKeyframeTracks',{}),
    animationStyles:read(node,'animationStyles',[]),timelines:read(node,'timelines',[]),reactions:read(node,'reactions',[]),
    children:[],captureDiagnostics};
  if(out.animationStyles.length && !Object.keys(out.animations).length) captureDiagnostics.push({code:'PRESET_MOTION_UNAVAILABLE',message:'Node has animation styles but no resolved animation data was exposed.'});
  if(!('animations' in node)&&!('manualKeyframeTracks' in node)) captureDiagnostics.push({severity:'warning',code:'MOTION_API_UNAVAILABLE',message:'Motion properties are unavailable in this Figma host. Verify that the source is static.'});
  // Convert a TEMPORARY COPY to outlines. Never flatten the original text.
  if(node.type==='TEXT') {
    try {
      if(out.fills==='MIXED') throw new Error('Mixed text colors are not yet supported');
      if(node.hasMissingFont) throw new Error('Text has a missing font');
      for(const font of node.getRangeAllFontNames(0,node.characters.length)) await figma.loadFontAsync(font);
      out.outlinedText=await outlineGeometry(node,true);
    } catch(error) { captureDiagnostics.push({code:'TEXT_OUTLINE_FAILED',message:error.message}); }

  }
  if(Array.isArray(out.strokes)&&out.strokes.some(p=>p.visible!==false)&&typeof node.outlineStroke==='function') {
    try { out.strokeOutline=await outlineGeometry(node,false); }
    catch(error) { captureDiagnostics.push({code:'STROKE_OUTLINE_FAILED',message:error.message}); }

  }
  // Boolean fillGeometry is already resolved; exporting operand children would double-draw.
  if('children' in node && node.type!=='BOOLEAN_OPERATION') {
    const children=Array.from(node.children);
    for(const child of children) if(child.visible!==false) out.children.push(await captureNode(child,depth+1));
  }
  return out;
}
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
    captureCount=0;
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
