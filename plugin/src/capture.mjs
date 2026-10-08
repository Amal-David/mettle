import {resolveMotionVariables} from './motion.mjs';
/** Shared, capability-guarded live Figma capture. No UI, compiler, or network. */
export function createCapture(figma) {
let captureCount = 0;
const audit = {created:[], removed:[]};
const temporaryIDs = new Set();
const cloneJSON = value => value == null ? value : JSON.parse(JSON.stringify(value));
const read = (node, key, fallback) => {
  if (!(key in node)) return fallback;
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
  const temporary=[];
  const page=figma.currentPage;
  const previousSelection=page&&Array.isArray(page.selection)?Array.from(page.selection):null;
  let changedSelection=false;
  function observeTemporarySelection() {
    if(page&&page===figma.currentPage&&Array.from(page.selection).some(node=>temporaryIDs.has(node.id))) changedSelection=true;
  }
  function remember(node) {
    audit.created.push(node.id);temporaryIDs.add(node.id);temporary.push(node);observeTemporarySelection();
  }
  let stage=null,copy=null,outline=null;
  try {
    stage=figma.createFrame();remember(stage);stage.name='__Mettle temporary outline workspace';
    stage.visible=false;stage.fills=[];stage.clipsContent=false;
    copy=node.clone();remember(copy);stage.appendChild(copy);copy.relativeTransform=[[1,0,0],[0,1,0]];
    if((copy.width!==width||copy.height!==height)&&typeof copy.resizeWithoutConstraints==='function') copy.resizeWithoutConstraints(width,height);
    outline=text?figma.flatten([copy],stage):copy.outlineStroke();
    if(outline) remember(outline);
    if(!outline) throw new Error('Source outline operation returned no geometry');
    const data=geometrySnapshot(outline),m=data.relativeTransform;
    data.localTransform={a:m[0][0],b:m[1][0],c:m[0][1],d:m[1][1],tx:m[0][2],ty:m[1][2]};
    if(data.regionalPaints) throw new Error('Outlined geometry contains independent regional paints');
    return data;
  } finally {
    observeTemporarySelection();
    if(stage&&!stage.removed)stage.remove();
    if(copy&&!copy.removed)copy.remove();
    if(outline&&!outline.removed)outline.remove();
    for(const n of temporary) if(n.removed&&!audit.removed.includes(n.id)) audit.removed.push(n.id);
    // Only this synchronous block mutates document selection. Its snapshot is
    // taken after any earlier async font/component reads, so a user selection
    // made while those reads were pending is not rewound to the export's start.
    if(changedSelection&&previousSelection&&page===figma.currentPage&&
      Array.from(page.selection).every(node=>node.removed||temporaryIDs.has(node.id))) {
      page.selection=previousSelection.filter(node=>!node.removed);
    }
  }
}
async function captureNode(node,options={}) {
  // Prototype endpoints and explicit static exports do not consume Figma's
  // independently gated Motion beta. A getter can exist yet throw on accounts
  // without Motion: never probe it for these modes, and never treat a failing
  // getter as an empty animation in a motion export.
  return visit(node,0,options);
}
async function visit(node,depth,options) {
  if(depth>64||++captureCount>5000) throw new Error('Export exceeds 64 levels or 5000 nodes');
  const captureDiagnostics=[];
  const out={id:node.id,name:node.name,type:node.type,...geometrySnapshot(node),
    visible:node.visible,opacity:read(node,'opacity',1),blendMode:read(node,'blendMode','NORMAL'),
    strokes:capturePaints(node,'strokes'),strokeGeometry:read(node,'strokeGeometry',[]),strokeAlign:read(node,'strokeAlign','CENTER'),
    effects:read(node,'effects',[]),isMask:read(node,'isMask',false),clipsContent:read(node,'clipsContent',false),
    layoutMode:read(node,'layoutMode','NONE'),itemReverseZIndex:read(node,'itemReverseZIndex',false),
    animations:options.includeMotion===false?{}:read(node,'animations',{}),
    manualKeyframeTracks:options.includeMotion===false?{}:read(node,'manualKeyframeTracks',{}),
    animationStyles:options.includeMotion===false?[]:read(node,'animationStyles',[]),
    timelines:options.includeMotion===false?[]:read(node,'timelines',[]),reactions:read(node,'reactions',[]),
    children:[],captureDiagnostics};
  if(depth===0) for(const property of ['absoluteTransform','absoluteRenderBounds','absoluteBoundingBox']) {
    if(property in node) out[property]=read(node,property,null);
  }
  // CHANGE_TO reactions target the main component's variant ID, not an
  // instance's scene ID. Retain that verified identity for matching two
  // selected instances. Never clone the live ComponentNode (it is cyclic),
  // and never use the synchronous getter in dynamic-page plugins.
  if(node.type==='INSTANCE') {
    try {
      if(!('getMainComponentAsync' in node) || typeof node.getMainComponentAsync!=='function') throw new Error('The host does not expose getMainComponentAsync');
      const main=await node.getMainComponentAsync();
      if(!main || typeof main.id!=='string' || !main.id) throw new Error('The main component is unavailable');
      out.sourceComponent={id:main.id,name:read(main,'name',main.id),key:read(main,'key',null)};
    } catch(error) {captureDiagnostics.push({severity:'warning',code:'INSTANCE_COMPONENT_UNAVAILABLE',message:`Source variant identity could not be read: ${error.message??error}. Automatic prototype direction may need an explicit start selection.`});}
  }
  // Keep raw source aliases and custom-style metadata. Compile only resolved
  // consumer-mode data; a missing token is an error, never a default easing.
  out.rawMotion={animations:cloneJSON(out.animations),manualKeyframeTracks:cloneJSON(out.manualKeyframeTracks),animationStyles:cloneJSON(out.animationStyles)};
  try {
    const tokens=await resolveMotionVariables(figma,node,out.rawMotion);
    Object.assign(out,tokens.resolved);out.motionVariableResolutions=tokens.resolutions;
  } catch(error) {captureDiagnostics.push({code:'MOTION_VARIABLE_UNRESOLVED',message:error.message});}
  if(options.includeMotion!==false) {
    if(out.animationStyles.length && !Object.keys(out.animations).length) captureDiagnostics.push({code:'PRESET_MOTION_UNAVAILABLE',message:'Node has animation styles but no resolved animation data was exposed.'});
    if(!('animations' in node)&&!('manualKeyframeTracks' in node)) captureDiagnostics.push({severity:'warning',code:'MOTION_API_UNAVAILABLE',message:'Motion properties are unavailable in this Figma host. Verify that the source is static.'});
  } else out.motionCapture='not-requested';
  // Figma exposes glyph outlines directly on uniform text in supported hosts.
  // Prefer that source geometry; flattening text is not supported by every host.
  if(node.type==='TEXT') {
    try {
      if(out.fills==='MIXED') throw new Error('Mixed text colors are not yet supported');
      if(node.hasMissingFont) throw new Error('Text has a missing font');
      if(out.fillGeometry.length) {
        out.textGeometry='source-glyph-paths';
        captureDiagnostics.push({severity:'info',code:'TEXT_SOURCE_OUTLINES',message:'Uniform text uses Figma-provided glyph paths. No font file or raster image is exported.'});
      } else {
        for(const font of node.getRangeAllFontNames(0,node.characters.length)) await figma.loadFontAsync(font);
        out.outlinedText=await outlineGeometry(node,true);
      }
    } catch(error) { captureDiagnostics.push({code:'TEXT_OUTLINE_FAILED',message:error.message}); }

  }
  if(Array.isArray(out.strokes)&&out.strokes.some(p=>p.visible!==false)&&typeof node.outlineStroke==='function') {
    try { out.strokeOutline=await outlineGeometry(node,false); }
    catch(error) { captureDiagnostics.push({code:'STROKE_OUTLINE_FAILED',message:error.message}); }

  }
  // Boolean fillGeometry is already resolved; exporting operand children would double-draw.
  if('children' in node && node.type!=='BOOLEAN_OPERATION') {
    const children=Array.from(node.children);
    for(const child of children) if(child.visible!==false) out.children.push(await visit(child,depth+1,options));
  }
  return out;
}
return {captureNode, audit, ownsTemporaryNode(id){return temporaryIDs.has(id);}, reset(){captureCount=0;}};
}
