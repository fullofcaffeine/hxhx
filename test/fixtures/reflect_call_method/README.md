# Typed methods at the Reflect callable boundary

Run `npm run test:m14:reflect-call-method` from the repository root. It runs
`Main.hx` with pinned upstream Haxe 4.3.7, then builds it for the Stage3
native OCaml route and for the Neko route. Every program must print
`expected.stdout` exactly.

`Reflect.callMethod(o, func, args)` takes `func:haxe.Constraints.Function`.
`Function` is declared as `@:callable abstract Function(Dynamic) {}` with no `@:from`
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

On the Stage3 route, a function value stored as a `Function` is adapted to the
Dynamic calling convention (`backend/ocaml/Stage3OcamlFunctionBoundary.hx`) at
these destinations:

- call arguments, including optional `?f:Function` parameters;
- `Function` and `Null<Function>` locals, at declaration and assignment;
- elements of an `Array<Function>` literal.

Every other destination stops native emission with a named error, because a raw
typed closure there would crash when `Reflect.callMethod` calls it. Typing
records each such place as a `TypedBackendFunctionConstraintFlow`, and
`Stage3OcamlFunctionBoundary.requireAdapted` refuses anything not adapted. That
covers instance and static fields, field initializers, function and lambda
results, structure fields, `Array.push`, array index assignment, `Map.set`,
enum and constructor arguments, and type-check or cast results.
`npm run test:m14:reflect-call-method` also runs
`M14Stage3FunctionDestinationTest`, which checks each of these. The JS and Neko
routes keep accepting them, and haxe_ocaml-h9dw9 tracks adapting them on Stage3.

`Reflect.callMethod` later hands the wrapped function the raw `Obj.t` elements
of its argument array, whatever their number and category:
- more arguments than parameters raise a catchable error, as in eval; a
  missing argument is null for a reference or nullable parameter, as in eval,
  and 0, 0.0 or false for a non-null Int, Float or Bool parameter;
- a String parameter receives the value's text, and null stays null.
  `function(d) Sys.println("listener " + d)` is typed `String -> Void`
  (upstream infers String for `d` too), and an Int argument prints
  `listener 9` as in eval. Only text output matches: eval keeps the Int, so
  `s == "9"`, `s.length` or `s.charAt(0)` give different results there;
- a Float parameter accepts an Int or a Float; Int, Bool and nullable
  parameters use checked conversions, which raise a catchable error for a
  value of another category;
- the result is boxed (a Bool keeps its box), and a Void function returns null.

A function with optional or rest parameters cannot be stored as a `Function`
on the Stage3 route yet; emission stops with a named error.

The fixture passes an instance method (which keeps its receiver), a
two-argument method, a static method, a local function, a value stored in a
`Function` local, and a value passed through a `Function` parameter. It also
passes untyped lambdas (`function(d) {...}`, `d -> ...`, `(a, b) -> a`,
`(x) -> x` directly and through a local), the event-listener shape (including
`"listener " + d` called with an Int and with a String), a Float parameter
called with an Int, a `Function` local, missing and extra arguments, Bool
parameters and results in an `Array<Function>`, and an
`Array<haxe.Constraints.Function>` literal. The
Stage3 test also requires upstream and Stage3 to reject an Int literal and a
String local passed as `Function`.

Not covered:
- Calling a `Function` directly (`f(1)`) stops while typing on the Stage3 route
  with "selected call conversion does not satisfy its retained parameter",
  although upstream allows it because `Function` is `@:callable`. Calling a
  wrapped value through a Dynamic field or structure (`o.f(1)`) works; other
  direct Dynamic calls fail in `ocamlopt` with a type error.
- A null String argument concatenated in a listener needs the null-String
  text fix of PR #160 (haxe_ocaml-txs4e) on the Stage3 route.
- A `Function` is accepted where a concrete function type is expected
  (haxe_ocaml-buvfs). `Reflect.callMethod` on Stage3 fails above five
  arguments (haxe_ocaml-5gxwi).
- A method value read with `Reflect.field(instance, "add")` on
the Stage3 route returns null today. PR #134 (haxe_ocaml-pewzi) adds class
methods to `Reflect.field`.

Bead: haxe_ocaml-6zeuc.
