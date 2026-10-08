/* Figma host UI adapter. FM/FMC/FME are injected by build.mjs. */
figma.showUI(__html__, { width: 480, height: 690, themeColors: true });
let busy=false;
let selectionToRestore=null;
const capture=FMC.createCapture(figma);
const captureNode=capture.captureNode;
function notifySelection(reason='selection') {
  if(busy) return;
  figma.ui.postMessage({type:'selection',reason,nodes:Array.from(figma.currentPage.selection).map(node=>({id:node.id,name:node.name,type:node.type}))});
}
if(typeof figma.on==='function') figma.on('selectionchange',()=>{
  if(busy) {
    const nodes=Array.from(figma.currentPage.selection);
    if(selectionToRestore&&nodes.every(node=>!capture.ownsTemporaryNode(node.id))) {
      selectionToRestore={page:figma.currentPage,nodes};
    }
    return;
  }
  notifySelection();
});
notifySelection();
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
  if(message.type==='export') selectionToRestore={page:figma.currentPage,nodes:Array.from(figma.currentPage.selection)};
  let selectionReason='selection';
  try {
    if(message.type==='selection') {busy=false;notifySelection();return;}
    if(message.type==='reveal-node') {
      const node=await figma.getNodeByIdAsync(message.nodeID);
      if(node&&'visible' in node) {figma.currentPage.selection=[node];figma.viewport.scrollAndZoomIntoView([node]);selectionReason='reveal';}
      return;
    }
    if(message.type==='create-test') {await createTestFrames();return;}
    if(message.type!=='export') return;
    const selection=Array.from(figma.currentPage.selection);
    const expected=message.mode==='transition'?2:1;
    if(selection.length!==expected) throw new Error(`Select exactly ${expected} frame/component${expected===2?'s':''}.`);
    if(selection.some(n=>!('width' in n)||!('height' in n))) throw new Error('Selection must have a width and height.');
    if(message.referenceBounds&&!['static','transition'].includes(message.mode)) throw new Error('Figma reference bounds are available for static artwork or two states. A single PNG cannot establish the bounds of a keyframe animation.');
    capture.reset();
    const snapshots=[];
    for(const node of selection) snapshots.push(await captureNode(node,{includeMotion:message.mode==='motion'}));
    const provenance={source:'Figma Plugin API',fileName:figma.root?.name??'',
      fileKey:('fileKey' in figma?figma.fileKey:null)??null};
    let viewport;
    const referenceFrames=[];
    if(message.referenceBounds) {
      let totalBytes=0;
      const exportSettings={format:'PNG',constraint:{type:'SCALE',value:1},contentsOnly:true,useAbsoluteBounds:false};
      provenance.referenceExports=[];
      for(let index=0;index<selection.length;index++) {
        const node=selection[index],bytes=await node.exportAsync(exportSettings);
        if(!bytes||!Number.isInteger(bytes.length)||(totalBytes+=bytes.length)>32*1024*1024) throw new Error('Figma reference PNGs exceed the 32 MiB transport limit. Select smaller source frames.');
        const local=FME.referenceViewport(snapshots[index],bytes);
        if(viewport&&!['x','y','width','height'].every(key=>viewport[key]===local[key])) {
          throw new Error('The selected Figma references have different local viewports. Use matching source frames before exporting a two-state comparison.');
        }
        viewport??=local;
        const fileName=(node.name.replace(/[^a-z0-9_-]+/gi,'-').slice(0,64)||'scene')+`-${index+1}.figma.png`;
        provenance.referenceExports.push({id:node.id,name:node.name,width:local.width,height:local.height,viewport:local,exportSettings});
        referenceFrames.push({name:node.name,fileName,width:local.width,height:local.height,bytes:Array.from(bytes)});
      }
    }
    const source=FME.makeCapture(snapshots,{mode:message.mode,startNodeID:message.startNodeID??'auto',
      loop:message.loop??'once',origin:message.origin??'center',duration:message.duration,viewport},provenance);
    const document=FME.compileCapture(source);
    const blocked=document.diagnostics.some(d=>d.severity==='error')&&!message.allowPartial;
    const filename=(source.nodes[0].name.replace(/[^a-z0-9_-]+/gi,'-').slice(0,64)||'scene')+'.figmetal.json';
    figma.ui.postMessage({type:'result',document,source,summary:FME.summarize(document),filename,blocked,referenceFrames});
  } catch(error) { figma.ui.postMessage({type:'failure',message:error.message??String(error)}); }
  finally {
    // Outline capture restores its own synchronous temporary selections. Keep
    // genuine selections made during asynchronous reads, including deselecting
    // everything. This fallback only handles a surviving plugin-owned node.
    const current=Array.from(figma.currentPage.selection);
    if(selectionToRestore&&current.some(node=>capture.ownsTemporaryNode(node.id))) {
      const real=current.filter(node=>!node.removed&&!capture.ownsTemporaryNode(node.id));
      figma.currentPage.selection=real.length?real:selectionToRestore.page===figma.currentPage?selectionToRestore.nodes.filter(node=>!node.removed&&!capture.ownsTemporaryNode(node.id)):[];
    }
    selectionToRestore=null;
    busy=false;notifySelection(selectionReason);figma.ui.postMessage({type:'ready'});
  }
};
