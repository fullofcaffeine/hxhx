#!/usr/bin/env node
'use strict';

// Compare the bootstrap input manifest with an independently assembled manifest.
// A matching final digest alone cannot explain a missing input or ordering error.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const repo = path.resolve(__dirname, '../..');
const script = 'scripts/hxhx/regenerate-hxhx-bootstrap.sh';
const helper = 'scripts/hxhx/hash-bootstrap-inputs.sh';
const source = fs.readFileSync(path.join(repo, script), 'utf8');
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'bootstrap-fingerprint-'));
const fields = [
  ['haxe_bin_requested', 'stage0_haxe_requested'],
  ['haxe_bin_resolved', 'stage0_haxe_resolved'],
  ['haxe_bin_mode', 'stage0_haxe_mode'],
  ['haxe_bin_policy', 'HXHX_BOOTSTRAP_STAGE0_HAXE_POLICY'],
  ['haxe_bin_switched', 'stage0_haxe_switched'],
  ['haxe_native_candidate', 'stage0_haxe_native_candidate'],
  ['haxe_version', 'stage0_haxe_version'],
  ...[
    'disable_prepasses', 'no_opt', 'no_inline', 'no_expr_macros',
    'no_external_macro_host', 'no_stage3', 'no_internal_tools', 'no_display',
    'ocaml_only', 'no_line_directives', 'ocamlrunparam', 'progress', 'telemetry',
    'telemetry_detail', 'telemetry_class', 'telemetry_field',
  ].map(name => [`stage0_${name}`, `HXHX_STAGE0_${name.toUpperCase()}`]),
  ['bootstrap_profile', 'HXHX_BOOTSTRAP_PROFILE'],
];
const trees = [
  'packages/hxhx/src', 'packages/hxhx-core/src', 'packages/reflaxe.ocaml/src',
  'packages/reflaxe.ocaml/std', 'haxe_libraries',
];
const singles = ['packages/hxhx/build.hxml', script, 'scripts/hxhx/shard-bootstrap-ml.sh'];
const env = { ...process.env, ROOT: scratch, ...Object.fromEntries(fields.map(([, variable]) => [variable, 'baseline'])) };
const definitions = ['hash_from_stdin', 'collect_fingerprint_files', 'collect_fingerprint_tree', 'compute_fingerprint'].map(name => {
  const match = source.match(new RegExp(`^${name}\\(\\) \\{[\\s\\S]*?^\\}`, 'm'));
  assert.ok(match, `missing production function: ${name}`);
  return match[0];
}).join('\n');
function bash(text, options = {}) {
  return spawnSync('bash', ['-euo', 'pipefail', '-c', text], {
    env, encoding: 'utf8', timeout: 15000, maxBuffer: 4 * 1024 * 1024, ...options,
  });
}
function successful(result) {
  assert.equal(result.status, 0, result.stderr || String(result.error));
  return result.stdout;
}
function put(relative, text) {
  const file = path.join(scratch, relative);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, text);
}
function filesBelow(relative) {
  if (!fs.existsSync(path.join(scratch, relative))) return [];
  return fs.readdirSync(path.join(scratch, relative), { withFileTypes: true }).flatMap(entry => {
    const name = `${relative}/${entry.name}`;
    return entry.isDirectory() ? filesBelow(name) : entry.isFile() ? [name] : [];
  }).sort((a, b) => Buffer.compare(Buffer.from(a), Buffer.from(b)));
}
function expectedManifest() {
  const files = [
    ...singles.filter(file => fs.existsSync(path.join(scratch, file))),
    ...trees.flatMap(filesBelow),
  ];
  return [
    'schema=v1',
    ...fields.map(([key, variable]) => `${key}=${env[variable]}`),
    ...files.map(file => `file=${file}:${crypto.createHash('sha256').update(fs.readFileSync(path.join(scratch, file))).digest('hex')}`),
    '',
  ].join('\n');
}
function verify() {
  const expected = expectedManifest();
  const manifest = successful(bash(`${definitions}\nhash_from_stdin() { cat; }\ncompute_fingerprint`));
  assert.equal(manifest, expected, 'ordered manifest differs');
  const digest = successful(bash(`${definitions}\ncompute_fingerprint`)).trim();
  assert.equal(digest, crypto.createHash('sha256').update(expected).digest('hex'));
  return digest;
}

