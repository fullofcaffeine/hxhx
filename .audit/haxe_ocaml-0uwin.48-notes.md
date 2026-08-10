Planned catch chains now authorize one checked HxRuntime exception pattern and
one checked unmatched-exception rethrow. The existing control decision remains
the semantic owner; syntax receives exact pattern/expression occurrences and
cannot infer permission from a private target name.

The focused red was preserved in the decision trail. Focused catch authority,
control planning, AST traversal/printer, runtime requirements, checked generated
text, type-registry generated text, the Haxe 4.3.7 oracle, and the 13-chain
Haxe-to-OCaml compile/build/run tracer pass. The tracer also proves one matching
runtime requirement per catch decision. Formatting, no-Dynamic, private-runtime
inventory, handwritten-OCaml ownership, local-path, and mega-file guards pass.

The reviewed inventory moved from 385 to 383 rows, removing exactly the planned
HxRuntime.Hx_exception pattern and HxRuntime.hx_throw_typed expression sites.
Runtime source selection and README Goals are unchanged.

The package-wide runtime-use wrapper was stopped after its Haxe 4.3.7
null-safety pass remained CPU-bound for 12 minutes. Its three underlying
fixtures pass directly, and the pre-existing wrapper latency/cleanup defect is
already owned by haxe_ocaml-tqv34. No pass is claimed for that wrapper.

The thinking:xhigh second pass is recorded in
.audit/haxe_ocaml-0uwin.48-second-pass.md. Oracle was deliberately not used:
the sealed catch owner and failure boundary were exact, and local executable
evidence converged without an unresolved architecture choice.
