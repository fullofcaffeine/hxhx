#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

function usage() {
  console.log(`Usage: node scripts/hxhx/summarize-stage0-progress.js --input <path> [options]

Summarize reflaxe.ocaml stage0 progress telemetry logs.

Options:
  --input <path>     Progress log path (reflaxe_ocaml_progress.log)
  --top <n>          Number of classes to print in top list (default: 10)
  --json-out <path>  Write machine-readable summary JSON
  --text-out <path>  Write text summary (same content as stdout)
  -h, --help         Show this help
`);
}

function fail(msg) {
  console.error(msg);
  process.exit(2);
}

const args = process.argv.slice(2);
let inputPath = '';
let topN = 10;
let jsonOutPath = '';
let textOutPath = '';

for (let i = 0; i < args.length; i += 1) {
  const arg = args[i];
  if (arg === '--input') {
    i += 1;
    if (i >= args.length) fail('Missing value for --input');
    inputPath = args[i];
  } else if (arg === '--top') {
    i += 1;
    if (i >= args.length) fail('Missing value for --top');
    const parsed = Number(args[i]);
    if (!Number.isInteger(parsed) || parsed <= 0) {
      fail(`Invalid --top value: ${args[i]} (expected positive integer)`);
    }
    topN = parsed;
  } else if (arg === '--json-out') {
    i += 1;
    if (i >= args.length) fail('Missing value for --json-out');
    jsonOutPath = args[i];
  } else if (arg === '--text-out') {
    i += 1;
    if (i >= args.length) fail('Missing value for --text-out');
    textOutPath = args[i];
  } else if (arg === '--help' || arg === '-h') {
    usage();
    process.exit(0);
  } else {
    fail(`Unknown option: ${arg}`);
  }
}

if (!inputPath) fail('Missing required --input <path>');

const summary = {
  schema: 'stage0-progress-summary.v1',
  generated_at: new Date().toISOString(),
  input: inputPath,
  line_count: 0,
  class_end_total_samples: 0,
  class_prepare_total_samples: 0,
  class_totals: [],
  top_classes: [],
  class_prepare_totals: [],
  top_class_prepares: [],
  class_pipeline_totals: [],
  top_class_pipelines: [],
  checkpoints: [],
  missing_input: false,
};

let lines = [];
if (!fs.existsSync(inputPath)) {
  summary.missing_input = true;
} else {
  lines = fs.readFileSync(inputPath, 'utf8').split(/\r?\n/);
  summary.line_count = lines.length;
}

function addSample(rows, name, count, dtMs) {
  const existing = rows.get(name) || {
    name,
    samples: 0,
    total_dt_ms: 0,
    max_dt_ms: 0,
    min_dt_ms: Number.POSITIVE_INFINITY,
    last_count: 0,
  };
  existing.samples += 1;
  existing.total_dt_ms += dtMs;
  existing.max_dt_ms = Math.max(existing.max_dt_ms, dtMs);
  existing.min_dt_ms = Math.min(existing.min_dt_ms, dtMs);
  existing.last_count = Math.max(existing.last_count, count);
  rows.set(name, existing);
}

function sortedTotals(rows) {
  return Array.from(rows.values())
    .map((row) => ({
      name: row.name,
      samples: row.samples,
      total_dt_ms: row.total_dt_ms,
      max_dt_ms: row.max_dt_ms,
      min_dt_ms: Number.isFinite(row.min_dt_ms) ? row.min_dt_ms : 0,
      last_count: row.last_count,
    }))
    .sort((a, b) => {
      if (b.total_dt_ms !== a.total_dt_ms) return b.total_dt_ms - a.total_dt_ms;
      return a.name.localeCompare(b.name);
    });
}