// Run both platform checksum choices through the production batching helper.
// The reference invokes that same installed program once per unusual filename.
function verifyChecksumTools() {
  const probes = ['space name', 'back\\slash', 'carriage\rreturn', 'tab\tname', 'é-name'];
  for (const name of probes) put(`probes/${name}`, 'abc');
  const allFiles = [...filesBelow(trees[0]), ...probes.map(name => `probes/${name}`)].map(f => path.join(scratch, f));
  for (const tool of ['sha256sum', 'shasum']) {
    const resolved = bash(`command -v ${tool}`);
    if (resolved.status !== 0) continue;
    const executable = resolved.stdout.trim();
    const bin = path.join(scratch, `tools-${tool}`);
    const counter = path.join(bin, 'calls');
    fs.mkdirSync(bin);
    fs.symlinkSync('/bin/bash', path.join(bin, 'bash'));
    const wrapper = '#!/bin/bash\nset -euo pipefail\n' +
      'bytes=0\nfor arg in "$@"; do bytes=$((bytes + ${#arg} + 1)); done\n' +
      'printf "%s %s\\n" "$#" "$bytes" >>"$CHECKSUM_CALLS"\nexec "$REAL_CHECKSUM" "$@"\n';
    fs.writeFileSync(path.join(bin, tool), wrapper, { mode: 0o755 });
    const toolEnv = { ...env, PATH: bin, REAL_CHECKSUM: executable, CHECKSUM_CALLS: counter, LC_ALL: 'C' };
    const result = spawnSync('/bin/bash', [path.join(repo, helper), scratch], {
      env: toolEnv, input: allFiles.join('\n') + '\n', encoding: 'utf8', timeout: 15000,
    });
    const expected = allFiles.map(file => {
      if (!probes.includes(path.basename(file))) {
        const digest = crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
        return `file=${file.slice(scratch.length + 1)}:${digest}\n`;
      }
      const args = tool === 'shasum' ? ['-a', '256', file] : [file];
      const digest = successful(spawnSync(executable, args, { encoding: 'utf8', timeout: 5000 })).split(/[ \t\n]/)[0];
      return `file=${file.slice(scratch.length + 1)}:${digest}\n`;
    }).join('');
    assert.equal(successful(result), expected, `${tool} digest tokens changed`);
    const calls = fs.readFileSync(counter, 'utf8').trim().split('\n').map(line => line.split(' ').map(Number));
    const flags = tool === 'shasum' ? 2 : 0;
    assert.ok(calls.length > 1 && calls.length < allFiles.length / 10, 'hashing did not batch files');
    assert.equal(calls.reduce((total, [count]) => total + count - flags, 0), allFiles.length);
    assert.ok(calls.every(([count, bytes]) => count - flags <= 128 && bytes <= 16384 + 7));
    // Preserve the empty-list behavior: no accidental read of stdin by sha256sum.
    assert.equal(successful(spawnSync('/bin/bash', [path.join(repo, helper), scratch], {
      env: toolEnv, input: '', encoding: 'utf8', timeout: 1000,
    })), '');
    const missing = spawnSync('/bin/bash', [path.join(repo, helper), scratch], {
      env: toolEnv, input: `${scratch}/missing\n`, encoding: 'utf8', timeout: 1000,
    });
    assert.notEqual(missing.status, 0);
    assert.equal(missing.stdout, '');
  }
}

