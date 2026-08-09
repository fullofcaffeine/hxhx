# Second-pass design review: stack-safe OCaml expression printing

## Verdict

The change fixes the proven owner without changing target semantics. The OCaml
printer now walks expressions with a heap-backed work list, so valid deeply
nested syntax no longer consumes one Haxe evaluator call frame per AST level.

## What the work list preserves

Each work item means either “append these exact characters” or “render this
expression under this precedence and indentation.” Children are pushed in
reverse order because the most recently pushed item is processed first. This
preserves the former left-to-right output for constants, applications,
operators, assignments, sequences, records, lists, functions, conditionals,
matches, exceptions, loops, annotations, source positions, and nested lets.

Precedence checks and the small helpers that unwrap source-position nodes are
also iterative. Match-arm tail inspection was already iterative. Pattern and
type printers remain recursive because this failure involved expression depth,
and no evidence shows compiler-generated patterns or types approaching the
same depth. Expanding those separate surfaces without a real failing shape
would add risk without improving this proof.

## Output-equivalence check

The ordinary printer tests and the repository snapshot portfolio passed. The
reduced CppRuntimeSupport program printed 1,280,790 characters, compiled with
Dune, and completed the formerly missing `class_print` and `class_end` phases.
The broad portable run initially exposed one IMap evidence golden whose
local-variable identity includes Haxe's temporary `TVar.id`. After confirming
that the same five source-bound decisions and runtime behavior remained
present, that deterministic current report passed in isolation. Replacing the
unstable temporary identity is tracked separately by `haxe_ocaml-9bome.18`.

The final portfolio run then reported 105 of 107 fixtures passing with no
failure before its attached session receipt became unavailable. Rather than
claim an exit status that could no longer be read or repeat the whole
portfolio, the two identifiable remaining XML fixtures were rerun together.
Both built and ran successfully, and their runner ended with `Portable
conformance OK`. The closure evidence is therefore 105 observed passes plus an
exact two-fixture completion run, not a recovered 107-fixture aggregate exit.

## Failure and ownership check

No planner, semantic validator, representation decision, runtime requirement,
output transaction, or Dune behavior was weakened. The new telemetry is opt-in
and only names phase boundaries; it does not affect ordinary generated output.
No generated OCaml or handwritten OCaml was edited, and no output repair,
placeholder success, global stack increase, or swallowed exception was added.

The full compiler-scale run advanced from the old 631-second stack overflow to
a precise nullable-String `Reflect.compare` rejection after 1,684 seconds. That
is the intended fail-closed handoff: the printer no longer hides the next real
semantic gap.

## Review and escalation disposition

The task was correctly calibrated at `thinking:high`. Localization required
several phase boundaries and a faithful reduction, but the final owner and
replacement were bounded. Oracle was not used because there were no competing
semantic architectures after the reduced test proved the printer boundary.
If future evidence shows similarly deep pattern or type trees, they should get
their own focused red case and iterative owner rather than being changed by
speculation.
