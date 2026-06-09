#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

function usage() {
  console.log(`Usage: node scripts/hxhx/summarize-stage0-heartbeat-trace.js --input <path> [options]

Summarize stage0 heartbeat JSONL traces emitted by regenerate-hxhx-bootstrap.sh.

Options:
  --input <path>     Heartbeat trace path (stage0_heartbeat_trace.jsonl)
  --top <n>          Number of peak tree-RSS samples to print (default: 5)
  --json-out <path>  Write machine-readable summary JSON
  --text-out <path>  Write text summary (same content as stdout)
  -h, --help         Show this help
`);
}

function fail(msg) {
  console.error(msg);
  process.exit(2);
}

function readArgs(argv) {
  const parsed = {
    inputPath: '',
    topN: 5,
    jsonOutPath: '',
    textOutPath: '',
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--input') {
      i += 1;
      if (i >= argv.length) fail('Missing value for --input');
      parsed.inputPath = argv[i];
    } else if (arg === '--top') {
      i += 1;
      if (i >= argv.length) fail('Missing value for --top');
      const n = Number(argv[i]);
      if (!Number.isInteger(n) || n <= 0) {
        fail(`Invalid --top value: ${argv[i]} (expected positive integer)`);
      }
      parsed.topN = n;
    } else if (arg === '--json-out') {
      i += 1;
      if (i >= argv.length) fail('Missing value for --json-out');
      parsed.jsonOutPath = argv[i];
    } else if (arg === '--text-out') {
      i += 1;
      if (i >= argv.length) fail('Missing value for --text-out');
      parsed.textOutPath = argv[i];
    } else if (arg === '--help' || arg === '-h') {
      usage();
      process.exit(0);
    } else {
      fail(`Unknown option: ${arg}`);
    }
  }

  if (!parsed.inputPath) fail('Missing required --input <path>');
  return parsed;
}

