#!/usr/bin/env node
/** Replay frozen, attributed Figma source through the same host export path.
 * PNGs are provider originals: this script never renders, crops, or resizes them.
 * Run with --check to verify committed artifacts without rewriting anything.
 */
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {makeCapture, compileCapture, summarize} from '../plugin/src/export.mjs';

const repository = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const root = path.join(repository, 'fixtures/community/material3');
const check = process.argv.includes('--check');
if (process.argv.slice(2).some(arg => arg !== '--check')) {
  throw new Error('Usage: node scripts/compile_community.mjs [--check]');
}
const json = value => JSON.stringify(value, null, 2) + '\n';
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const read = name => fs.readFileSync(path.join(root, name));
const parse = name => JSON.parse(read(name));
const assert = (condition, message) => { if (!condition) throw new Error(message); };
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const provenanceBytes = read('provenance.json');
const provenance = JSON.parse(provenanceBytes);
assert(provenance.format === 'mettle-community-provenance' && provenance.version === 1,
  'Expected version 1 Community provenance.');
const bounds = parse(provenance.sourceBounds.path);
assert(hash(read(provenance.sourceBounds.path)) === provenance.sourceBounds.sha256,
  'Source bounds no longer match their capture fingerprint.');
const fixtures = new Map();

for (const fixture of provenance.fixtures) {
  assert(!fixtures.has(fixture.slug), `Duplicate source fixture: ${fixture.slug}`);
  const snapshotBytes = read(fixture.snapshot.path);
  const png = read(fixture.reference.path);
  assert(hash(snapshotBytes) === fixture.snapshot.sha256, `${fixture.slug}: source fingerprint changed.`);
  assert(hash(png) === fixture.reference.sha256, `${fixture.slug}: independent Figma PNG fingerprint changed.`);
  assert(png.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) &&
    png.toString('ascii', 12, 16) === 'IHDR', `${fixture.slug}: reference is not a PNG.`);
  const width = png.readUInt32BE(16), height = png.readUInt32BE(20);
  assert(width === fixture.reference.width && height === fixture.reference.height,
    `${fixture.slug}: PNG dimensions disagree with provenance.`);
  const snapshot = JSON.parse(snapshotBytes);
  assert(snapshot.id === fixture.instanceId && same(snapshot.sourceComponent, fixture.sourceComponent),
    `${fixture.slug}: imported source component identity changed.`);
  const observed = bounds.bounds.find(item => item.slug === fixture.slug);
  assert(observed && observed.frameId === fixture.sourceFrameId && observed.instanceId === snapshot.id,
    `${fixture.slug}: missing source frame/bounds identity.`);
  assert(same(snapshot.absoluteTransform, observed.instance.absoluteTransform) &&
    same(snapshot.absoluteRenderBounds, observed.instance.absoluteRenderBounds),
    `${fixture.slug}: separately captured bounds disagree with the snapshot.`);
  const transform = snapshot.absoluteTransform, render = snapshot.absoluteRenderBounds;
  assert(transform[0][0] === 1 && transform[0][1] === 0 && transform[1][0] === 0 && transform[1][1] === 1,
    `${fixture.slug}: viewport derivation only supports the observed translation-only source roots.`);
  // Provider SVG evidence in provenance establishes the fractional origin for
  // the circular control. Keep the original PNG's dimensions, including Figma's
  // subpixel rounding; do not floor the origin or enlarge a 404px PNG to 405px.
  const viewport = {x: render.x - transform[0][2], y: render.y - transform[1][2], width, height};
  assert(same(viewport, fixture.reference.viewport), `${fixture.slug}: source viewport evidence changed.`);
  fixtures.set(fixture.slug, {fixture, snapshot, viewport});
}
assert(fixtures.size === 11, 'Expected the eleven frozen Material 3 source endpoints.');

const artifacts = new Map();
const cases = [];
const provenanceReference = {path: 'provenance.json', sha256: hash(provenanceBytes)};
const source = slug => {
  const value = fixtures.get(slug);
  assert(value, `Missing captured source ${slug}`);
  return value;
};
const allowedBlockers = new Set(['TRANSITION_GEOMETRY', 'TRANSITION_DRAW_GEOMETRY']);

