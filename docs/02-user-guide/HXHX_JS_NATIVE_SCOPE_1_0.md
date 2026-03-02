# HXHX JS-native Scoped 1.0 Matrix

This is the canonical scope document for `hxhx` linked JS support in the 1.0 track.

- Delegated JS lane: `--target js-compat` (stage0 `haxe` delegation).
- Linked JS lane: `--target js` (Stage3 builtin backend, non-delegating emit path).

If this matrix and another doc disagree, this matrix wins.

## Scope status

| Area | Status | Evidence |
| --- | --- | --- |
| Linked backend selection (`--target js`, `-js/--js` routing, strict CLI `--js`) | In scope | `scripts/test-hxhx-targets.sh`, `npm run test:m14:js-target-core-wiring` |
| Single-file JS emit + `stage3=ok`/artifact/run markers | In scope | `scripts/test-hxhx-targets.sh` |
| Statement `try/catch` + `throw` / rethrow lowering | Partial (compile/run smoke) | `npm run test:m14:js-stmt-try-throw`, `scripts/test-hxhx-targets.sh` (runtime parity remains a known gap) |
| Ordered multi-catch dispatch lowering (`Int`, `Float`, `Bool`, `String`, `Array`, `Dynamic`) | Partial (compile/run smoke) | `npm run test:m14:js-stmt-multi-catch`, `scripts/test-hxhx-targets.sh` (runtime parity remains a known gap) |
| Switch expression lowering | In scope | `npm run test:m14:js-expr-switch`, `scripts/test-hxhx-targets.sh`, `npm run test:upstream:js-oracle-smoke` |
| Array comprehension lowering | In scope | `npm run test:m14:js-expr-array-comprehension`, `scripts/test-hxhx-targets.sh`, `npm run test:upstream:js-oracle-smoke` |
| Range expression lowering | In scope | `npm run test:m14:js-expr-range`, `scripts/test-hxhx-targets.sh`, `npm run test:upstream:js-oracle-smoke` |
| `new Array(...)` expression lowering | In scope | `npm run test:m14:js-expr-new-array`, `scripts/test-hxhx-targets.sh`, `npm run test:upstream:js-oracle-smoke` |
| Enum-tag switch lowering | In scope | `scripts/test-hxhx-targets.sh` |
| Basic `Type` reflection helpers (`resolveClass`, `getClassName`, `enumConstructor`, `enumIndex`, `enumParameters`) | Out of scope (known gap) | Current JS-native lane does not guarantee full `Type` helper parity; tracked under JS semantic-gap tasks |
| Class construction via `new SomeClass(...)` (known class types) | In scope | `scripts/test-hxhx-targets.sh` compiles `JsNativeClassInstanceMain` and asserts emitted constructor call |
| Unknown/opaque constructor types in expression lowering | Out of scope (fail-fast) | `npm run test:m14:js-expr-new-array` and `npm run test:m14:js-unsupported-diagnostics` assert deterministic marker `[js-native:unsupported_expr] kind=ENew detail=<type>` |
| Full class/interface typed-catch runtime parity | Out of scope (known gap) | Documented boundary; tracked under JS 1.0 semantic-gap epic/tasks |
| Full enum runtime/model parity | Out of scope (known gap) | Documented boundary; tracked under JS 1.0 semantic-gap epic/tasks |
| Full `Type` API parity | Out of scope (known gap) | Documented boundary; tracked under JS 1.0 semantic-gap epic/tasks |

## Required regression lanes for this scope

Run these lanes for scoped JS-native confidence:

```bash
npm run test:m14:js-target-core-wiring
npm run test:m14:js-stmt-try-throw
npm run test:m14:js-stmt-multi-catch
npm run test:m14:js-expr-new-array
npm run test:m14:js-unsupported-diagnostics
npm run test:m14:js-expr-range
npm run test:m14:js-expr-array-comprehension
npm run test:m14:js-expr-switch
npm run test:hxhx-targets
npm run test:upstream:js-oracle-smoke
```

`npm run test:upstream:js-oracle-smoke` defaults to the stable scoped fixture set
(`Loop`, `SwitchExpr`, `ArrayComprehension`, `RangeExpr`, `NewArray`).
Use `HXHX_JS_ORACLE_FIXTURES=<comma-separated fixtures>` for extended diagnostics.

## Scope change rule

Any JS-native scope update must change all three together:

1. This matrix (`docs/02-user-guide/HXHX_JS_NATIVE_SCOPE_1_0.md`).
2. At least one deterministic test/fixture lane.
3. Gate/CI wiring if the change affects required regression coverage.
