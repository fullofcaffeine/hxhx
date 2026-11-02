# Trace output and enum Bool arguments

Run `npm run test:m14:stage3-trace-text` from the repository root. The test
runs `Main.hx` with pinned upstream Haxe 4.3.7, builds it with the Stage3 native
emitter, and requires both programs to print `expected.stdout` exactly.

| Haxe expression | Upstream | Old native output |
| --- | --- | --- |
| `trace("hello")` | `test/fixtures/stage3_trace_text/Main.hx:18: hello` | `hello` |
| `trace(flag)` (Bool static) | `...Main.hx:19: true` | `1` |
| `trace(42, "extra", true)` | `...Main.hx:20: 42,extra,true` | nothing |
| `trace(nothing)` (null String) | `...Main.hx:23: null` | raw bytes |
| `Helper.report(7)` tracing in `Helper.hx` | `...Helper.hx:4: helper,7` | `helper` |
| `Std.string(Flagged(true))` | `Flagged(true)` | `Flagged(1)` |

Now:
- The typed trace record (`TypedBackendTraceOccurrence`) keeps each
  `trace(...)` call's source line and argument types.
  `backend/ocaml/Stage3OcamlTrace.hx` prints `file:line: ` and then every
  argument, separated by commas. Each argument is converted from its type,
  like `Std.string`; a null String prints `null`.
- The file name is the module's path relative to the compiler's working
  directory, which is what upstream prints for a relative `-cp`. With an
  absolute `-cp`, upstream prints an absolute path and Stage3 prints a
  relative one.
- A generated enum module registers which constructor arguments are Bool or
  `Null<Bool>` (`HxDynamic.register_enum_bool_arguments`), so enum text prints
  `Flagged(true)` and `Maybe(null)` (haxe_ocaml-k3jwd).
- A String `+=` on an instance field with a null field or a null right operand
  already printed `null`; the fixture keeps that as a regression check.

Not covered:
- Replacing `haxe.Log.trace` with a custom function is not supported, because
  Stage3 does not run reassigned dynamic functions (haxe_ocaml-waz9w).
- A String `+=` on a static field is not stored at all today. That is the
  static field write bug fixed by PR #131 (haxe_ocaml-nq65n), so it is not in
  this fixture.

Beads: haxe_ocaml-00tpu, haxe_ocaml-k3jwd.