function compile(id, slugs, mode, blocked = false) {
  const endpoints = slugs.map(source);
  const viewport = endpoints[0].viewport;
  assert(endpoints.every(item => same(item.viewport, viewport)),
    `${id}: endpoints require a common independently exported source viewport.`);
  const capture = makeCapture(endpoints.map(item => item.snapshot), {
    mode, viewport,
    // The switch has a genuine reverse connection too, so explicitly choose
    // the source state while still requiring its captured reaction and timing.
    ...(mode === 'transition' ? {startNodeID: endpoints[0].snapshot.id} : {}),
  }, {
    communityURL: provenance.communityURL,
    creator: provenance.creator,
    capturedDate: provenance.capturedDate,
    sourceManifest: {...provenanceReference, path: 'fixtures/community/material3/provenance.json'},
    fixtureSlugs: slugs,
    referenceCoverage: mode === 'static' ? 'static' : 'endpoint-states',
    prototypePlaybackFramesCaptured: false,
  });
  if (mode === 'transition') {
    assert(capture.transition && capture.transition.action.navigation === 'CHANGE_TO',
      `${id}: no genuine source CHANGE_TO transition; inferred timing is forbidden.`);
    assert(capture.transition.action.destinationId === endpoints[1].snapshot.sourceComponent.id,
      `${id}: transition no longer points to the captured destination component.`);
    assert(!capture.notes.some(note => note.code === 'EXPLICIT_TRANSITION_TIMING'),
      `${id}: source timing was replaced by panel defaults.`);
  }
  const document = compileCapture(capture);
  const summary = summarize(document);
  const errors = document.diagnostics.filter(issue => issue.severity === 'error');
  const warnings = document.diagnostics.filter(issue => issue.severity === 'warning');
  assert(warnings.every(issue => mode === 'static' && issue.code === 'PROTOTYPE_EVENTS_NOT_EXPORTED'),
    `${id}: unexpected compiler warning: ${warnings.map(issue => issue.code).join(', ')}`);
  assert(summary.draws > 0, `${id}: compiler produced no source artwork.`);
  if (blocked) {
    assert(errors.some(issue => issue.code === 'TRANSITION_DRAW_GEOMETRY'),
      `${id}: expected unsupported source path change was not rejected. Verify real Figma playback before revising this contract.`);
    assert(errors.every(issue => allowedBlockers.has(issue.code)),
      `${id}: unexpected errors: ${errors.map(issue => issue.code).join(', ')}`);
    assert(capture.transition.trigger.type === 'AFTER_TIMEOUT', `${id}: source loader trigger changed.`);
  } else {
    assert(errors.length === 0, `${id}: unexpected compilation errors: ${errors.map(issue => issue.code).join(', ')}`);
    if (mode === 'transition') {
      assert(summary.bindings > 0 && capture.transition.trigger.type === 'ON_HOVER',
        `${id}: expected a real animated hover transition.`);
    } else {
      assert(summary.bindings === 0, `${id}: static endpoint unexpectedly contains executable motion.`);
    }
  }
  if (mode === 'transition') {
    assert(summary.duration === capture.transition.delay + capture.transition.duration,
      `${id}: source delay/duration were not preserved.`);
  }
  assert(document.scenes[0].width === viewport.width && document.scenes[0].height === viewport.height,
    `${id}: compiled viewport differs from the independent reference.`);
  assert(document.scenes[0].root.transform.tx === -viewport.x &&
    document.scenes[0].root.transform.ty === -viewport.y,
    `${id}: compiled root has the wrong camera offset.`);
  const sourcePath = `source/${id}.source.json`;
  const compiledPath = `compiled/${id}${blocked ? '.blocked' : ''}.figmetal.json`;
  const sourceBytes = json(capture);
  document.provenance.sourceCaptureSHA256 = hash(sourceBytes);
  const compiledBytes = json(document);
  artifacts.set(sourcePath, sourceBytes);
  artifacts.set(compiledPath, compiledBytes);
  cases.push({id, mode, status: blocked ? 'blocked' : 'compiled',
    coverage: mode === 'static' ? 'static' : 'endpoint-states', fixtureSlugs: slugs,
    viewport, source: {path: sourcePath, sha256: hash(sourceBytes)},
    compiled: {path: compiledPath, sha256: hash(compiledBytes)}, summary,
    expectedErrorCodes: blocked ? [...allowedBlockers] : [],
    diagnostics: document.diagnostics,
    ...(capture.transition ? {sourceTransition: capture.transition} : {}),
  });
}

for (const slug of fixtures.keys()) compile(slug, [slug], 'static');
compile('switch-hover', ['switch-enabled', 'switch-hovered'], 'transition');
// This is the captured creator-authored cycle, not numerical variant order.
const loadingCycle = [1, 2, 3, 4, 5, 7, 6, 1];
for (let index = 0; index < loadingCycle.length - 1; index++) {
  const a = loadingCycle[index], b = loadingCycle[index + 1];
  compile(`loading-${a}-to-${b}`, [`loading-step-${a}`, `loading-step-${b}`], 'transition', true);
}
const report = {format: 'mettle-community-compilation', version: 1,
  provenance: provenanceReference, status: 'compiled-with-expected-blockers',
  nativeComparison: 'not-run', prototypePlaybackFramesCaptured: false,
  note: 'Compilation acceptance and source endpoint capture are not evidence of native Metal or intermediate motion parity.',
  cases};
artifacts.set('compile-report.json', json(report));

// Evaluate all source and diagnostic gates before any output is written.
for (const [relative, contents] of artifacts) {
  const destination = path.join(root, relative);
  if (check) {
    assert(fs.existsSync(destination) && fs.readFileSync(destination, 'utf8') === contents,
      `${relative}: missing or stale artifact. Run node scripts/compile_community.mjs and review the source-driven change.`);
  } else {
    fs.mkdirSync(path.dirname(destination), {recursive: true});
    fs.writeFileSync(destination, contents);
  }
}
console.log(`${check ? 'Verified' : 'Compiled'} ${fixtures.size} static Community endpoints, one source hover transition, and seven expected path-change blockers.`);
console.log('Independent Figma PNGs preserved. Native Metal and intermediate prototype playback parity remain unverified.');
