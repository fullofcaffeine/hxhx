# Typed methods at the Reflect callable boundary

Run `npm run test:m14:reflect-call-method` from the repository root. It runs
`Main.hx` with pinned upstream Haxe 4.3.7, then builds it for the Stage3
native OCaml route and for the Neko route. Every program must print
`expected.stdout` exactly.

`Reflect.callMethod(o, func, args)` takes `func:haxe.Constraints.Function`.
`Function` is declared as `abstract Function(Dynamic) {}` with no `@:from`
conversion, but upstream Haxe lets every function value unify with it.
Before this change, typing rejected the program before either target could
emit it:

```haxe
final holder = new Holder();
Sys.println(Reflect.callMethod(holder, holder.add, [7]) == 12);
// upstream: true
// before:   No compatible method signature for callMethod
```

`TyFunctionConstraint` now states the rule once: a function value is
assignable to `haxe.Constraints.Function`. The rule is directional, and a
non-callable value is not accepted. Three typing owners use it:
- the shared assignment check (`TyAssignmentCompatibility.classify`);
- overload ranking (`TyperStage.overloadArgScore`, which scores it like an
  abstract conversion, below an exact signature);
- the inference solver's call constraint (`TyFunctionInference.constrain`),
  which accepts the value without solving anything from the destination. An
  untyped lambda's omitted inputs and its result fall back to Dynamic, because
  nothing can supply their types later;
- callback argument checks (`TyCallbackArgumentContext`), which accept a
  lambda whose inputs are still unknown;
- Array literal element checks, so `[holder.add, Holder.twice]` is a valid
  `Array<haxe.Constraints.Function>`.

Stage3 passes a function value to a `Function` parameter through the
Dynamic calling convention (`backend/ocaml/Stage3OcamlFunctionBoundary.hx`),
because `Reflect.callMethod` later applies it to the raw `Obj.t` elements of
its argument array, whatever their category:
- a String parameter receives the value's text, and null stays null.
  `function(d) Sys.println("listener " + d)` is typed `String -> Void`
  (upstream infers String for `d` too), and an Int argument prints
  `listener 9` as in eval, instead of crashing the native program;
- Int, Bool and nullable parameters use checked conversions;
- the result is boxed, and a Void function returns null.

The fixture passes an instance method (which keeps its receiver), a
two-argument method, a static method, a local function, a value stored in a
`Function` local, and a value passed through a `Function` parameter. It also
passes untyped lambdas (`function(d) {...}`, `d -> ...`, `(a, b) -> a`,
`(x) -> x` directly and through a local), the event-listener shape (including
`"listener " + d` called with an Int and with a String), and an
`Array<haxe.Constraints.Function>` literal. The
Stage3 test also requires upstream and Stage3 to reject an Int literal and a
String local passed as `Function`.

Not covered:
- A null String argument concatenated in a listener needs the null-String
  text fix of PR #160 (haxe_ocaml-txs4e) on the Stage3 route.
- A `Function` is accepted where a concrete function type is expected
  (haxe_ocaml-buvfs). `Reflect.callMethod` on Stage3 fails above five
  arguments (haxe_ocaml-5gxwi).
- A method value read with `Reflect.field(instance, "add")` on
the Stage3 route returns null today. PR #134 (haxe_ocaml-pewzi) adds class
methods to `Reflect.field`.

Bead: haxe_ocaml-6zeuc.
