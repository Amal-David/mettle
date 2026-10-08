#!/usr/bin/env node
/** Replay the exact host capture without Figma. A failed compilation still writes
 * its diagnostic source artifact; default exit status remains failure. */
import {readFile,writeFile,mkdir,stat,realpath,lstat,readlink} from 'node:fs/promises';
import {resolve,dirname,basename} from 'node:path';
import {createHash} from 'node:crypto';
import {compileCapture,summarize} from '../plugin/src/export.mjs';

async function canonicalPath(target,depth=0) {
  if(depth>64) throw new Error('Excessive path alias nesting.');
  try {return await realpath(target);}catch(error){
    if(error.code!=='ENOENT') throw error;
    try {
      const entry=await lstat(target);
      if(entry.isSymbolicLink()) return canonicalPath(resolve(dirname(target),await readlink(target)),depth+1);
    }catch(missing){if(missing.code!=='ENOENT')throw missing;}
    return resolve(await canonicalPath(dirname(target),depth+1),basename(target));
  }
}
async function distinctFiles(paths) {
  const names=new Set(),identities=new Set();
  for(const path of paths.filter(Boolean)) {
    const canonical=await canonicalPath(path);
    if(names.has(canonical)) throw new Error('Source, scene and report must be different files, including path aliases.');
    names.add(canonical);
    try {
      const entry=await stat(path),identity=`${entry.dev}:${entry.ino}`;
      if(identities.has(identity)) throw new Error('Source, scene and report must be different files, including hard links.');
      identities.add(identity);
    }catch(error){if(error.code!=='ENOENT')throw error;}
  }
}

async function main() {
  const args=process.argv.slice(2);
  if(!args.length||args.includes('--help')) {
    console.log('Usage: node scripts/compile_capture.mjs capture.source.json --output scene.figmetal.json [--report report.json]');
    return args.length?0:2;
  }
  const input=resolve(args.shift()),options={};
  while(args.length) {
    const key=args.shift();
    if(!['--output','--report'].includes(key)||!args.length||args[0].startsWith('--')||options[key]) throw new Error(`Unknown, missing, or duplicate option: ${key}`);
    options[key]=args.shift();
  }
  if(!options['--output']) throw new Error('--output is required.');
  if((await stat(input)).size>32*1024*1024) throw new Error('Source capture exceeds 32 MiB.');
  const output=resolve(options['--output']),reportPath=options['--report']?resolve(options['--report']):null;
  await distinctFiles([input,output,reportPath]);
  const bytes=await readFile(input),capture=JSON.parse(bytes.toString('utf8'));
  const document=compileCapture(capture);
  document.provenance={...document.provenance,sourceCaptureSHA256:createHash('sha256').update(bytes).digest('hex')};
  const report={source:basename(input),sourceCaptureSHA256:document.provenance.sourceCaptureSHA256,
    summary:summarize(document),diagnostics:document.diagnostics};
  await mkdir(dirname(output),{recursive:true});
  await writeFile(output,JSON.stringify(document,null,2)+'\n');
  if(reportPath){await mkdir(dirname(reportPath),{recursive:true});await writeFile(reportPath,JSON.stringify(report,null,2)+'\n');}
  console.log(JSON.stringify(report,null,2));
  return report.summary.errors?1:0;
}
try {process.exitCode=await main();}catch(error){console.error(error.message);process.exitCode=2;}
