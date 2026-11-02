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
 *
 * The tables are derived from the Unicode Character Database, so the output
 * starts with the Unicode License V3 copyright and permission notice
 * (https://www.unicode.org/license.txt). That license requires the notice to
 * appear with every copy, and HxString.ml is copied into every generated
 * OCaml program.
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

const UNICODE_LICENSE = `UNICODE LICENSE V3

COPYRIGHT AND PERMISSION NOTICE

Copyright © 1991-2026 Unicode, Inc.

NOTICE TO USER: Carefully read the following legal agreement. BY
DOWNLOADING, INSTALLING, COPYING OR OTHERWISE USING DATA FILES, AND/OR
SOFTWARE, YOU UNEQUIVOCALLY ACCEPT, AND AGREE TO BE BOUND BY, ALL OF THE
TERMS AND CONDITIONS OF THIS AGREEMENT. IF YOU DO NOT AGREE, DO NOT
DOWNLOAD, INSTALL, COPY, DISTRIBUTE OR USE THE DATA FILES OR SOFTWARE.

Permission is hereby granted, free of charge, to any person obtaining a
copy of data files and any associated documentation (the "Data Files") or
software and any associated documentation (the "Software") to deal in the
Data Files or Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, and/or sell
copies of the Data Files or Software, and to permit persons to whom the
Data Files or Software are furnished to do so, provided that either (a)
this copyright and permission notice appear with all copies of the Data
Files or Software, or (b) this copyright and permission notice appear in
associated Documentation.

THE DATA FILES AND SOFTWARE ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY
KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF
THIRD PARTY RIGHTS.

IN NO EVENT SHALL THE COPYRIGHT HOLDER OR HOLDERS INCLUDED IN THIS NOTICE
BE LIABLE FOR ANY CLAIM, OR ANY SPECIAL INDIRECT OR CONSEQUENTIAL DAMAGES,
OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS,
WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION,
ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THE DATA
FILES OR SOFTWARE.

Except as contained in this notice, the name of a copyright holder shall
not be used in advertising or otherwise to promote the sale, use or other
dealings in these Data Files or Software without prior written
authorization of the copyright holder.`;

const upperRuns = requireDisjoint("upper_runs", runs(upper));
const lowerRuns = requireDisjoint("lower_runs", runs(lower));
const changed = new Set([...upper.keys(), ...lower.keys()].filter((c) => upper.get(c) !== c || lower.get(c) !== c));
console.log("(* BEGIN generated case tables: scripts/reflaxe-ocaml/generate-hxstring-case-table.js *)");
console.log("(* The case tables below are derived from the Unicode Character Database");
console.log("   (UnicodeData.txt, Unicode 8.0.0, https://www.unicode.org/Public/8.0.0/ucd/)");
console.log("   and are distributed under the following notice.");
console.log("");
console.log(UNICODE_LICENSE.split("\n").map((line) => (line === "" ? "" : "   " + line)).join("\n") + " *)");
console.log(`(* ${changed.size} code points change case; ${upperRuns.length} upper and ${lowerRuns.length} lower runs. *)`);
console.log(render("upper_runs", upperRuns));
console.log("");
console.log(render("lower_runs", lowerRuns));
console.log("(* END generated case tables *)");
