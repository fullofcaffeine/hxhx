## Outcome

The compiler-scale target generator no longer exhausts the Haxe evaluator
stack while printing the generated OCaml syntax tree. The printer now keeps
its own explicit list of remaining expression work, so valid nesting depth is
limited by available memory rather than one evaluator call frame per syntax
node.

## Evidence

- The old printer failed on a focused 20,000-level nested-let expression with
  `Stack overflow`; the same test now passes.
- Opt-in phase telemetry localized the real compiler failure after lowering,
  binding order, and runtime scanning, at the start of class printing.
- A reduced program that exercises every public `CppRuntimeSupport` method now
  prints a 1,280,790-character module and builds it with Dune.
- Printer tests, snapshot checks, formatting, local-path and handwritten-OCaml
  ownership guards passed.
- The portable portfolio showed 105 of 107 fixtures passing before its saved
  session receipt became unavailable. The two identifiable remaining XML
  fixtures were then rerun together; both built and ran, and their runner ended
  with `Portable conformance OK`.
- The exact current-source `hxhx` workload advanced from the former stack
  overflow after 631 seconds to a later, precise nullable-String
  `Reflect.compare` rejection after 1,684 seconds.

## Boundaries and follow-up

No generated or handwritten OCaml was edited. The change does not weaken
lowering, representation, diagnostics, output transactions, or target
validation. README Goals remain unchanged because a complete user-facing route
has not closed.

The later nullable-String comparison is tracked by `haxe_ocaml-9bome.19`. The
unrelated discovery that an IMap evidence report publishes temporary
process-local variable IDs is tracked by `haxe_ocaml-9bome.18`.

The task's `thinking:high` calibration was sufficient. A written second pass
found one bounded implementation owner, so an Oracle review was deliberately
not used.
