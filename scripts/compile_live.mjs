#!/usr/bin/env node
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {resolve,dirname} from 'node:path';
import {compileScene} from '../plugin/src/compiler.mjs';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
await mkdir(resolve(root,'artifacts/phase2'),{recursive:true});
for(const name of ['conformance','motion']) {
 const input=JSON.parse(await readFile(resolve(root,`fixtures/live/${name}.source.json`),'utf8'));
 const doc=compileScene(input.snapshot);
 doc.provenance=input.provenance;
 await writeFile(resolve(root,`fixtures/live/${name}.figmetal.json`),JSON.stringify(doc,null,2)+'\n');
 console.log(name,doc.diagnostics);
 if(doc.diagnostics.some(x=>x.severity==='error'))process.exitCode=1;
}
