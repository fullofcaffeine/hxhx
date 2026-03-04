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
  class_totals: [],
  top_classes: [],
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

const byClass = new Map();
if (!summary.missing_input) {
  for (const line of lines) {
    let match = line.match(/class_end count=(\d+) name=([^ ]+) dt_ms=(\d+)/);
    if (match) {
      const count = Number(match[1]);
      const name = match[2];
      const dtMs = Number(match[3]);
      summary.class_end_total_samples += 1;
      const existing = byClass.get(name) || {
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
      byClass.set(name, existing);
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

summary.class_totals = Array.from(byClass.values())
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
summary.top_classes = summary.class_totals.slice(0, topN);

const outLines = [];
if (summary.missing_input) {
  outLines.push('top_class_total_dt_ms: no-progress-log');
} else if (summary.top_classes.length === 0) {
  outLines.push('top_class_total_dt_ms: none');
} else {
  outLines.push('top_class_total_dt_ms:');
  for (const row of summary.top_classes) {
    outLines.push(`  ${row.total_dt_ms}\t${row.name}\t(samples=${row.samples} max=${row.max_dt_ms} min=${row.min_dt_ms})`);
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
