/** Deterministic Figma snapshot -> native scene compiler. Zero runtime dependencies.
 * Kept separate from the Figma host so source semantics can be unit-tested in Node.
 * Matrices are column-vector affine; times are seconds; source geometry is never traced.
 */
export const IDENTITY = Object.freeze({ a:1,b:0,c:0,d:1,tx:0,ty:0 });
const rgba = (r=1,g=1,b=1,a=1) => ({r,g,b,a});
const point = (x=0,y=0) => ({x,y});
const json = x => JSON.parse(JSON.stringify(x));
const equal = (a,b) => JSON.stringify(a) === JSON.stringify(b);
const finite = x => typeof x === 'number' && Number.isFinite(x);
const clamp = x => Math.min(1,Math.max(0,x));
export function affine(t) {
  if (!Array.isArray(t) || t.length !== 2 || t.some(row => !Array.isArray(row) || row.length !== 3 || !row.every(finite))) {
    throw new Error('Expected a finite Figma 2×3 transform');
  }
  return {a:t[0][0],b:t[1][0],c:t[0][1],d:t[1][1],tx:t[0][2],ty:t[1][2]};
}
export function multiply(l,r) {
  return {a:l.a*r.a+l.c*r.b,b:l.b*r.a+l.d*r.b,c:l.a*r.c+l.c*r.d,d:l.b*r.c+l.d*r.d,
    tx:l.a*r.tx+l.c*r.ty+l.tx,ty:l.b*r.tx+l.d*r.ty+l.ty};
}
export function inverse(t) {
  const det=t.a*t.d-t.b*t.c;
  if (!finite(det) || Math.abs(det)<1e-12) throw new Error('Singular source transform');
  return {a:t.d/det,b:-t.b/det,c:-t.c/det,d:t.a/det,tx:(t.c*t.ty-t.d*t.tx)/det,ty:(t.b*t.tx-t.a*t.ty)/det};
}
function value(v) {
  if (v?.type==='FLOAT' && finite(v.value)) return [v.value];
  if (v?.type==='COLOR' && ['r','g','b','a'].every(k=>finite(v.value?.[k]))) return ['r','g','b','a'].map(k=>v.value[k]);
  if (v?.type==='VECTOR' && finite(v.value?.x) && finite(v.value?.y)) return [v.value.x,v.value.y];
  throw new Error(`Unsupported or unresolved keyframe value ${v?.type}`);
}
export function easing(e={type:'LINEAR'}) {
  const named={LINEAR:{kind:'linear',control:[]},HOLD:{kind:'hold',control:[]},
    EASE_IN:{kind:'cubic',control:[.42,0,1,1]},EASE_OUT:{kind:'cubic',control:[0,0,.58,1]},
    EASE_IN_AND_OUT:{kind:'cubic',control:[.42,0,.58,1]}};
  if (named[e.type]) return json(named[e.type]);
  if (e.type==='CUSTOM_CUBIC_BEZIER') {
    const c=e.easingFunctionCubicBezier;
    const control=[c?.x1,c?.y1,c?.x2,c?.y2];
    if (control.every(finite) && control[0]>=0 && control[0]<=1 && control[2]>=0 && control[2]<=1) return {kind:'cubic',control};
  }
  throw new Error(`Easing ${e.type} is not implemented; original easing is retained in sourceMotion. No spring approximation is applied.`);
}
function paint(p,report,node) {
  if (p.visible===false) return null;
  if (p.blendMode && p.blendMode!=='NORMAL') { report('error','PAINT_BLEND',node,`Paint blend ${p.blendMode} is unsupported.`); return null; }
  if (p.type==='SOLID') return {kind:'solid',color:rgba(p.color.r,p.color.g,p.color.b),opacity:p.opacity??1,transform:IDENTITY,stops:[]};
  if (['GRADIENT_LINEAR','GRADIENT_RADIAL'].includes(p.type)) {
    if (!Array.isArray(p.gradientStops) || p.gradientStops.length<2 || p.gradientStops.length>64) {
      report('error','GRADIENT_STOPS',node,'Expected 2...64 gradient stops.');return null;
    }
    return {kind:p.type==='GRADIENT_LINEAR'?'linear':'radial',color:rgba(),opacity:p.opacity??1,
      transform:affine(p.gradientTransform),stops:json(p.gradientStops).map(s=>({position:s.position,color:s.color}))};
  }
  report('error','UNSUPPORTED_PAINT',node,`${p.type} paint needs a native implementation. No raster substitute was made.`);return null;
}
function paths(source,report,node) {
  const result=[];
  for (const p of source??[]) {
    if (!['NONZERO','EVENODD'].includes(p.windingRule)) {
      report('error','PATH_WINDING',node,`Unsupported winding ${p.windingRule}.`);continue;
    }
    if (typeof p.data!=='string' || p.data.length>2_000_000) {
      report('error','PATH_DATA',node,'Missing or excessive path data.');continue;
    }
    result.push({data:p.data,windingRule:p.windingRule});
  }
  return result;
}
function drawings(geometry,paints,size,transform,role,report,node) {
  if (paints==='MIXED') { report('error','MIXED_PAINTS',node,'Mixed/rich-text paints require region-level export.');return []; }
  const out=[];const ps=paths(geometry,report,node);
  if (!ps.length && (paints??[]).some(p=>p.visible!==false)) report('error','MISSING_GEOMETRY',node,`No ${role} geometry was exposed.`);
  // Live Figma conformance confirms the API paint array is bottom-to-top.
  for(let index=0;index<(paints??[]).length;index++) {
    const p=paint(paints[index],report,node);
    if(p && ps.length) out.push({paths:ps,paint:p,transform,size,paintIndex:index,role});
  }
  return out;
}
function motionBindings(source,report,options) {
  const animations=source.animations;
  const manual=source.manualKeyframeTracks;
  const hasResolved=animations && Object.keys(animations).length>0;
  const data=hasResolved?animations:(manual??{});
  const result=[];
  if (!hasResolved && Object.keys(data).length) report('warning','MANUAL_TRACK_FALLBACK',source,'Resolved animations unavailable; only exposed manual tracks are exported.');
  const map={TRANSLATION_X:['translationX'],TRANSLATION_Y:['translationY'],TRANSLATION_XY:['translationX','translationY'],
    OPACITY:['opacity'],ROTATION:['rotation'],SCALE_X:['scaleX'],SCALE_Y:['scaleY'],SCALE_XY:['scaleX','scaleY']};
  function add(field,binding,component) {
    try {
      const baseAll=value(binding.baseValue);
      const base=component===undefined?baseAll:[baseAll[component]];
      if (!base.every(finite)) throw new Error('Binding base dimensions do not match field');
      const sourceTracks=binding.tracks??[{keyframeOperation:'SET',keyframes:binding.keyframes}];
      const tracks=sourceTracks.map(track=>{
        const op=String(track.keyframeOperation??'SET').toLowerCase();
        if(!['set','offset','scale'].includes(op)) throw new Error(`Unknown track operation ${op}`);
        let previous=-Infinity;
        const keyframes=(track.keyframes??[]).map(k=>{
          if(!finite(k.timelinePosition)||k.timelinePosition<0||k.timelinePosition<=previous) throw new Error('Unsorted/duplicate keyframe times');
          previous=k.timelinePosition;
          const all=value(k.value);const v=component===undefined?all:[all[component]];
          if(v.length!==base.length || !v.every(finite)) throw new Error('Keyframe dimensions differ from base');
          return {time:k.timelinePosition,value:v,easing:easing(k.easing)};
        });
        if(!keyframes.length) throw new Error('Empty motion track');
        return {operation:op,keyframes};
      });
      const needed=field.includes(':')?4:1;
      if(base.length!==needed) throw new Error('Field/value dimension mismatch');
      if((field==='scaleX'||field==='scaleY')&&Math.abs(base[0])<1e-12) throw new Error('Cannot normalize scale from zero');
      // Figma Motion translation values are OFFSETS, unlike A→B absolute positions.
      // Live frame 2:9: static x=24, source keyframe=24, Figma renders x=48.
      // A resolved binding.baseValue may already include the static position.
      // Use a zero anchor for SET-led offset tracks; preserve raw sourceMotion.
      if(field==='translationX'||field==='translationY') {
        if(tracks[0]?.operation!=='set') throw new Error('Translation needs a leading SET track; OFFSET/SCALE-only source bases are not yet validated.');
        result.push({field,base:[0],tracks});
      } else result.push({field,base,tracks});
    } catch(error) { report('error','MOTION_BINDING',source,`${field}: ${error.message}`); }
  }
  for(const [name,binding] of Object.entries(data)) {
    if(!binding) continue;
    if(map[name]) {
      if(['ROTATION','SCALE_X','SCALE_Y','SCALE_XY'].includes(name)) {
        report('warning','EXPLICIT_TRANSFORM_ORIGIN',source,`Motion API does not supply a pivot here. Export uses the explicitly selected ${options.origin??'center'} origin; verify against Figma.`);
      }
      map[name].forEach((field,i)=>add(field,binding,map[name].length>1?i:undefined));
    } else if(name==='fills'||name==='strokes') {
      for(const [index,paintBinding] of Object.entries(binding)) {
        if(paintBinding?.properties) {report('error','SHADER_PROPERTY_MOTION',source,`${name}[${index}] shader parameter tracks are not implemented.`);continue;}
        const sourcePaint=source[name]?.[Number(index)];
        if(sourcePaint?.type!=='SOLID') {report('error','NON_SOLID_COLOR_MOTION',source,`${name}[${index}] color animation requires a solid paint.`);continue;}
        add(`${name}:${index}`,paintBinding);
      }
    } else {report('error','UNSUPPORTED_MOTION_FIELD',source,`${name} motion is not implemented. Its source data is retained.`);}
  }
  return result;
}

