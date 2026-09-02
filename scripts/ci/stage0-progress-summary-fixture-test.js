#!/usr/bin/env node

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const root = path.resolve(__dirname, '..', '..');
const helper = path.join(root, 'scripts', 'hxhx', 'summarize-stage0-progress.js');
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'hxhx-stage0-progress-summary-'));

try {
  const input = path.join(temp, 'progress.log');
  const output = path.join(temp, 'summary.json');
  fs.writeFileSync(
    input,
    [
      'reflaxe.ocaml: class_prepare_end count=1 name=FastRenderSlowPrepare dt_ms=900',
      'reflaxe.ocaml: class_begin count=1 name=FastRenderSlowPrepare',
      'reflaxe.ocaml: class_end count=1 name=FastRenderSlowPrepare dt_ms=100 chars=10',
      'reflaxe.ocaml: class_prepare_end count=2 name=SlowRender dt_ms=10',
      'reflaxe.ocaml: class_begin count=2 name=SlowRender',
      'reflaxe.ocaml: class_end count=2 name=SlowRender dt_ms=500 chars=10',
      'reflaxe.ocaml: function_prepare_begin count=1 class=FastRenderSlowPrepare field=compile root=ordinary function_id=FastRenderSlowPrepare.compile args=1 body=present',
      'reflaxe.ocaml: function_prepare_end count=1 class=FastRenderSlowPrepare field=compile root=ordinary function_id=FastRenderSlowPrepare.compile result=sealed dt_ms=120 phase_binding_ms=5 phase_calls_and_scalars_ms=90 phase_finalize_ms=2',
      'reflaxe.ocaml: function_prepare_begin count=2 class=FastRenderSlowPrepare field=interrupted root=ordinary function_id=FastRenderSlowPrepare.interrupted args=0 body=present',
      'reflaxe.ocaml: function_prepare_begin count=3 class=FastRenderSlowPrepare field=rejected root=ordinary function_id=FastRenderSlowPrepare.rejected args=0 body=present',
      'reflaxe.ocaml: function_prepare_end count=3 class=FastRenderSlowPrepare field=rejected root=ordinary function_id=FastRenderSlowPrepare.rejected result=failed dt_ms=20 phase_binding_ms=2 phase_interrupted_ms=18',
      '',
    ].join('\n'),
    'utf8'
  );

  const result = spawnSync(process.execPath, [helper, '--input', input, '--top', '2', '--json-out', output], {
    cwd: root,
    encoding: 'utf8',
  });
  assert.strictEqual(result.status, 0, result.stderr || result.stdout);

  const summary = JSON.parse(fs.readFileSync(output, 'utf8'));
  assert.strictEqual(summary.class_prepare_total_samples, 2);
  assert.strictEqual(summary.class_end_total_samples, 2);
  assert.strictEqual(summary.schema, 'stage0-progress-summary.v2');
  assert.deepStrictEqual(
    summary.top_class_pipelines.map((row) => [row.name, row.total_dt_ms, row.prepare_dt_ms, row.render_dt_ms]),
    [
      ['FastRenderSlowPrepare', 1000, 900, 100],
      ['SlowRender', 510, 10, 500],
    ]
  );
  assert.strictEqual(summary.top_classes[0].name, 'SlowRender');
  assert.strictEqual(summary.function_prepare_total_samples, 2);
  assert.strictEqual(summary.function_prepare_failed_samples, 1);
  assert.strictEqual(summary.top_function_prepares[0].name, 'FastRenderSlowPrepare.compile');
  assert.strictEqual(summary.top_function_prepares[0].phase_totals_ms.calls_and_scalars, 90);
  assert.deepStrictEqual(summary.incomplete_function_prepares, [
    {
      count: 2,
      class_name: 'FastRenderSlowPrepare',
      field_name: 'interrupted',
      root: 'ordinary',
      function_id: 'FastRenderSlowPrepare.interrupted',
    },
  ]);
  assert.match(result.stdout, /top_class_pipeline_total_dt_ms:/);
  assert.match(result.stdout, /top_class_prepare_total_dt_ms:/);
  assert.match(result.stdout, /top_function_prepare_total_dt_ms:/);
  assert.match(result.stdout, /incomplete_function_prepares:/);
  assert.match(result.stdout, /FastRenderSlowPrepare\.interrupted/);

  console.log('STAGE0_PROGRESS_SUMMARY_FIXTURE:PASS');
} finally {
  fs.rmSync(temp, { recursive: true, force: true });
}
