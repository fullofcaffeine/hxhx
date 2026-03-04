#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

function usage() {
  console.log(`Usage: node scripts/ci/stage0-progress-hotspot-baseline.js [options]

Collect latest stage0 progress summaries and print a hotspot regression table.

Options:
  --root <dir>            Root directory containing run dirs with progress_summary.json
                          (default: .hxhx/profile/stage0-regen)
  --summary <path>        Explicit progress_summary.json path (repeatable)
  --samples <n>           Number of latest summaries to include (default: 5)
  --top <n>               Number of hotspot rows to print (default: 10)
  --min-presence <n>      Require hotspot presence in at least n runs (default: 2)
  --sort <key>            Comparator sort key (median|avg|total|max|presence; default: median)
  --allow-partial         Exit 0 when fewer than --samples files are found
  --json-out <path>       Write compare JSON output
  --text-out <path>       Write regression table output
  -h, --help              Show this help

Behavior:
  - If --summary is provided, those files are used in order provided.
  - Otherwise script scans --root recursively for progress_summary.json and picks latest N by mtime.
  - Baseline = oldest selected run; latest = newest selected run.
`);
}

function fail(msg, code = 2) {
  console.error(msg);
  process.exit(code);
}

function parsePositiveInt(name, value) {
  const n = Number(value);
  if (!Number.isInteger(n) || n <= 0) {
    fail(`Invalid ${name}: ${value} (expected positive integer)`);
  }
  return n;
}

function formatPct(value) {
  if (!Number.isFinite(value)) return 'na';
  const sign = value > 0 ? '+' : '';
  return `${sign}${value.toFixed(2)}%`;
}

function formatNum(value) {
  if (!Number.isFinite(value)) return 'na';
  return value.toFixed(1);
}

const args = process.argv.slice(2);
const explicitSummaries = [];
let rootDir = '.hxhx/profile/stage0-regen';
let samples = 5;
let topN = 10;
let minPresence = 2;
let sortKey = 'median';
let allowPartial = false;
let jsonOutPath = '';
let textOutPath = '';

