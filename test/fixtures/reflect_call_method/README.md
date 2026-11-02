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
  which accepts the value without solving anything from the destination.

Stage3 passes such an argument with the Dynamic carrier (`Obj.t`), because
`Function` is an abstract over Dynamic.

The fixture passes an instance method (which keeps its receiver), a
two-argument method, a static method, a local function, a value stored in a
`Function` local, and a value passed through a `Function` parameter. The
Stage3 test also requires upstream and Stage3 to reject an Int literal and a
String local passed as `Function`.

Not covered: a method value read with `Reflect.field(instance, "add")` on
the Stage3 route returns null today. PR #134 (haxe_ocaml-pewzi) adds class
methods to `Reflect.field`.

Bead: haxe_ocaml-6zeuc.
