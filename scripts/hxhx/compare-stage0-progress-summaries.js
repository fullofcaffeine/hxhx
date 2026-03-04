#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

function usage() {
  console.log(`Usage: node scripts/hxhx/compare-stage0-progress-summaries.js [options]

Compare multiple stage0 progress summary JSON files and rank stable hotspots.

Options:
  --summary <path>       Path to one progress_summary.json (repeatable)
  --summary-dir <dir>    Directory containing progress_summary.json (repeatable)
  --top <n>              Number of rows per section (default: 10)
  --min-presence <n>     Require class/checkpoint to appear in >=n runs (default: 1)
  --sort <key>           Class sort key: median|avg|total|max|presence (default: median)
  --json-out <path>      Write machine-readable comparison JSON
  --text-out <path>      Write text summary to file
  -h, --help             Show this help
`);
}

function fail(msg) {
  console.error(msg);
  process.exit(2);
}

function parsePositiveInt(name, value) {
  const n = Number(value);
  if (!Number.isInteger(n) || n <= 0) {
    fail(`Invalid ${name}: ${value} (expected positive integer)`);
  }
  return n;
}

function avg(values) {
  if (values.length === 0) return 0;
  return values.reduce((a, b) => a + b, 0) / values.length;
}

function median(values) {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  if (sorted.length % 2 === 1) return sorted[mid];
  return (sorted[mid - 1] + sorted[mid]) / 2;
}

function stats(values) {
  if (values.length === 0) {
    return { avg: 0, median: 0, min: 0, max: 0, total: 0 };
  }
  return {
    avg: avg(values),
    median: median(values),
    min: Math.min(...values),
    max: Math.max(...values),
    total: values.reduce((a, b) => a + b, 0),
  };
}

const args = process.argv.slice(2);
const summaryPaths = [];
let topN = 10;
let minPresence = 1;
let sortKey = 'median';
let jsonOutPath = '';
let textOutPath = '';

