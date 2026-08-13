# Second-pass review: callable Array read types

## Outcome

The fix preserves the final Haxe function type at one standard Array read. It
does not change Array runtime behavior or add a general cast.

For example, `callbacks[0](value)` still evaluates the Array and index once.
The emitted `HxArray.get` result now carries `String -> Int` when that is the
final Haxe element type. OCaml can then check the argument and return type.

## Review findings

1. **The decision is narrow.** Only a final `TFun` result selects the
   `exact-callable` carrier. Other Array reads keep normal OCaml inference.
2. **The plan owns the conversion.** Syntax does not guess from generated text.
   It accepts the annotation only when the sealed carrier and the fresh typed
   expression agree.
3. **Corruption fails closed.** The unit fixture creates a validly shaped but
   incorrect `inferred` decision for a callable read. Lookup rejects it before
   output publication.
4. **Evaluation order is unchanged.** Existing receiver and index temporary
   bindings remain in the same order and still prevent duplicate evaluation.
5. **The regression has two independent observers.** Upstream Haxe 4.3.7
   supplies the expected output. Dune type-checks and executes the generated
   OCaml.
6. **The real workload advanced.** The four macro-host callback errors are
   absent. The next failure is the independently tracked enum-to-`Obj.t`
   conversion in `haxe_ocaml-0inhh`.
7. **No readiness claim changes.** The macro-host snapshot did not publish, so
   README Goals remain unchanged.

## Escalation decision

Oracle review was deliberately skipped. The reduced failure identified one
typed plan boundary, upstream behavior was clear, and the real workload
advanced to an unrelated error. This written review is the required second
pass for the `thinking:high` task.
