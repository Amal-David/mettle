import {compileScene,compileTransition} from './compiler.mjs';

/** The host and command-line replay share this contract. A Community URL alone
 * is provenance, not source data; only captured Figma nodes enter the compiler. */
export const CAPTURE_FORMAT='mettle-source';
const copy=value=>JSON.parse(JSON.stringify(value));
const finite=value=>typeof value==='number'&&Number.isFinite(value);

function localRenderBounds(snapshot) {
  const matrix=snapshot.absoluteTransform,bounds=snapshot.absoluteRenderBounds;
  if(!Array.isArray(matrix)||matrix.length!==2||matrix.some(row=>!Array.isArray(row)||row.length!==3||!row.every(finite))||
    matrix[0][0]!==1||matrix[0][1]!==0||matrix[1][0]!==0||matrix[1][1]!==1) return null;
  if(!bounds||!['x','y','width','height'].every(key=>finite(bounds[key]))||bounds.width<=0||bounds.height<=0) return null;
  const local={x:bounds.x-matrix[0][2],y:bounds.y-matrix[1][2],width:bounds.width,height:bounds.height};
  return Object.values(local).every(finite)?local:null;
}

/** Only the provider's PNG header determines the raster size. The artwork stays
 * in the captured vector geometry, and the original PNG is a separate reference. */
export function referenceViewport(snapshot,png) {
  const bounds=localRenderBounds(snapshot);
  if(!bounds) throw new Error(`Figma reference bounds require an unrotated, unscaled selected root with visible render bounds (${snapshot.name??snapshot.id}).`);
  const signature=[137,80,78,71,13,10,26,10];
  if(!png||!Number.isInteger(png.length)||png.length<33||
    signature.some((byte,index)=>png[index]!==byte)||
    png[8]!==0||png[9]!==0||png[10]!==0||png[11]!==13||
    png[12]!==73||png[13]!==72||png[14]!==68||png[15]!==82||
    Array.from({length:8},(_,index)=>png[index+16]).some(byte=>!Number.isInteger(byte)||byte<0||byte>255)) {
    throw new Error(`Figma did not return a valid PNG reference for ${snapshot.name??snapshot.id}.`);
  }
  const uint32=offset=>png[offset]*0x1000000+png[offset+1]*0x10000+png[offset+2]*0x100+png[offset+3];
  const width=uint32(16),height=uint32(20);
  if(width<1||height<1||width>16384||height>16384) throw new Error('Figma reference dimensions must be between 1 and 16384 pixels.');
  return {x:bounds.x,y:bounds.y,width,height};
}

export function findTransitions(root,destination) {
  const literalID=typeof destination==='string';
  const target=literalID?{id:destination}:destination;
  const matches=[],counterparts=new Map();let count=0;
  const layerName=node=>node.name??node.id;
  function counterpart(path) {
    if(!path) return null;
    const key=JSON.stringify(path);
    if(counterparts.has(key)) return counterparts.get(key);
    let node=target;
    for(const name of path) {
      const candidates=(node?.children??[]).filter(child=>child.visible!==false&&layerName(child)===name);
      if(candidates.length!==1) {node=null;break;}
      node=candidates[0];
    }
    counterparts.set(key,node);return node;
  }
  function visit(node,path=[],scope=null,depth=0) {
    if(++count>5000||depth>64) throw new Error('Transition source node/depth budget exceeded');
    if(node.visible===false) return;
    if(node.type==='INSTANCE'||node.type==='COMPONENT') scope={node,path};
    for(const reaction of node.reactions??[]) {
      for(const action of reaction.actions??(reaction.action?[reaction.action]:[])) {
        let matchesDestination=action.destinationId===target.id;
        if(action.navigation==='CHANGE_TO'&&!literalID) {
          // CHANGE_TO applies to its containing instance. A component ID shared
          // by an unrelated destination instance cannot identify that instance.
          // Match the corresponding scope by its unique layer-name path; the
          // selected roots' names may differ between prototype states.
          const corresponding=scope?counterpart(scope.path):null;
          const componentID=corresponding?.type==='COMPONENT'?corresponding.id:
            corresponding?.type==='INSTANCE'?corresponding.sourceComponent?.id:undefined;
          matchesDestination=typeof componentID==='string'&&action.destinationId===componentID;
        }
        if(matchesDestination&&action.transition?.type==='SMART_ANIMATE') {
          if(action.navigation&&!['NAVIGATE','CHANGE_TO'].includes(action.navigation)) continue;
          const delay=reaction.trigger?.type==='AFTER_TIMEOUT'?reaction.trigger.timeout:0;
          if(!finite(delay)||delay<0) throw new Error(`Invalid source delay on ${node.name??node.id}.`);
          matches.push({nodeID:node.id,trigger:copy(reaction.trigger??{}),
            action:copy(action),duration:action.transition.duration,easing:action.transition.easing,delay});
        }
      }
    }
    const children=(node.children??[]).filter(child=>child.visible!==false),counts=new Map();
    for(const child of children) counts.set(layerName(child),(counts.get(layerName(child))??0)+1);
    for(const child of children) visit(child,path&&counts.get(layerName(child))===1?[...path,layerName(child)]:null,scope,depth+1);
  }
  visit(root);
  return matches;
}

