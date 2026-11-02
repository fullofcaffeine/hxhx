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

Stage3 passes such an argument with the Dynamic carrier (`Obj.t`), because
`Function` is an abstract over Dynamic.

The fixture passes an instance method (which keeps its receiver), a
two-argument method, a static method, a local function, a value stored in a
`Function` local, and a value passed through a `Function` parameter. It also
passes untyped lambdas (`function(d) {...}`, `d -> ...`, `(a, b) -> a`,
`(x) -> x` directly and through a local), the event-listener shape, and an
`Array<haxe.Constraints.Function>` literal. The
Stage3 test also requires upstream and Stage3 to reject an Int literal and a
String local passed as `Function`.

Not covered:
- `"text" + d` makes hxhx infer String for an untyped parameter `d`, which
  upstream does not (haxe_ocaml-lizwb), so the listeners print `d` directly.
- A `Function` is accepted where a concrete function type is expected
  (haxe_ocaml-buvfs). `Reflect.callMethod` on Stage3 fails above five
  arguments and returns `0` for a Void function (haxe_ocaml-5gxwi).
- A method value read with `Reflect.field(instance, "add")` on
the Stage3 route returns null today. PR #134 (haxe_ocaml-pewzi) adds class
methods to `Reflect.field`.

Bead: haxe_ocaml-6zeuc.