export function compileScene(snapshot,options={}) {
  const diagnostics=[];
  const sourceMotion={};
  const report=(severity,code,node,message)=>diagnostics.push({severity,code,nodeID:node.id??'',message});
  let duration=0,count=0;
  const timelineIDs=new Set();
  function visit(source,root=false,depth=0) {
    if(++count>5000||depth>64) throw new Error('Export node/depth budget exceeded');
    if(!finite(source.width)||!finite(source.height)||source.width<0||source.height<0) throw new Error(`Invalid dimensions for ${source.id}`);
    for(const issue of source.captureDiagnostics??[]) report(issue.severity??'error',issue.code,source,issue.message);
    if(source.effects?.some(e=>e.visible!==false)) report('error','EFFECTS',source,'Blur, shadow, shader, and other effects need native render passes; no effect was silently approximated.');
    if(source.isMask) report('error','SIBLING_MASK',source,'Sibling alpha/vector masks are not implemented. Frame clipsContent is supported.');
    if(source.blendMode&&!['NORMAL','PASS_THROUGH'].includes(source.blendMode)) report('error','NODE_BLEND',source,`Node blend ${source.blendMode} is unsupported.`);
    if(source.regionalPaints) report('error','REGIONAL_PAINTS',source,'Vector regions have independent paints; region-level extraction is not implemented.');
    if(source.layoutMode&&source.layoutMode!=='NONE') report('info','LAYOUT_SNAPSHOT',source,'Resolved layout is exported at this size. No responsive layout engine is included.');
    const ownTransform=affine(source.relativeTransform??[[1,0,0],[0,1,0]]);
    const output={id:source.id,name:source.name??source.id,transform:root?IDENTITY:ownTransform,
      size:point(source.width,source.height),opacity:source.visible===false?0:(source.opacity??1),
      origin:options.origin==='topLeft'?point():point(source.width/2,source.height/2),draws:[],clip:[],bindings:[],children:[]};
    const geometrySource=source.outlinedText??source;
    const fillTransform=source.outlinedText?(geometrySource.localTransform??multiply(inverse(ownTransform),affine(geometrySource.relativeTransform))):IDENTITY;
    output.draws.push(...drawings(geometrySource.fillGeometry,geometrySource.fills,
      point(geometrySource.width,geometrySource.height),fillTransform,'fills',report,source));
    if(source.outlinedText) report('info','TEXT_OUTLINED',source,'Text is exported as native vector outlines, not font files or raster pixels. Text is no longer editable in the player.');
    if(source.strokeOutline) {
      const s=source.strokeOutline;
      output.draws.push(...drawings(s.fillGeometry,s.fills,point(s.width,s.height),
        s.localTransform??multiply(inverse(ownTransform),affine(s.relativeTransform)),'strokes',report,source));
    } else if(source.strokes?.some?.(p=>p.visible!==false)) {
      if(source.strokeAlign==='CENTER') output.draws.push(...drawings(source.strokeGeometry,source.strokes,output.size,IDENTITY,'strokes',report,source));
      else report('error','STROKE_OUTLINE',source,'Inside/outside strokes require successful source outline extraction.');
    }
    if(source.clipsContent) {
      output.clip=paths(source.fillGeometry,report,source);
      if(!output.clip.length) report('error','CLIP_GEOMETRY',source,'Figma did not expose the clipping path.');
    }
    if(options.includeMotion!==false) {
      output.bindings=motionBindings(source,report,options);
      for(const b of output.bindings) for(const t of b.tracks) for(const k of t.keyframes) duration=Math.max(duration,k.time);
      for(const binding of Object.values(source.animations??{})) if(finite(binding?.timelineDuration)) duration=Math.max(duration,binding.timelineDuration);
      for(const timeline of source.timelines??[]) { if(finite(timeline.duration)) duration=Math.max(duration,timeline.duration);if(timeline.id) timelineIDs.add(timeline.id); }
    }
    if(Object.keys(source.animations??{}).length||Object.keys(source.manualKeyframeTracks??{}).length) {
      sourceMotion[source.id]={animations:source.animations??null,manualKeyframeTracks:source.manualKeyframeTracks??null,timelines:source.timelines??[]};
    }
    let children=(source.children??[]).filter(c=>c.visible!==false);
    if(source.itemReverseZIndex) children=[...children].reverse();
    output.children=children.map(c=>visit(c,false,depth+1));
    return output;
  }
  const root=visit(snapshot,true);
  if(timelineIDs.size>1) report('error','MULTIPLE_TIMELINES',snapshot,'Independent/nested timelines need explicit coordination; this player exports a single timeline.');
  if(snapshot.reactions?.length) report('warning','PROTOTYPE_EVENTS_NOT_EXPORTED',snapshot,'Interactive event wiring is not part of a single-scene export. Use the two-frame compiler for a constrained A→B clip.');
  const scene={name:snapshot.name??'Figma scene',width:snapshot.width,height:snapshot.height,duration,loop:options.loop??'once',root};
  return {format:'figma-metal',version:1,scenes:[scene],diagnostics,sourceMotion,exporter:{name:'Mettle',version:'0.2.0',source:'Figma Plugin API'}};
}

