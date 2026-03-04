# Execution Modes: Delegated vs Native

This project uses two execution modes.

- **Delegated mode**: `hxhx` forwards compile work to upstream `haxe` (`stage0`).
- **Native mode**: `hxhx` runs its own compile pipeline/backends directly.

If you are new, this is the most important distinction.

## Mental model

```mermaid
flowchart LR
  A[Your Haxe project] --> B[hxhx CLI]
  B -->|Delegated mode| C[upstream haxe stage0]
  B -->|Native mode| D[hxhx native pipeline]
  D --> E[Builtin backend or dynlink plugin]
```

## When to use each mode

| Mode | Use it when | Strength | Tradeoff |
| --- | --- | --- | --- |
| Delegated | You need compatibility-first behavior right now | Predictable baseline via upstream `haxe` | Depends on stage0 |
| Native | You are validating or shipping non-delegating `hxhx` paths | Future-ready architecture, native plugin/builtin paths | Some lanes are still maturing |

## Portable vs metal (profile summary)

| Profile | Goal | Typical use | Tradeoff |
| --- | --- | --- | --- |
| `portable` | Compatibility-first semantics | Default builds and cross-target-friendly code paths | Can carry more runtime overhead |
| `metal` | Native-leaning strict mode | Performance-focused, metal-safe code paths | Stricter constraints and fail-fast checks |

Deep contract details:
- `docs/02-user-guide/OCAML_PROFILE_CONTRACT.md`
- `docs/02-user-guide/OCAML_RUNTIME_CAPABILITY_MATRIX.md`

## Related terms

- `stage0`, `stage3`, `stage4` are contributor architecture terms.
- Beginner docs should prefer **delegated** and **native** terms first.

See `docs/00-project/GLOSSARY.md` for term definitions.

## Beginner truth table (canonical: lanes + profiles + gate purpose)

Use this as the single quick-reference table when deciding what to run.

| Scenario | Lane / command | Profile default | Gate purpose to prioritize |
| --- | --- | --- | --- |
| Compile a Haxe app with compatibility-first behavior | Delegated lane (`--ocaml-eval` or `--compat --js <file>`) or upstream `haxe` | `portable` | Gate 0 fast safety (`CI / Core PR Checks`) |
| Use upstream `haxe` + `reflaxe.ocaml` | Upstream lane (`haxe -lib reflaxe.ocaml`) | `portable` | Gate 1/Gate 2 oracle macro compatibility |
| Validate non-delegating `hxhx` compile paths | Native lane (`--ocaml` / `--js <file>`) | `portable` unless explicitly set to `metal` | Gate 3 builtin/native target smoke + stage0-forbidden checks |
| Optimize OCaml output performance on metal-safe code | Native lane (`--ocaml`) | `metal` | Gate 4 distribution/perf acceptance and KPI reports |
| Promote backend behavior into runtime-loaded native artifacts | Native lane + backend plugin (`ocaml-dynlink`) | `portable` for baseline compatibility, `metal` for perf-focused lanes | Gate 4 plugin acceptance/perf and ABI compatibility checks |

Related canonical references:

- Lane delegation truth table: `docs/02-user-guide/concepts/what_delegates_today.md`
- Gate/workflow map: `docs/00-project/CI_GATES.md`
- Term definitions: `docs/00-project/GLOSSARY.md`