export function makeCapture(nodes,{mode='motion',startNodeID='auto',duration=.6,loop='once',origin='center',viewport}={},provenance={}) {
  if(!['motion','static','transition'].includes(mode)) throw new Error('Choose Motion, static artwork, or a two-frame transition.');
  const count=mode==='transition'?2:1;
  if(nodes.length!==count) throw new Error(`Select exactly ${count} frame/component${count===2?'s':''}.`);
  if(!['once','loop','pingPong'].includes(loop)) throw new Error('Invalid playback mode.');
  if(!['center','topLeft'].includes(origin)) throw new Error('Invalid transform origin.');
  let ordered=[...nodes],transition=null;
  const options={loop,origin,includeMotion:mode==='motion'};
  if(viewport!==undefined) options.viewport=copy(viewport);
  const notes=[];
  if(viewport===undefined) for(const node of nodes) {
    const bounds=localRenderBounds(node),epsilon=1e-3;
    if(bounds&&finite(node.width)&&finite(node.height)&&
      (bounds.x < -epsilon||bounds.y < -epsilon||bounds.x+bounds.width > node.width+epsilon||bounds.y+bounds.height > node.height+epsilon)) {
      notes.push({severity:'warning',code:'CONTENT_OUTSIDE_CANVAS',nodeID:node.id,
        message:'Visible content extends beyond the selected canvas and will be clipped. For static artwork or two states, enable “Use Figma reference bounds” to include the overflow and save independent source references.'});
    }
  }
  if(mode==='transition') {
    if(nodes[0].id===nodes[1].id) throw new Error('Choose two different frames.');
    if(startNodeID==='auto') {
      const forward=findTransitions(nodes[0],nodes[1]),reverse=findTransitions(nodes[1],nodes[0]);
      if(Boolean(forward.length)===Boolean(reverse.length)) {
        throw new Error(forward.length
          ? 'Both frames have a Smart Animate connection. Choose the start frame explicitly.'
          : 'No Smart Animate connection joins these selections. Choose the start frame to create an explicit A → B clip.');
      }
      if(reverse.length) ordered.reverse();
    } else {
      if(!nodes.some(node=>node.id===startNodeID)) throw new Error('The start frame is no longer selected. Inspect the selection again.');
      if(ordered[0].id!==startNodeID) ordered.reverse();
    }
    const matches=findTransitions(ordered[0],ordered[1]);
    const timingKeys=new Set(matches.map(match=>JSON.stringify([match.duration,match.easing,match.delay])));
    if(timingKeys.size>1) throw new Error('Several source interactions have different timing. Select a pair with one unambiguous transition.');
    transition=matches[0]??null;
    if(transition) {
      if(!finite(transition.duration)||transition.duration<=0) throw new Error('The source transition has no valid duration.');
      if(!transition.easing) throw new Error('The source transition has no captured easing.');
      options.duration=transition.duration;options.easing=transition.easing;options.delay=transition.delay;
      notes.push({severity:'info',code:'SOURCE_TRANSITION',nodeID:transition.nodeID,
        message:`${ordered[0].name} → ${ordered[1].name}: source ${transition.duration}s Smart Animate transition, ${transition.delay}s delay. This clip does not run a prototype state machine.`});
    } else {
      options.duration=duration;options.delay=0;
      notes.push({severity:'warning',code:'EXPLICIT_TRANSITION_TIMING',nodeID:ordered[0].id,
        message:'This is an explicitly requested A → B clip. Timing comes from the panel; no matching source interaction was found.'});
    }
  }
  return {format:CAPTURE_FORMAT,version:1,mode,nodes:copy(ordered),options,transition,notes,provenance:copy(provenance)};
}

export function compileCapture(capture) {
  if(capture?.format!==CAPTURE_FORMAT||capture.version!==1) throw new Error('Expected a Mettle source capture (version 1).');
  if(!['motion','static','transition'].includes(capture.mode)) throw new Error('Unknown source capture mode.');
  const count=capture.mode==='transition'?2:1;
  if(!Array.isArray(capture.nodes)||capture.nodes.length!==count) throw new Error(`Capture requires ${count} source nodes.`);
  const options={...capture.options,includeMotion:capture.mode==='motion'};
  const document=capture.mode==='transition'
    ? compileTransition(capture.nodes[0],capture.nodes[1],options)
    : compileScene(capture.nodes[0],options);
  document.diagnostics.push(...(capture.notes??[]));
  if(capture.mode==='motion'&&!summarize(document).bindings) {
    document.diagnostics.push({severity:'warning',code:'NO_MOTION_TRACKS',nodeID:capture.nodes[0].id,
      message:'No executable motion tracks were captured. This export is static. Prototype interactions require the two-frame mode; static library variants do not imply animation.'});
  }
  document.provenance={...capture.provenance,captureFormat:CAPTURE_FORMAT,captureVersion:1,mode:capture.mode,
    sourceNodeIDs:capture.nodes.map(node=>node.id)};
  return document;
}

export function summarize(document) {
  let nodes=0,bindings=0,draws=0;
  function visit(node) {nodes++;bindings+=node.bindings.length;draws+=node.draws.length;node.children.forEach(visit);}
  document.scenes.forEach(scene=>visit(scene.root));
  return {nodes,bindings,draws,duration:document.scenes[0]?.duration??0,
    errors:document.diagnostics.filter(issue=>issue.severity==='error').length,
    warnings:document.diagnostics.filter(issue=>issue.severity==='warning').length};
}