const byClass = new Map();
const byClassPrepare = new Map();
if (!summary.missing_input) {
  for (const line of lines) {
    let match = line.match(/class_end count=(\d+) name=([^ ]+) dt_ms=(\d+)/);
    if (match) {
      const count = Number(match[1]);
      const name = match[2];
      const dtMs = Number(match[3]);
      summary.class_end_total_samples += 1;
      addSample(byClass, name, count, dtMs);
      continue;
    }

    match = line.match(/class_prepare_end count=(\d+) name=([^ ]+) dt_ms=(\d+)/);
    if (match) {
      const count = Number(match[1]);
      const name = match[2];
      const dtMs = Number(match[3]);
      summary.class_prepare_total_samples += 1;
      addSample(byClassPrepare, name, count, dtMs);
      continue;
    }

    match = line.match(/onOutputComplete ([^=]+) dt=(\d+)s/);
    if (match) {
      summary.checkpoints.push({
        phase: match[1].trim(),
        dt_s: Number(match[2]),
      });
    }
  }
}

summary.class_totals = sortedTotals(byClass);
summary.top_classes = summary.class_totals.slice(0, topN);
summary.class_prepare_totals = sortedTotals(byClassPrepare);
summary.top_class_prepares = summary.class_prepare_totals.slice(0, topN);

const pipelineNames = new Set([...byClass.keys(), ...byClassPrepare.keys()]);
summary.class_pipeline_totals = Array.from(pipelineNames)
  .map((name) => {
    const render = byClass.get(name);
    const prepare = byClassPrepare.get(name);
    const renderDtMs = render?.total_dt_ms || 0;
    const prepareDtMs = prepare?.total_dt_ms || 0;
    return {
      name,
      samples: Math.max(render?.samples || 0, prepare?.samples || 0),
      total_dt_ms: renderDtMs + prepareDtMs,
      prepare_dt_ms: prepareDtMs,
      render_dt_ms: renderDtMs,
      last_count: Math.max(render?.last_count || 0, prepare?.last_count || 0),
    };
  })
  .sort((a, b) => {
    if (b.total_dt_ms !== a.total_dt_ms) return b.total_dt_ms - a.total_dt_ms;
    return a.name.localeCompare(b.name);
  });
summary.top_class_pipelines = summary.class_pipeline_totals.slice(0, topN);

const outLines = [];
if (summary.missing_input) {
  outLines.push('top_class_pipeline_total_dt_ms: no-progress-log');
  outLines.push('top_class_total_dt_ms: no-progress-log');
  outLines.push('top_class_prepare_total_dt_ms: no-progress-log');
} else {
  if (summary.top_class_pipelines.length === 0) {
    outLines.push('top_class_pipeline_total_dt_ms: none');
  } else {
    outLines.push('top_class_pipeline_total_dt_ms:');
    for (const row of summary.top_class_pipelines) {
      outLines.push(`  ${row.total_dt_ms}\t${row.name}\t(prepare=${row.prepare_dt_ms} render=${row.render_dt_ms} samples=${row.samples})`);
    }
  }

  if (summary.top_classes.length === 0) {
    outLines.push('top_class_total_dt_ms: none');
  } else {
    outLines.push('top_class_total_dt_ms:');
    for (const row of summary.top_classes) {
      outLines.push(`  ${row.total_dt_ms}\t${row.name}\t(samples=${row.samples} max=${row.max_dt_ms} min=${row.min_dt_ms})`);
    }
  }

  if (summary.top_class_prepares.length === 0) {
    outLines.push('top_class_prepare_total_dt_ms: none');
  } else {
    outLines.push('top_class_prepare_total_dt_ms:');
    for (const row of summary.top_class_prepares) {
      outLines.push(`  ${row.total_dt_ms}\t${row.name}\t(samples=${row.samples} max=${row.max_dt_ms} min=${row.min_dt_ms})`);
    }
  }
}

if (summary.checkpoints.length === 0) {
  outLines.push('output_checkpoints: none');
} else {
  outLines.push('output_checkpoints:');
  for (const row of summary.checkpoints) {
    outLines.push(`  ${row.dt_s}s\t${row.phase}`);
  }
}

const textOutput = `${outLines.join('\n')}\n`;
process.stdout.write(textOutput);

if (textOutPath) {
  fs.mkdirSync(path.dirname(textOutPath), { recursive: true });
  fs.writeFileSync(textOutPath, textOutput, 'utf8');
}
if (jsonOutPath) {
  fs.mkdirSync(path.dirname(jsonOutPath), { recursive: true });
  fs.writeFileSync(jsonOutPath, JSON.stringify(summary, null, 2) + '\n', 'utf8');
}
