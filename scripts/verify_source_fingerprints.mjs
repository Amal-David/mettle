#!/usr/bin/env node
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
// Returned by the shared capture code running inside live Figma on 2026-09-29.
// FNV is an accidental-corruption fingerprint, not a security/authenticity proof.
const expected={'1:9':['9df1c9b9','bbf47e5e'],'1:10':['db2ad3ca','e7a2be4f'],'1:11':['b5744153','eeb6d782'],'1:12':['ea1a26e9','d58eefd1'],'1:13':['ffc392b6','c662b58b'],'2:2':['ece8f3cc','9acf535c'],'2:3':['eceb6753','5bd53424'],'2:4':['ae84a029','c6977714'],'2:5':['68d361e','82712dda','aef608d0'],'2:6':['1c6c33a4','9df14a66'],'2:7':['9ff78cfc','3e96f98c'],'2:8':['3f9e66ad','cbc9d7e0'],'2:9':['43db9cc0','39a035ae']};
const hash=x=>{let h=2166136261;for(const c of JSON.stringify(x))h=Math.imul(h^c.charCodeAt(0),16777619)>>>0;return h.toString(16);};
let count=0;function visit(n){assert.equal(hash(n.fillGeometry),expected[n.id][0],`Geometry ${n.id}`);assert.equal(hash(n.relativeTransform),expected[n.id][1],`Transform ${n.id}`);if(n.strokeOutline)assert.equal(hash(n.strokeOutline.fillGeometry),expected[n.id][2],`Stroke ${n.id}`);count++;n.children?.forEach(visit);}
for(const name of ['conformance','motion'])visit(JSON.parse(readFileSync(new URL(`../fixtures/live/${name}.source.json`,import.meta.url))).snapshot);
assert.equal(count,Object.keys(expected).length);
console.log(`Verified ${count} source-node geometry/transform fingerprints against live Figma; stroke outline matched too.`);
