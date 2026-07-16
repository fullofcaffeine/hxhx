#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const repoRoot = path.resolve(__dirname, "../..");
const roots = [
  path.join(repoRoot, "packages/hxhx-core/src/backend"),
  path.join(repoRoot, "packages/hxhx-core/src/EmitterStage.hx"),
  path.join(repoRoot, "packages/hxhx-core/src/TypedBodySource.hx"),
];

function haxeFiles(entry) {
  const stat = fs.statSync(entry);
  if (stat.isFile()) return entry.endsWith(".hx") ? [entry] : [];
  const out = [];
  for (const name of fs.readdirSync(entry).sort()) {
    out.push(...haxeFiles(path.join(entry, name)));
  }
  return out;
}

const files = roots.flatMap(haxeFiles);
const failures = [];

for (const file of files) {
  const source = fs.readFileSync(file, "utf8");
  const relative = path.relative(repoRoot, file);

  const rawBodyRead = /\bHxFunctionDecl\.getBodyText\s*\(|\.bodyText\b/g;
  for (const match of source.matchAll(rawBodyRead)) {
    failures.push(`${relative}:${source.slice(0, match.index).split("\n").length}: parsed raw function-body read`);
  }

  const direct = /\b[A-Za-z_][A-Za-z0-9_]*\.getParsed\(\)\.getDecl\(\)/g;
  for (const match of source.matchAll(direct)) {
    failures.push(`${relative}:${source.slice(0, match.index).split("\n").length}: direct parsed declaration read`);
  }

  const alias = /\b(?:final|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*[A-Za-z_][A-Za-z0-9_]*\.getParsed\(\)\s*;/g;
  for (const match of source.matchAll(alias)) {
    const aliasName = match[1];
    const remainder = source.slice(match.index + match[0].length);
    const declarationRead = new RegExp(`\\b${aliasName}\\.getDecl\\(\\)`);
    if (declarationRead.test(remainder)) {
      failures.push(`${relative}:${source.slice(0, match.index).split("\n").length}: parsed alias \`${aliasName}\` reaches getDecl()`);
    }
  }
}

if (failures.length > 0) {
  console.error("Typed backend body boundary failed.");
  console.error("Backends must obtain declarations/function bodies from TypedModule.getBackendDeclaration().");
  console.error("TypedModule.getParsed() remains available only for file/source provenance.");
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log(`TYPED_BACKEND_BODY_BOUNDARY:PASS files=${files.length}`);
