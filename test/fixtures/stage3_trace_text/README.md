# Trace output and enum Bool arguments

Run `npm run test:m14:stage3-trace-text` from the repository root. The test
runs `Main.hx` with pinned upstream Haxe 4.3.7, builds it with the Stage3 native
emitter, and requires both programs to print `expected.stdout` exactly.

| Haxe expression | Upstream | Old native output |
| --- | --- | --- |
| `trace("hello")` (on line LINE) | `test/fixtures/stage3_trace_text/Main.hx:LINE: hello` | `hello` |
| `trace(flag)` (Bool static) | `...Main.hx:LINE: true` | `1` |
| `trace(42, "extra", true)` | `...Main.hx:LINE: 42,extra,true` | nothing |
| `trace(nothing)` (null String) | `...Main.hx:LINE: null` | raw bytes |
| `Helper.report(7)` tracing in `Helper.hx` | `...Helper.hx:4: helper,7` | `helper` |
| `Std.string(Flagged(true))` | `Flagged(true)` | `Flagged(1)` |

Now:
- The typed trace record (`TypedBackendTraceOccurrence`) keeps each
  `trace(...)` call's source line and argument types.
  `backend/ocaml/Stage3OcamlTrace.hx` prints `file:line: ` and then every
  argument, separated by commas. Each argument is converted from its type,
  like `Std.string`; a null String prints `null`.
- The file name is the module's path relative to the compiler's working
  directory. Upstream prints the path relative to the owning class path,
  spelled as that class path was given (`-cp src` prints `src/Main.hx`, an
  absolute `-cp /abs/src` prints `Main.hx`, `-cp ../src` prints
  `../src/Main.hx`). Stage3 resolves class paths to absolute paths and loses
  their spelling, so it matches upstream for a relative class path under the
  working directory, as in this fixture, and differs for absolute class
  paths and class paths outside the working directory.
- Arguments are evaluated once, left to right: `trace(next(), next(),
  next())` prints `0,1,2`, as upstream does.
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
