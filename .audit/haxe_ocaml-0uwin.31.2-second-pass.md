# Second-pass review: IMap conversion final runtime-use order

Outcome: accepted. Ordinary IMap conversions now describe private runtime helpers in the same preorder used to inspect the completed structured OCaml expression.

The defect was not a target-behavior error. The adapter created correct nested expressions, but its local side list recorded the order helper nodes were constructed. For `HxIterator.of_array (HxMap.keys ...)`, construction saw the inner Map call first while final AST traversal correctly saw the outer iterator wrapper first. Text formatting had the same issue across iterator, array, and stringifier helpers.

The fix keeps semantics in the existing typed plan:

- The plan explicitly records the known final order for standard Map operations.
- The syntax module walks only the structured adapter expression it just built and retains references whose owner is this conversion.
- The walk does not scan generated text, infer Haxe behavior, or accept references from the source expression.
- Local reconciliation and final-output reconciliation therefore compare the same order.

The focused test names the expected wrapper, Map, formatting, and stringifier order. The general runtime-use authority fixture already proves swapped final order fails. The full IMap boundary built twice with byte-identical lowering evidence, executed successfully, passed inspection and corruption checks, and retained the same generated behavior.

Oracle was deliberately skipped because the failing diagnostic identified an exact mismatch between two existing deterministic orders, and the fix remained within one focused syntax/plan contract. No final-authority rule was relaxed.
