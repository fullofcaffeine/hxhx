#!/usr/bin/env node
/*
 * Prints the OCaml case-mapping tables embedded in
 * packages/reflaxe.ocaml/std/runtime/HxString.ml.
 *
 * Upstream Haxe 4.3.7 eval changes the case of 2224 code points, each to one
 * other code point. That set is the Unicode 8.0 simple case mapping for the
 * Basic Multilingual Plane (U+0000..U+FFFF), with one difference: the four
 * Latin digraph triples (U+01C4..U+01CC, U+01F1..U+01F3) upper-case to their
 * title-case member. Supplementary-plane letters keep their case.
 *
 * Usage:
 *   curl -o .tmp/UnicodeData-8.0.0.txt https://www.unicode.org/Public/8.0.0/ucd/UnicodeData.txt
 *   node scripts/reflaxe-ocaml/generate-hxstring-case-table.js .tmp/UnicodeData-8.0.0.txt
 *
 * Paste the output between the "BEGIN/END generated case tables" markers.
 * test/fixtures/stage3_string_unicode compares a checksum over every code
 * point with upstream, so a wrong table fails that fixture.
 */
"use strict";

const fs = require("fs");

const input = process.argv[2];
if (!input) {
  console.error("usage: generate-hxstring-case-table.js <UnicodeData-8.0.0.txt>");
  process.exit(2);
}

const upper = new Map();
const lower = new Map();
for (const line of fs.readFileSync(input, "utf8").split("\n")) {
  if (line.trim() === "") continue;
  const fields = line.split(";");
  const code = parseInt(fields[0], 16);
  if (code > 0xffff) continue;
  if (fields[12]) upper.set(code, parseInt(fields[12], 16));
  if (fields[13]) lower.set(code, parseInt(fields[13], 16));
}

// Digraphs: eval upper-cases every member of each triple to the title-case form.
for (const [capital, title, small] of [
  [0x1c4, 0x1c5, 0x1c6],
  [0x1c7, 0x1c8, 0x1c9],
  [0x1ca, 0x1cb, 0x1cc],
  [0x1f1, 0x1f2, 0x1f3],
]) {
  upper.set(capital, title);
  upper.set(title, title);
  upper.set(small, title);
}

/*
 * Groups mappings into (first, last, step, delta) runs: every code point
 * first + k * step up to last maps to itself plus delta. Step 2 covers the
 * alternating capital/small pairs of Latin Extended and similar blocks.
 */
function runs(mapping) {
  const codes = [...mapping.keys()].filter((code) => mapping.get(code) !== code).sort((a, b) => a - b);
  const out = [];
  let index = 0;
  while (index < codes.length) {
    const first = codes[index];
    const delta = mapping.get(first) - first;
    let best = { last: first, step: 1, next: index + 1 };
    for (const step of [1, 2]) {
      let cursor = index;
      let last = first;
      while (
        cursor + 1 < codes.length &&
        codes[cursor + 1] === last + step &&
        mapping.get(codes[cursor + 1]) - codes[cursor + 1] === delta
      ) {
        cursor += 1;
        last = codes[cursor];
      }
      if (cursor + 1 > best.next) best = { last, step, next: cursor + 1 };
    }
    out.push([first, best.last, best.last === first ? 1 : best.step, delta]);
    index = best.next;
  }
  return out;
}

/* The runtime binary-searches runs by first code point, so spans must not overlap. */
function requireDisjoint(name, table) {
  for (let i = 1; i < table.length; i += 1) {
    if (table[i][0] <= table[i - 1][1]) {
      throw new Error(`${name}: run at 0x${table[i][0].toString(16)} overlaps the previous run`);
    }
  }
  return table;
}

function render(name, table) {
  const rows = [];
  for (let i = 0; i < table.length; i += 4) {
    rows.push(
      "  " +
        table
          .slice(i, i + 4)
          .map(([first, last, step, delta]) => `0x${first.toString(16)}; 0x${last.toString(16)}; ${step}; ${delta};`)
          .join(" ")
    );
  }
  return `let ${name} : int array = [|\n${rows.join("\n")}\n|]`;
}

const upperRuns = requireDisjoint("upper_runs", runs(upper));
const lowerRuns = requireDisjoint("lower_runs", runs(lower));
const changed = new Set([...upper.keys(), ...lower.keys()].filter((c) => upper.get(c) !== c || lower.get(c) !== c));
console.log("(* BEGIN generated case tables: scripts/reflaxe-ocaml/generate-hxstring-case-table.js *)");
console.log(`(* ${changed.size} code points change case; ${upperRuns.length} upper and ${lowerRuns.length} lower runs. *)`);
console.log(render("upper_runs", upperRuns));
console.log("");
console.log(render("lower_runs", lowerRuns));
console.log("(* END generated case tables *)");