for (let i = 0; i < args.length; i += 1) {
  const arg = args[i];
  if (arg === '--root') {
    i += 1;
    if (i >= args.length) fail('Missing value for --root');
    rootDir = args[i];
  } else if (arg === '--summary') {
    i += 1;
    if (i >= args.length) fail('Missing value for --summary');
    explicitSummaries.push(args[i]);
  } else if (arg === '--samples') {
    i += 1;
    if (i >= args.length) fail('Missing value for --samples');
    samples = parsePositiveInt('--samples', args[i]);
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
  } else if (arg === '--allow-partial') {
    allowPartial = true;
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

if (samples < 2) {
  fail('--samples must be >= 2 for baseline/latest regression comparison');
}
if (minPresence > samples && explicitSummaries.length === 0) {
  fail(`Invalid --min-presence: ${minPresence} exceeds requested samples ${samples}`);
}

function walkSummaries(dir) {
  const out = [];
  if (!fs.existsSync(dir)) return out;
  const stack = [dir];
  while (stack.length > 0) {
    const current = stack.pop();
    let entries = [];
    try {
      entries = fs.readdirSync(current, { withFileTypes: true });
    } catch (_) {
      continue;
    }
    for (const entry of entries) {
      const full = path.join(current, entry.name);
      if (entry.isDirectory()) {
        stack.push(full);
      } else if (entry.isFile() && entry.name === 'progress_summary.json') {
        try {
          const st = fs.statSync(full);
          out.push({ path: full, mtimeMs: st.mtimeMs });
        } catch (_) {
          // skip unreadable
        }
      }
    }
  }
  return out;
}

let selected = [];
if (explicitSummaries.length > 0) {
  for (const p of explicitSummaries) {
    if (!fs.existsSync(p)) fail(`Missing summary file: ${p}`);
    const st = fs.statSync(p);
    selected.push({ path: p, mtimeMs: st.mtimeMs });
  }
} else {
  const found = walkSummaries(rootDir)
    .sort((a, b) => b.mtimeMs - a.mtimeMs)
    .slice(0, samples)
    .sort((a, b) => a.mtimeMs - b.mtimeMs); // oldest -> newest
  selected = found;
}

if (selected.length < 2) {
  fail(`Need at least 2 summaries, found ${selected.length}` + (allowPartial ? ' (allow_partial active)' : ''), allowPartial ? 0 : 3);
}
if (selected.length < samples && !allowPartial && explicitSummaries.length === 0) {
  fail(`Only found ${selected.length} summaries (requested ${samples}).`, 4);
}
if (selected.length < minPresence) {
  fail(`min_presence=${minPresence} exceeds available runs=${selected.length}`);
}

const compareScript = path.join(__dirname, '..', 'hxhx', 'compare-stage0-progress-summaries.js');
if (!fs.existsSync(compareScript)) {
  fail(`Missing compare script: ${compareScript}`);
}

const compareJsonPath = jsonOutPath || path.join(process.cwd(), '.hxhx', 'profile', 'stage0-regen', 'compare.latest.json');
fs.mkdirSync(path.dirname(compareJsonPath), { recursive: true });

const compareArgs = [compareScript];
for (const s of selected) {
  compareArgs.push('--summary', s.path);
}
compareArgs.push('--top', String(topN));
compareArgs.push('--min-presence', String(minPresence));
compareArgs.push('--sort', sortKey);
compareArgs.push('--json-out', compareJsonPath);

const cp = spawnSync(process.execPath, compareArgs, { encoding: 'utf8' });
if (cp.status !== 0) {
  process.stdout.write(cp.stdout || '');
  process.stderr.write(cp.stderr || '');
  fail('Failed to run compare-stage0-progress-summaries.js', 5);
}

let compare;
try {
  compare = JSON.parse(fs.readFileSync(compareJsonPath, 'utf8'));
} catch (err) {
  fail(`Failed to parse compare JSON: ${compareJsonPath} (${err.message})`, 6);
}

const baselinePath = selected[0].path;
const latestPath = selected[selected.length - 1].path;
const baseline = JSON.parse(fs.readFileSync(baselinePath, 'utf8'));
const latest = JSON.parse(fs.readFileSync(latestPath, 'utf8'));

const baselineMap = new Map((baseline.class_totals || []).map((row) => [row.name, Number(row.total_dt_ms)]));
const latestMap = new Map((latest.class_totals || []).map((row) => [row.name, Number(row.total_dt_ms)]));

const lines = [];
lines.push(`stage0_hotspot_regression runs=${selected.length} requested=${samples} min_presence=${minPresence} sort=${sortKey}`);
lines.push(`baseline=${baselinePath}`);
lines.push(`latest=${latestPath}`);
lines.push(`compare_json=${compareJsonPath}`);

const rows = (compare.top_classes || []).map((row) => {
  const name = row.name;
  const base = baselineMap.get(name);
  const late = latestMap.get(name);
  const deltaMs = Number.isFinite(base) && Number.isFinite(late) ? late - base : NaN;
  const deltaPct = Number.isFinite(base) && base !== 0 && Number.isFinite(late)
    ? ((late - base) / base) * 100
    : NaN;
  return {
    name,
    baseline_ms: base,
    latest_ms: late,
    delta_ms: deltaMs,
    delta_pct: deltaPct,
    median_ms: Number(row.median_dt_ms),
    avg_ms: Number(row.avg_dt_ms),
    presence: row.presence,
    run_count: row.run_count,
  };
});

if (rows.length === 0) {
  lines.push('hotspot_regression: none');
} else {
  lines.push('hotspot_regression:');
  for (const r of rows) {
    const deltaMsStr = Number.isFinite(r.delta_ms) ? (r.delta_ms > 0 ? `+${Math.round(r.delta_ms)}` : `${Math.round(r.delta_ms)}`) : 'na';
    lines.push(
      `  ${Math.round(r.median_ms)}\t${r.name}\tbase=${formatNum(r.baseline_ms)} latest=${formatNum(r.latest_ms)} delta_ms=${deltaMsStr} delta_pct=${formatPct(r.delta_pct)} presence=${r.presence}/${r.run_count}`
    );
  }
}

const text = `${lines.join('\n')}\n`;
process.stdout.write(text);
if (textOutPath) {
  fs.mkdirSync(path.dirname(textOutPath), { recursive: true });
  fs.writeFileSync(textOutPath, text, 'utf8');
}
