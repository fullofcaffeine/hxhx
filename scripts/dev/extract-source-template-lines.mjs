#!/usr/bin/env node
import fs from "node:fs";

function usage() {
  console.error("Usage: extract-source-template-lines.mjs <source> <template> <start-marker> <end-marker> <replacement>");
  process.exit(2);
}

const [sourcePath, templatePath, startMarker, endMarker, replacement] = process.argv.slice(2);
if (!sourcePath || !templatePath || !startMarker || !endMarker || !replacement) usage();

let source = fs.readFileSync(sourcePath, "utf8");
const start = source.indexOf(startMarker);
if (start < 0) throw new Error(`start marker not found: ${startMarker}`);
const end = source.indexOf(endMarker, start + startMarker.length);
if (end < 0) throw new Error(`end marker not found: ${endMarker}`);

const block = source.slice(start, end).replace(/\n$/, "");
const lines = block.split("\n");
const templateLines = [];

for (let i = 0; i < lines.length; i++) {
  let raw = lines[i];
  if (!raw.startsWith("\t\t\t\tlines.push(")) {
    throw new Error(`unexpected line ${i + 1}: ${raw}`);
  }

  let expr = raw.slice("\t\t\t\tlines.push(".length);
  while (!expr.endsWith(");")) {
    i++;
    if (i >= lines.length) throw new Error(`unterminated lines.push expression near line ${i}`);
    expr += "\n" + lines[i].trim();
  }
  expr = expr.slice(0, -2);
  templateLines.push(evalLiteralStringExpression(expr));
}

fs.writeFileSync(templatePath, `${templateLines.join("\n")}\n`);
source = source.slice(0, start) + replacement + source.slice(end);
fs.writeFileSync(sourcePath, source);

function evalLiteralStringExpression(expr) {
  const parts = splitStringLiteralConcat(expr);
  if (parts.length === 0) throw new Error("empty literal expression");
  return parts.map(parseJsonStringLiteral).join("");
}

function splitStringLiteralConcat(expr) {
  const parts = [];
  let start = 0;
  let inString = false;
  let escaped = false;
  for (let i = 0; i < expr.length; i++) {
    const ch = expr[i];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (ch === "\\") {
      escaped = inString;
      continue;
    }
    if (ch === "\"") {
      inString = !inString;
      continue;
    }
    if (!inString && ch === "+") {
      parts.push(expr.slice(start, i).trim());
      start = i + 1;
    }
  }
  parts.push(expr.slice(start).trim());
  return parts.filter(part => part.length > 0);
}

function parseJsonStringLiteral(part) {
  const trimmed = part.trim();
  if (!/^"(?:[^"\\]|\\.)*"$/.test(trimmed)) {
    throw new Error(`unsupported non-literal lines.push expression: ${part}`);
  }
  return JSON.parse(trimmed);
}
