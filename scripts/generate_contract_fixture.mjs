import { writeFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { compileTransition } from '../plugin/src/compiler.mjs';
const shape = (id, x, opacity) => ({
  id, name:'Moving square',type:'RECTANGLE',width:40,height:40,
  relativeTransform:[[1,0,x],[0,1,20]],opacity,
  fills:[{type:'SOLID',color:{r:1,g:0,b:0}}],
  fillGeometry:[{data:'M0 0 H40 V40 H0 Z',windingRule:'NONZERO'}],children:[]
});
const frame = (id, x, opacity) => ({
  id,name:id,type:'FRAME',width:160,height:80,
  relativeTransform:[[1,0,0],[0,1,0]],fills:[],fillGeometry:[],children:[shape(`${id}:square`,x,opacity)]
});
const result=compileTransition(frame('Compiler A',10,1),frame('Compiler B',100,.5),{
  duration:1,loop:'once',easing:{type:'LINEAR'}
});
if(result.diagnostics.some(d=>d.severity==='error')) throw new Error(JSON.stringify(result.diagnostics));
const out=fileURLToPath(new URL('../examples/compiler-transition.figmetal.json',import.meta.url));
mkdirSync(fileURLToPath(new URL('../examples/',import.meta.url)),{recursive:true});
writeFileSync(out,JSON.stringify(result,null,2)+'\n');
console.log('Wrote synthetic JS-compiler → Swift-decoder contract fixture:',out);