for (let i = 0; i < args.length; i += 1) {
  const arg = args[i];
  if (arg === '--summary') {
    i += 1;
    if (i >= args.length) fail('Missing value for --summary');
    summaryPaths.push(args[i]);
  } else if (arg === '--summary-dir') {
    i += 1;
    if (i >= args.length) fail('Missing value for --summary-dir');
    summaryPaths.push(path.join(args[i], 'progress_summary.json'));
  } else if (arg === '--top') {
    i += 1;
    if (i >= args.length) fail('Missing value for --top');
    topN = parsePositiveInt('--top', args[i]);
  } else if (arg === '--min-presence') {
    i += 1;
    if (i >= args.length) fail('Missing value for --min-presence');
    minPresence = parsePositiveInt('--min-presence', args[i]);
  } else if (arg === '--sort') {
    i += 1;
    if (i >= args.length) fail('Missing value for --sort');
    sortKey = args[i];
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

const sortKeys = new Set(['median', 'avg', 'total', 'max', 'presence']);
if (!sortKeys.has(sortKey)) {
  fail(`Invalid --sort value: ${sortKey} (expected median|avg|total|max|presence)`);
}

if (summaryPaths.length === 0) {
  fail('Provide at least one --summary or --summary-dir');
}
if (minPresence > summaryPaths.length) {
  fail(`Invalid --min-presence: ${minPresence} exceeds run count ${summaryPaths.length}`);
}

const runs = [];
for (const p of summaryPaths) {
  if (!fs.existsSync(p)) {
    fail(`Missing summary file: ${p}`);
  }
  let parsed;
  try {
    parsed = JSON.parse(fs.readFileSync(p, 'utf8'));
  } catch (err) {
    fail(`Invalid JSON summary: ${p} (${err.message})`);
  }
  if (typeof parsed.schema !== 'string' || !parsed.schema.startsWith('stage0-progress-summary.')) {
    fail(`Unexpected summary schema in ${p}: ${parsed.schema}`);
  }
  runs.push({ path: p, summary: parsed });
}

const classByName = new Map();
const checkpointByPhase = new Map();

for (const run of runs) {
  const classRows = Array.isArray(run.summary.class_totals) ? run.summary.class_totals : [];
  const checkpoints = Array.isArray(run.summary.checkpoints) ? run.summary.checkpoints : [];

  for (const row of classRows) {
    if (!row || typeof row.name !== 'string') continue;
    const value = Number(row.total_dt_ms);
    if (!Number.isFinite(value)) continue;
    const existing = classByName.get(row.name) || [];
    existing.push(value);
    classByName.set(row.name, existing);
  }

  for (const row of checkpoints) {
    if (!row || typeof row.phase !== 'string') continue;
    const value = Number(row.dt_s);
    if (!Number.isFinite(value)) continue;
    const existing = checkpointByPhase.get(row.phase) || [];
    existing.push(value);
    checkpointByPhase.set(row.phase, existing);
  }
}

function buildRows(map, valueFieldName) {
  const out = [];
  for (const [name, values] of map.entries()) {
    const presence = values.length;
    if (presence < minPresence) continue;
    const s = stats(values);
    out.push({
      name,
      presence,
      run_count: runs.length,
      coverage_pct: (presence / runs.length) * 100,
      values,
      [`avg_${valueFieldName}`]: s.avg,
      [`median_${valueFieldName}`]: s.median,
      [`min_${valueFieldName}`]: s.min,
      [`max_${valueFieldName}`]: s.max,
      [`total_${valueFieldName}`]: s.total,
    });
  }
  return out;
}

const classRows = buildRows(classByName, 'dt_ms');
const checkpointRows = buildRows(checkpointByPhase, 'dt_s');

function classSortMetric(row) {
  if (sortKey === 'presence') return row.presence;
  if (sortKey === 'avg') return row.avg_dt_ms;
  if (sortKey === 'total') return row.total_dt_ms;
  if (sortKey === 'max') return row.max_dt_ms;
  return row.median_dt_ms;
}

classRows.sort((a, b) => {
  const metricDiff = classSortMetric(b) - classSortMetric(a);
  if (metricDiff !== 0) return metricDiff;
  const coverageDiff = b.coverage_pct - a.coverage_pct;
  if (coverageDiff !== 0) return coverageDiff;
  return a.name.localeCompare(b.name);
});

checkpointRows.sort((a, b) => {
  const metricDiff = b.median_dt_s - a.median_dt_s;
  if (metricDiff !== 0) return metricDiff;
  const coverageDiff = b.coverage_pct - a.coverage_pct;
  if (coverageDiff !== 0) return coverageDiff;
  return a.name.localeCompare(b.name);
});

const topClasses = classRows.slice(0, topN);
const topCheckpoints = checkpointRows.slice(0, topN);

const result = {
  schema: 'stage0-progress-compare.v1',
  generated_at: new Date().toISOString(),
  run_count: runs.length,
  min_presence: minPresence,
  class_sort_key: sortKey,
  runs: runs.map((r) => ({ path: r.path, input: r.summary.input || '', generated_at: r.summary.generated_at || '' })),
  classes: classRows,
  checkpoints: checkpointRows,
  top_classes: topClasses,
  top_checkpoints: topCheckpoints,
};

const lines = [];
lines.push(`runs=${runs.length} min_presence=${minPresence} class_sort=${sortKey}`);
if (topClasses.length === 0) {
  lines.push('top_class_hotspots: none');
} else {
  lines.push('top_class_hotspots:');
  for (const row of topClasses) {
    lines.push(
      `  ${Math.round(row.median_dt_ms)}\t${row.name}\t(presence=${row.presence}/${row.run_count} avg=${row.avg_dt_ms.toFixed(1)} max=${row.max_dt_ms} min=${row.min_dt_ms})`
    );
  }
}
if (topCheckpoints.length === 0) {
  lines.push('top_checkpoints: none');
} else {
  lines.push('top_checkpoints:');
  for (const row of topCheckpoints) {
    lines.push(
      `  ${row.median_dt_s.toFixed(1)}s\t${row.name}\t(presence=${row.presence}/${row.run_count} avg=${row.avg_dt_s.toFixed(1)}s max=${row.max_dt_s}s)`
    );
  }
}

const text = `${lines.join('\n')}\n`;
process.stdout.write(text);

if (textOutPath) {
  fs.mkdirSync(path.dirname(textOutPath), { recursive: true });
  fs.writeFileSync(textOutPath, text, 'utf8');
}
if (jsonOutPath) {
  fs.mkdirSync(path.dirname(jsonOutPath), { recursive: true });
  fs.writeFileSync(jsonOutPath, JSON.stringify(result, null, 2) + '\n', 'utf8');
}