/** Strict, bounded Smart-Animate-style A→B compiler: stable geometry, translation,
 * opacity, solid colors. Rejects topology/size/rotation changes instead of crossfading them.
 * Match by unique hierarchical layer NAME, never by guessed pixel proximity.
 */
export function compileTransition(a,b,options={}) {
  const first=compileScene(a,{...options,includeMotion:false}),second=compileScene(b,{...options,includeMotion:false});
  first.diagnostics.push(...second.diagnostics);
  const report=(code,id,message)=>first.diagnostics.push({severity:'error',code,nodeID:id,message});
  const duration=options.duration??.6;
  if(!finite(duration)||duration<=0||duration>3600) throw new Error('Transition duration must be 0...3600 seconds');
  const ease=easing(options.easing??{type:'EASE_IN_AND_OUT'});
  first.scenes[0].duration=duration;first.scenes[0].name=`${a.name} → ${b.name}`;
  if(a.width!==b.width||a.height!==b.height) report('TRANSITION_SIZE',a.id,'A and B must have the same frame dimensions.');
  function track(node,field,base,target) {
    if(equal(base,target)) return;
    node.bindings.push({field,base,tracks:[{operation:'set',keyframes:[{time:0,value:base,easing:ease},{time:duration,value:target,easing:{kind:'linear',control:[]}}]}]});
  }
  function compare(x,y) {
    if(!equal(x.size,y.size)||!equal(x.clip,y.clip)) report('TRANSITION_GEOMETRY',x.id,'Animated size/clip geometry is not implemented.');
    if(['a','b','c','d'].some(k=>Math.abs(x.transform[k]-y.transform[k])>1e-7)) report('TRANSITION_LINEAR_TRANSFORM',x.id,'A→B rotation, skew, or scale changes are not implemented.');
    track(x,'translationX',[x.transform.tx],[y.transform.tx]);track(x,'translationY',[x.transform.ty],[y.transform.ty]);
    track(x,'opacity',[x.opacity],[y.opacity]);
    if(x.draws.length!==y.draws.length) report('TRANSITION_DRAW_COUNT',x.id,'Different draw counts.');
    else x.draws.forEach((d,i)=>{
      const target=y.draws[i];
      if(!equal(d.paths,target.paths)||!equal(d.transform,target.transform)||!equal(d.size,target.size)||d.role!==target.role||d.paintIndex!==target.paintIndex) {
        report('TRANSITION_DRAW_GEOMETRY',x.id,'Path morphs/different source geometry are not implemented.');return;
      }
      if(d.paint.kind==='solid'&&target.paint.kind==='solid') {
        const effective=p=>[p.color.r,p.color.g,p.color.b,p.color.a*p.opacity];
        track(x,`${d.role}:${d.paintIndex}`,effective(d.paint),effective(target.paint));
      } else if(!equal(d.paint,target.paint)) report('TRANSITION_PAINT',x.id,'Animated gradients are not implemented.');
    });
    const names=x.children.map(n=>n.name),other=y.children.map(n=>n.name);
    if(new Set(names).size!==names.length||new Set(other).size!==other.length) {report('AMBIGUOUS_LAYER_NAMES',x.id,'Sibling names must be unique for deterministic matching.');return;}
    if(!equal(names,other)) {report('TRANSITION_HIERARCHY',x.id,'Layer additions/removals/reordering are not implemented.');return;}
    x.children.forEach((child,i)=>compare(child,y.children[i]));
  }
  compare(first.scenes[0].root,second.scenes[0].root);
  first.sourceMotion={from:first.sourceMotion,to:second.sourceMotion};
  first.exporter.mode='two-frame-transition';
  return first;
}
