/** Motion adapter contracts checked against Figma's September 2026 live API.
 * Resolved keyframes are data, not programs. Never execute custom style code.
 */
export const MOTION_SUPPORT = Object.freeze({
  checkedAt: '2026-09-30',
  customStyles: 'resolved-supported-tracks',
  easingVariables: 'resolved-for-consumer-at-export',
  backEasing: 'source-cubic-required',
  textAnimation: 'whole-node-only; per-character/word not supported',
  audioTimeline: 'not-supported; no published capture contract verified',
  lottie: 'alternative-export; not a Mettle input or dependency'
});
const number = value => typeof value === 'number' && Number.isFinite(value);
const copy = value => JSON.parse(JSON.stringify(value));
export function compileEasing(e = {type:'LINEAR'}) {
  if (e?.type === 'VARIABLE_ALIAS') throw new Error('Unresolved easing variable; capture must resolve it for this node.');
  if (e?.type === 'HOLD') return {kind:'hold', control:[]};
  const named = {LINEAR:[], EASE_IN:[.42,0,1,1], EASE_OUT:[0,0,.58,1], EASE_IN_AND_OUT:[.42,0,.58,1]};
  const back = ['EASE_IN_BACK','EASE_OUT_BACK','EASE_IN_AND_OUT_BACK'];
  if (!(e?.type in named) && !back.includes(e?.type) && e?.type !== 'CUSTOM_CUBIC_BEZIER') {
    throw new Error(`Easing ${e?.type} needs a native implementation; springs are not approximated.`);
  }
  // Explicit source values take precedence over generic CSS named curves. Do not
  // mistake a cached cubic on a spring object for the spring itself.
  if (e.easingFunctionCubicBezier !== undefined) {
    const c=e.easingFunctionCubicBezier, control=[c?.x1,c?.y1,c?.x2,c?.y2];
    if (!control.every(number) || control[0]<0 || control[0]>1 || control[2]<0 || control[2]>1) {
      throw new Error('Invalid source cubic; expected finite controls and x in 0...1.');
    }
    if (e.type==='LINEAR' && control[0]===control[1] && control[2]===control[3]) return {kind:'linear',control:[]};
    return {kind:'cubic',control};
  }
  if (back.includes(e.type) || e.type==='CUSTOM_CUBIC_BEZIER') throw new Error(`${e.type} requires its exact source cubic.`);
  return {kind:e.type==='LINEAR'?'linear':'cubic',control:[...named[e.type]]};
}

/** Preset keyframe times are local to the style in the observed API. Manual
 * keyframes are already timeline-relative. `props.delay` duplicates placement;
 * adding it a second time is incorrect. Duration is already reflected in keys.
 */
export function trackPlacement(track, styles = []) {
  const preset=track.animationPreset;
  if (!preset) return 0;
  if (typeof preset.id!=='string' || !preset.id) throw new Error('Style track is missing its source instance ID.');
  const owner=styles.find(style=>style.id===preset.id);
  const offset=preset.timelineOffset ?? owner?.timelineOffset;
  if (!number(offset) || offset<0 || offset>86400) throw new Error('Style timelineOffset is missing, unresolved, or out of range.');
  const duration=preset.duration ?? owner?.duration;
  if (duration!==undefined && (!number(duration) || duration<0 || duration>86400)) throw new Error('Invalid style duration.');
  // Evidence: a one-second style's keys already span 0...1, not 0...100%.
  if (duration!==undefined && track.keyframes?.some(k=>k.timelinePosition>duration+1e-5)) {
    throw new Error('Style keys extend beyond its duration; timing convention is not recognized.');
  }
  return offset;
}

export function styleCoverage(source, report) {
  const styles=source.animationStyles ?? [];
  if (!styles.length) return;
  if (!Array.isArray(styles) || styles.length>64) throw new Error('Expected at most 64 applied animation styles.');
  const resolved=source.animations ?? {};
  const linked=new Set();
  function visit(value,depth=0) {
    if (!value || typeof value!=='object' || depth>40) return;
    if (Array.isArray(value.tracks)) for (const track of value.tracks) {
      if (track.animationPreset?.id) linked.add(track.animationPreset.id);
    }
    for (const [key,child] of Object.entries(value)) if (key!=='animationPreset' && key!=='keyframes') visit(child,depth+1);
  }
  visit(resolved);
  for (const style of styles) {
    if (!style.id || !linked.has(style.id)) report('error','UNRESOLVED_ANIMATION_STYLE',source,
      `Style ${style.name ?? style.id ?? '(unnamed)'} has no attributable resolved tracks. Wait for Figma to resolve it, then export again; it was not replaced with manual or static content.`);
  }
}

/** Resolve tokens in the consumer's effective variable mode, not the collection
 * default. Raw aliases are retained separately by capture for audit/re-export.
 */
export async function resolveMotionVariables(figma, consumer, raw) {
  const resolutions=[],cache=new Map(); let visited=0;
  async function resolve(value,path,depth=0,chain=[]) {
    if (++visited>200000 || depth>48) throw new Error('Motion variable resolution budget exceeded.');
    if (value===null || typeof value!=='object') return value;
    if (value.type==='VARIABLE_ALIAS') {
      if (typeof value.id!=='string' || !value.id || chain.includes(value.id) || chain.length>=16) throw new Error(`Cyclic or invalid motion alias at ${path}.`);
      if (!figma.variables?.getVariableByIdAsync) throw new Error('This host cannot resolve motion variables.');
      let token=cache.get(value.id);
      if (!token) {
        token=(async()=>{
        const variable=await figma.variables.getVariableByIdAsync(value.id);
        if (!variable || typeof variable.resolveForConsumer!=='function') throw new Error(`Motion variable ${value.id} is unavailable.`);
        const result=await variable.resolveForConsumer(consumer);
        if (!result || result.value===undefined) throw new Error(`Motion variable ${value.id} did not resolve.`);
        return copy(result);
        })();cache.set(value.id,token);
      }
      token=await token;
      const resolved=await resolve(token.value,path,depth+1,[...chain,value.id]);
      resolutions.push({path,id:value.id,resolvedType:token.resolvedType,value:copy(resolved)});
      return resolved;
    }
    if (Array.isArray(value)) return Promise.all(value.map((item,index)=>resolve(item,`${path}[${index}]`,depth+1,chain)));
    const out={};
    for (const [key,child] of Object.entries(value)) {
      // Avoid prototype mutation even with externally supplied JSON snapshots.
      Object.defineProperty(out,key,{value:await resolve(child,`${path}.${key}`,depth+1,chain),enumerable:true,writable:true,configurable:true});
    }
    return out;
  }
  const resolved=await resolve(raw,'motion');
  resolutions.sort((a,b)=>a.path<b.path?-1:a.path>b.path?1:a.id<b.id?-1:1);
  return {resolved,resolutions};
}
