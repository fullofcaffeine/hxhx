#!/usr/bin/env node
/*
 * Builds the OCaml programs in test/reflaxe_ocaml_hxstring_runtime against the
 * shipped String runtime (HxRuntime, HxArray, HxString) and runs them.
 *
 * - cache_contract.ml checks the cost contract with HxString's work counters
 *   (no timing thresholds) plus edge cases for cached ASCII and ill-formed text.
 * - differential.ml compares every String method with a naive reference
 *   decoder on seeded random input.
 *
 * Requires ocamlfind with the unix package, like the rest of the OCaml gates.
 */
"use strict";

const childProcess = require("child_process");
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..", "..");
const runtimeDir = path.join(root, "packages/reflaxe.ocaml/std/runtime");
const testDir = path.join(root, "test/reflaxe_ocaml_hxstring_runtime");
const workDir = path.join(root, ".tmp", `hxstring-runtime-contract-${process.pid}`);

function run(command, args, cwd) {
  const result = childProcess.spawnSync(command, args, { cwd, encoding: "utf8" });
  if (result.error) throw new Error(`${command} failed to start: ${result.error.message}`);
  return result;
}

const programs = [
  { source: "cache_contract.ml", marker: "HXSTRING_RUNTIME_CONTRACT:PASS", args: [] },
  { source: "differential.ml", marker: "HXSTRING_DIFFERENTIAL:PASS", args: ["7"] },
];

fs.rmSync(workDir, { recursive: true, force: true });
fs.mkdirSync(workDir, { recursive: true });
let failed = false;
try {
  for (const module of ["HxRuntime.ml", "HxArray.ml", "HxString.ml"]) {
    fs.copyFileSync(path.join(runtimeDir, module), path.join(workDir, module));
  }
  for (const program of programs) {
    fs.copyFileSync(path.join(testDir, program.source), path.join(workDir, program.source));
    const exe = program.source.replace(/\.ml$/, ".exe");
    const build = run(
      "ocamlfind",
      ["ocamlopt", "-package", "unix", "-linkpkg", "HxRuntime.ml", "HxArray.ml", "HxString.ml", program.source, "-o", exe],
      workDir
    );
    if (build.status !== 0) {
      process.stderr.write(build.stdout + build.stderr);
      console.error(`[hxstring-runtime-contract] ERROR: ${program.source} did not compile`);
      failed = true;
      continue;
    }
    const result = run(path.join(workDir, exe), program.args, workDir);
    const output = result.stdout + result.stderr;
    const failures = output.split("\n").filter((line) => line.startsWith("FAIL"));
    for (const line of output.split("\n")) {
      if (line.startsWith("info ") || line.startsWith("FAIL") || line.includes(":PASS") || line.includes(":FAIL")) {
        console.log(`[hxstring-runtime-contract] ${program.source}: ${line}`);
      }
    }
    if (result.status !== 0 || !output.includes(program.marker) || failures.length > 0) {
      console.error(`[hxstring-runtime-contract] ERROR: ${program.source} exited ${result.status}`);
      failed = true;
    }
  }
} finally {
  fs.rmSync(workDir, { recursive: true, force: true });
}
if (failed) process.exit(1);
console.log("HXSTRING_RUNTIME_CONTRACT_TEST:PASS");
