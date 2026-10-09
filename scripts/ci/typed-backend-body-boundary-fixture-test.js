#!/usr/bin/env node

// Exercise the real boundary guard with an in-memory renderer mutation. The
// source tree stays untouched, and the guard still reads every ordinary file.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const guardPath = path.join(__dirname, "typed-backend-body-boundary-check.js");
const rendererPath = path.resolve(__dirname, "../../packages/hxhx-core/src/backend/cpp/CppTargetCore.hx");
const guardSource = fs.readFileSync(guardPath, "utf8");

function runGuard(mutateRenderer, targetPath = rendererPath, insertion = "final projection = new CppTypedProgramProjection(program);",
  mutation = "for (module in projection.getModules()) for (cls in module.projection.getClasses()) cls.requireSemanticFacts();") {
  const messages = [];
  const stopped = {};
  let status = 0;
  let mutated = false;
  const observedFs = {
    ...fs,
    readFileSync(file, options) {
      const source = fs.readFileSync(file, options);
      if (!mutateRenderer || path.resolve(file) !== targetPath) return source;
      assert.equal(source.split(insertion).length, 2, "renderer mutation requires one exact insertion point");
      mutated = true;
      return source.replace(insertion, `${insertion}\n${mutation}`);
    },
  };
  try {
    vm.runInNewContext(guardSource, {
      __dirname,
      require(name) { return name === "fs" ? observedFs : require(name); },
      console: {
        log(message) { messages.push(String(message)); },
        error(message) { messages.push(String(message)); },
      },
      process: { exit(code) { status = code; throw stopped; } },
    }, { filename: guardPath, timeout: 10000 });
  } catch (error) {
    if (error !== stopped) throw error;
  }
  if (mutateRenderer) assert.ok(mutated, "the guard must read the mutated renderer");
  return { status, messages: messages.join("\n") };
}

const baseline = runGuard(false);
assert.equal(baseline.status, 0, baseline.messages);
const renderer = runGuard(true);
assert.equal(renderer.status, 1, "direct renderer access must fail the boundary guard");
assert.match(renderer.messages, /backend\/cpp\/CppTargetCore\.hx: observation-only typed class facts/);
const graphRenderer = runGuard(true, rendererPath, "final projection = new CppTypedProgramProjection(program);", "projection.getClassGraph();");
assert.equal(graphRenderer.status, 1, "direct renderer graph access must still fail after storage-plan admission");
assert.match(graphRenderer.messages, /backend\/cpp\/CppTargetCore\.hx: observation-only exact class graph/);
// Extracting a plan does not grant its neighboring emitter access to source facts.
const functionEmitterPath = path.resolve(__dirname, "../../packages/hxhx-core/src/backend/cpp/CppManagedFunctionEmitter.hx");
const functionEmitterSource = fs.readFileSync(functionEmitterPath, "utf8");
const functionEmitterInsertion = "class CppManagedFunctionEmitter {";
assert.ok(functionEmitterSource.includes(functionEmitterInsertion));
for (const [mutation, diagnostic] of [
  ["owner.requireSemanticFacts();", /CppManagedFunctionEmitter\.hx: observation-only typed class facts/],
  ["program.getClassGraph();", /CppManagedFunctionEmitter\.hx: observation-only exact class graph/],
]) {
  const emitter = runGuard(true, functionEmitterPath, functionEmitterInsertion, mutation);
  assert.equal(emitter.status, 1, "the extracted plans must not authorize direct emitter access");
  assert.match(emitter.messages, diagnostic);
}
const enumRenderer = runGuard(
  true,
  path.resolve(__dirname, "../../packages/hxhx-core/src/backend/ocaml/Stage3OcamlEnums.hx"),
  "final owner = byDeclaration.get(projection.getDeclaration());",
);
assert.equal(enumRenderer.status, 1, "enum rendering must not bypass its target plan");
assert.match(enumRenderer.messages, /backend\/ocaml\/Stage3OcamlEnums\.hx: observation-only typed class facts/);
console.log("TYPED_BACKEND_BODY_BOUNDARY_FIXTURE:PASS");