function toNumber(value) {
  if (value === '' || value === null || value === undefined) return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function sampleFromRaw(raw, index) {
  return {
    index,
    elapsed_s: toNumber(raw.elapsed_s ?? raw.elapsed_sec),
    pid: toNumber(raw.pid),
    focus_pid: toNumber(raw.focus_pid),
    child_pid: toNumber(raw.child_pid),
    rss_mb: toNumber(raw.rss_mb),
    tree_rss_mb: toNumber(raw.tree_rss_mb),
    cpu_pct: toNumber(raw.cpu_pct),
    state: typeof raw.state === 'string' ? raw.state : '',
    log_bytes: toNumber(raw.log_bytes),
  };
}

function snapshotSample(sample) {
  if (!sample) return null;
  return {
    index: sample.index,
    elapsed_s: sample.elapsed_s,
    pid: sample.pid,
    focus_pid: sample.focus_pid,
    child_pid: sample.child_pid,
    rss_mb: sample.rss_mb,
    tree_rss_mb: sample.tree_rss_mb,
    cpu_pct: sample.cpu_pct,
    state: sample.state,
    log_bytes: sample.log_bytes,
  };
}

function sampleSortValue(sample) {
  if (sample.tree_rss_mb !== null) return sample.tree_rss_mb;
  if (sample.rss_mb !== null) return sample.rss_mb;
  return -1;
}

function formatValue(value, suffix = '') {
  return value === null || value === undefined ? 'na' : `${value}${suffix}`;
}

function formatSample(row) {
  return [
    `${formatValue(sampleSortValue(row), 'MB')}`,
    `at=${formatValue(row.elapsed_s, 's')}`,
    `rss=${formatValue(row.rss_mb, 'MB')}`,
    `tree_rss=${formatValue(row.tree_rss_mb, 'MB')}`,
    `focus_pid=${formatValue(row.focus_pid)}`,
    `child_pid=${formatValue(row.child_pid)}`,
    `cpu=${formatValue(row.cpu_pct)}`,
    `state=${row.state || 'na'}`,
    `log_bytes=${formatValue(row.log_bytes)}`,
  ].join(' ');
}

const { inputPath, topN, jsonOutPath, textOutPath } = readArgs(process.argv.slice(2));

const summary = {
  schema: 'stage0-heartbeat-summary.v1',
  generated_at: new Date().toISOString(),
  input: inputPath,
  missing_input: false,
  line_count: 0,
  invalid_line_count: 0,
  sample_count: 0,
  elapsed_seconds: {
    first: null,
    last: null,
    duration: null,
  },
  log_bytes: {
    first: null,
    last: null,
    delta: null,
  },
  peak_rss_mb: null,
  peak_tree_rss_mb: null,
  top_tree_rss_samples: [],
};

let rawLines = [];
if (!fs.existsSync(inputPath)) {
  summary.missing_input = true;
} else {
  rawLines = fs.readFileSync(inputPath, 'utf8').split(/\r?\n/);
  if (rawLines.length > 0 && rawLines[rawLines.length - 1] === '') {
    rawLines.pop();
  }
  summary.line_count = rawLines.length;
}

const samples = [];
if (!summary.missing_input) {
  rawLines.forEach((line, index) => {
    if (line.trim() === '') {
      return;
    }
    try {
      const parsed = JSON.parse(line);
      samples.push(sampleFromRaw(parsed, index + 1));
    } catch (_) {
      summary.invalid_line_count += 1;
    }
  });
}

summary.sample_count = samples.length;

if (samples.length > 0) {
  const elapsed = samples.map((s) => s.elapsed_s).filter((n) => n !== null);
  const logBytes = samples.map((s) => s.log_bytes).filter((n) => n !== null);
  const byRss = samples.filter((s) => s.rss_mb !== null)
    .sort((a, b) => b.rss_mb - a.rss_mb || a.index - b.index);
  const byTreeRss = samples.filter((s) => sampleSortValue(s) >= 0)
    .sort((a, b) => sampleSortValue(b) - sampleSortValue(a) || a.index - b.index);

  if (elapsed.length > 0) {
    summary.elapsed_seconds.first = elapsed[0];
    summary.elapsed_seconds.last = elapsed[elapsed.length - 1];
    summary.elapsed_seconds.duration = summary.elapsed_seconds.last - summary.elapsed_seconds.first;
  }
  if (logBytes.length > 0) {
    summary.log_bytes.first = logBytes[0];
    summary.log_bytes.last = logBytes[logBytes.length - 1];
    summary.log_bytes.delta = summary.log_bytes.last - summary.log_bytes.first;
  }
  summary.peak_rss_mb = snapshotSample(byRss[0]);
  summary.peak_tree_rss_mb = snapshotSample(byTreeRss[0]);
  summary.top_tree_rss_samples = byTreeRss.slice(0, topN).map(snapshotSample);
}

const outLines = [];
if (summary.missing_input) {
  outLines.push('heartbeat_trace_summary: no-heartbeat-trace');
} else if (summary.sample_count === 0) {
  outLines.push(`heartbeat_trace_summary: no-samples invalid_lines=${summary.invalid_line_count}`);
} else {
  outLines.push('heartbeat_trace_summary:');
  outLines.push([
    `  samples=${summary.sample_count}`,
    `invalid_lines=${summary.invalid_line_count}`,
    `elapsed_s=${formatValue(summary.elapsed_seconds.first)}..${formatValue(summary.elapsed_seconds.last)}`,
    `duration_s=${formatValue(summary.elapsed_seconds.duration)}`,
    `log_bytes=${formatValue(summary.log_bytes.first)}..${formatValue(summary.log_bytes.last)}`,
    `log_delta=${formatValue(summary.log_bytes.delta)}`,
  ].join(' '));

  if (summary.peak_rss_mb) {
    outLines.push([
      `  peak_rss_mb=${formatValue(summary.peak_rss_mb.rss_mb)}`,
      `at=${formatValue(summary.peak_rss_mb.elapsed_s, 's')}`,
      `focus_pid=${formatValue(summary.peak_rss_mb.focus_pid)}`,
      `child_pid=${formatValue(summary.peak_rss_mb.child_pid)}`,
      `tree_rss_mb=${formatValue(summary.peak_rss_mb.tree_rss_mb)}`,
    ].join(' '));
  } else {
    outLines.push('  peak_rss_mb=na');
  }

  if (summary.peak_tree_rss_mb) {
    outLines.push([
      `  peak_tree_rss_mb=${formatValue(summary.peak_tree_rss_mb.tree_rss_mb)}`,
      `at=${formatValue(summary.peak_tree_rss_mb.elapsed_s, 's')}`,
      `focus_pid=${formatValue(summary.peak_tree_rss_mb.focus_pid)}`,
      `child_pid=${formatValue(summary.peak_tree_rss_mb.child_pid)}`,
      `rss_mb=${formatValue(summary.peak_tree_rss_mb.rss_mb)}`,
    ].join(' '));
  } else {
    outLines.push('  peak_tree_rss_mb=na');
  }

  outLines.push('heartbeat_top_tree_rss_samples:');
  for (const row of summary.top_tree_rss_samples) {
    outLines.push(`  ${formatSample(row)}`);
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
