# Nullable enum comparisons

This fixture compares a nullable enum result with an ordinary enum value.
For example, `picker.choose(true) == Plain` must compile and return `true`.
The original OCaml output compares an `Obj.t` result with a concrete variant,
so native compilation fails before the program can run.

The independently authored expectations cover both operand orders, equality,
inequality, null, constants, and payload identity. A payload equals its alias.
Two separately constructed payloads do not compare equal, even when their
fields have the same values. The printed `left` and `right` lines also require
each operand to execute once, in source order.

The fixture also checks comparisons in initializers and nested functions.
Repeated calls and optional arguments must create distinct payload values.
The printed argument labels require constructor arguments to execute in
source order before allocation.

From the repository root, compare the fixture with upstream Haxe 4.3.7:

```sh
haxe -cp test/portable/fixtures/nullable_enum_comparison/src -main Main --interp
```

Run the native compile, build, and output check through the portable runner:

```sh
PORTABLE_FIXTURE_ALLOWLIST=nullable_enum_comparison npm run test:portable
```

The portable runner discovers this fixture through `build.hxml`. Its native
output must match `expected.stdout`. This focused regression does not prove
full Haxe compatibility or the compiler-host build that first exposed the bug.

Tracked by `haxe_ocaml-3z9p4`, which blocks the native representation check for
`haxe_ocaml-7dufk`.