// Exercise the real skip branch with an isolated fake compiler. The stored
// digest simulates a previous successful build; it is not compiler evidence.
function verifySkipIntegration() {
  for (const file of ['stage0-process-watchdog.sh', 'stage0-process-resources.sh']) {
    put(`scripts/hxhx/${file}`, fs.readFileSync(path.join(repo, 'scripts/hxhx', file)));
  }
  put('bin/haxe', '#!/bin/bash\nif [ "${1:-}" = "--version" ]; then echo 4.3.7; exit 0; fi\necho compile >>"$COMPILE_CAPTURE"\nexit 23\n');
  for (const tool of ['dune', 'ocamlc']) put(`bin/${tool}`, '#!/bin/sh\nexit 0\n');
  for (const tool of ['haxe', 'dune', 'ocamlc']) fs.chmodSync(path.join(scratch, 'bin', tool), 0o755);
  const capture = path.join(scratch, 'compiled');
  const report = path.join(scratch, 'report.json');
  const state = path.join(scratch, 'state');
  const integrationEnv = {
    ...process.env, PATH: `${scratch}/bin:${process.env.PATH}`,
    HAXE_BIN: path.join(scratch, 'bin/haxe'), HAXE_CONNECT: '',
    HXHX_STATE_DIR: state, HXHX_HAXE_SERVER_PREFLIGHT: '0',
    HXHX_BOOTSTRAP_USE_REPO_SERVER: '0', HXHX_BOOTSTRAP_FORCE: '0',
    HXHX_BOOTSTRAP_STAGE0_HAXE_POLICY: 'warn', HXHX_STAGE0_HEARTBEAT: '0',
    HXHX_STAGE0_NATIVE_HAXE_BIN: '', COMPILE_CAPTURE: capture,
  };
  const run = (extra = []) => spawnSync('/bin/bash', [path.join(scratch, script),
    '--incremental', '--no-verify', '--skip-if-unchanged', '--report-json', report, ...extra,
  ], { env: integrationEnv, encoding: 'utf8', timeout: 15000 });
  const first = run();
  assert.equal(first.status, 23, first.stdout + first.stderr);
  const fingerprint = JSON.parse(fs.readFileSync(report, 'utf8')).fingerprint;
  assert.match(fingerprint, /^[a-f0-9]{64}$/);
  fs.mkdirSync(state, { recursive: true });
  fs.mkdirSync(path.join(scratch, 'packages/hxhx/bootstrap_out'), { recursive: true });
  const saved = path.join(state, 'bootstrap_regen_fingerprint.v1');
  fs.writeFileSync(saved, fingerprint + '\n');
  const skipped = run();
  assert.equal(skipped.status, 0, skipped.stdout + skipped.stderr);
  assert.match(skipped.stdout, /Stage0 emit skipped \(fingerprint unchanged\)/);
  assert.equal(fs.readFileSync(capture, 'utf8'), 'compile\n');
  assert.equal(run(['--force']).status, 23);
  put(`${trees[0]}/integration-edit.hx`, 'changed');
  assert.equal(run().status, 23);
  assert.equal(fs.readFileSync(capture, 'utf8'), 'compile\ncompile\ncompile\n');
  assert.equal(fs.readFileSync(saved, 'utf8'), fingerprint + '\n', 'failed compile overwrote the saved fingerprint');
}
try {
  put(helper, fs.readFileSync(path.join(repo, helper)));
  put(script, source);
  put(singles[0], 'build contract\n');
  put(singles[2], 'shard contract\n');
  trees.forEach((tree, index) => put(`${tree}/input-${index}.hx`, `input ${index}\n`));
  put(`${trees[0]}/empty.hx`, '');
  put(`${trees[0]}/space and é.hx`, 'abc');
  // More than one batch, including paths that force the byte limit first.
  for (let i = 0; i < 270; i++) put(`${trees[0]}/${'long'.repeat(35)}-${i}.hx`, `file ${i}`);
  const baseline = verify();
  for (const [, variable] of fields) {
    env[variable] = 'changed';
    assert.notEqual(verify(), baseline, `configuration omitted: ${variable}`);
    env[variable] = 'baseline';
  }
  const changed = `${trees[0]}/input-0.hx`;
  put(changed, 'edited\n');
  const edited = verify();
  assert.notEqual(edited, baseline);
  put(`${trees[1]}/added.hx`, 'added');
  const added = verify();
  assert.notEqual(added, edited);
  fs.renameSync(path.join(scratch, changed), path.join(scratch, trees[0], 'moved.hx'));
  const moved = verify();
  assert.notEqual(moved, added);
  fs.unlinkSync(path.join(scratch, trees[1], 'added.hx'));
  assert.notEqual(verify(), moved);
  verifyChecksumTools();
  verifySkipIntegration();
  // A checksum failure must reach the command-substitution assignment used by regen.
  put('bin/sha256sum', '#!/bin/sh\nprintf "invalid checksum\\n"\n');
  fs.chmodSync(path.join(scratch, 'bin/sha256sum'), 0o755);
  const failure = bash(`${definitions}\ncurrent_fingerprint="$(compute_fingerprint)"\nprintf 'ACCEPTED\\n'`, {
    env: { ...env, PATH: `${scratch}/bin:${process.env.PATH}` },
  });
  assert.notEqual(failure.status, 0);
  assert.ok(!failure.stdout.includes('ACCEPTED'));
  for (const body of [
    'exit 19',
    'printf "%064d  file\\n" 0',
    'printf "%064d  file\\n" 0; exit 19',
    'for file in "$@"; do printf "%064d  file\\n" 0; done; printf "%064d  extra\\n" 0',
  ]) {
    put('bin/sha256sum', `#!/bin/bash\n${body}\n`);
    const result = spawnSync('/bin/bash', [path.join(repo, helper), scratch], {
      env: { ...env, PATH: `${scratch}/bin:${process.env.PATH}` },
      input: `${scratch}/${script}\n${scratch}/${singles[0]}\n`, encoding: 'utf8', timeout: 1000,
    });
    assert.notEqual(result.status, 0, 'accepted failed or incomplete checksum output');
    assert.equal(result.stdout, '');
  }
  console.log(`BOOTSTRAP_FINGERPRINT_FIXTURE:PASS (${fields.length} configuration fields, manifest order, file edits/adds/moves/deletes, both checksum tools, skip/force, failed checksum)`);
} finally {
  fs.rmSync(scratch, { recursive: true, force: true });
}
