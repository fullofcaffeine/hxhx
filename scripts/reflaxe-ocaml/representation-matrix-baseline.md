# Representation matrix baseline

Recorded on 2026-11-16 with `node scripts/reflaxe-ocaml/representation-matrix.js` on `main`
(`reflaxe.ocaml` hosted by upstream Haxe 4.3.7, macOS, OCaml 5.4.0). The run was split into
three passes while the generator was corrected; this table merges them.

**220 of 239 cells pass (92.1%)** after the first steps of the conversion table (updates of
2026-11-17 and 2026-11-19, below). No cell prints a wrong value, 3 cells produce OCaml that does
not build, and 16 cells are refused by `reflaxe.ocaml` with a named "unsupported" error.

The first recording passed 203 of 239 cells (84.9%), with 19 cells that did not build.

**Update 2026-11-17 (`haxe_ocaml-9cqxj`, step 1).** Casts and nullable assignments take their
conversion from one table, `OcamlValueConversion`. The cast `(Green : Null<Color>)` now
builds, so the `null_enum` row goes from 6 to 14 passing cells. No other cell changed.

**Update 2026-11-17 (`haxe_ocaml-9cqxj`, step 3).** A `Null<Bool>` value that enters
`Dynamic` or `Any` gets the Boolean tag from the same table. The `null_bool` row's
`dynamic_observed` cell, the only silently wrong cell, now passes. The table below is the
full run after step 1 with this cell updated from the `null_bool` row run.

**Update 2026-11-17 (`haxe_ocaml-9cqxj`, step 4).** A read of a field declared as a type
parameter, at a concrete type such as `Holder<Int>.value`, takes its conversion from the
table. The `generic_class` column goes from 10 to 16 passing cells. The table below is the
full run after this change.

**Update 2026-11-19 (`haxe_ocaml-9cqxj.2`, PR 1).** A `Null<Int>` that moves into a `Float`
(`UnboxNullableIntAsFloat`), and the other unplanned nullable-primitive moves (assignment tail,
direct function results, branch joins), take their conversion from the table: null gives the
default value. The `float` row's `optional_argument` cell now builds and passes. The table below
is the full run after step 4 with this cell updated from the `float` row run.

Each row passes one value type through each boundary and prints the result. A cell passes when
the native program prints the same line as `haxe --interp`.

| Mark | Meaning |
| --- | --- |
| ok | Same output as upstream Haxe |
| **WRONG** | Builds and runs, but prints a different value (silent wrong output) |
| build | `reflaxe.ocaml` emits OCaml that does not type-check |
| refused | `reflaxe.ocaml` stops with a named unsupported-conversion error |
| - | Not measured (Haxe does not define how a function prints) |

| value \ boundary | local | static_field | instance_field | argument | return | optional_argument | generic_function | generic_class | dynamic | dynamic_observed | array_dynamic | anon_field | closure_capture | method_value | callback_argument |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `int` | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| `float` | ok | ok | ok | ok | ok | ok | refused | ok | ok | ok | ok | ok | ok | ok | ok |
| `bool` | ok | ok | ok | ok | ok | refused | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| `string` | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| `null_int` | ok | ok | ok | ok | ok | ok | refused | ok | ok | ok | ok | ok | ok | ok | ok |
| `null_int_null` | ok | ok | ok | ok | ok | ok | refused | ok | ok | ok | ok | ok | ok | ok | ok |
| `null_float` | ok | ok | ok | ok | ok | ok | refused | ok | ok | ok | ok | ok | ok | ok | ok |
| `null_bool` | ok | ok | ok | ok | ok | ok | refused | ok | ok | ok | ok | ok | ok | ok | ok |
| `enum_const` | ok | ok | ok | ok | ok | ok | refused | ok | ok | ok | ok | ok | ok | ok | ok |
| `enum_args` | ok | ok | ok | ok | ok | ok | refused | ok | ok | ok | ok | ok | ok | ok | ok |
| `null_enum` | ok | ok | ok | ok | ok | ok | refused | ok | ok | ok | ok | ok | ok | ok | ok |
| `class` | ok | ok | ok | ok | ok | ok | refused | ok | ok | ok | ok | ok | ok | ok | ok |
| `anon` | ok | ok | ok | ok | ok | ok | refused | ok | ok | ok | ok | ok | ok | ok | ok |
| `array` | ok | ok | ok | ok | ok | ok | refused | ok | ok | ok | ok | ok | ok | ok | ok |
| `function` | ok | ok | ok | ok | ok | build | refused | ok | build | - | build | ok | ok | ok | refused |
| `dynamic` | ok | ok | ok | ok | ok | refused | refused | ok | ok | ok | ok | ok | ok | ok | ok |

## Failure classes

- **Silent wrong output (fixed 2026-11-17):** a `Null<Bool>` value observed through `Dynamic`
  printed `1` instead of `true` (`dynamic_observed`).
- **`Null<Enum>` crossings (fixed 2026-11-17):** a plain enum value reached a `Null<Color>`
  place without conversion, even through `(Green : Null<Color>)` in a local declaration.
- **Generic class fields (reads fixed 2026-11-17):** reading `Holder<T>.value` as `Int`,
  `Float`, `Bool`, `String`, an array, or a function left the value as `Obj.t`. Writes after
  construction are still open (`haxe_ocaml-9cqxj.1`).
- **Optional arguments:** `Float` and function optional arguments do not build; `Bool` and
  `Dynamic` optional arguments are refused.
- **Generic identity function:** `same<T>(x:T):T` is refused for most types
  (`ocaml-call:generic-identity-substitution`).
- **Function values through `Dynamic`, arrays, and callbacks:** several cells in the `function`
  row do not build or are refused.

Two printing bugs are kept out of the boundary cells: the matrix prints enums through a typed
`switch` and arrays through `join`. Natively, `Std.string(Green)` prints `1`
(`haxe_ocaml-oxjcd`), and `Std.string` of an array does not build (`haxe_ocaml-uo4xg`).

The typed conversion authority (`haxe_ocaml-9cqxj`) must take every cell to "ok" by
construction, not by fixing cells one at a time.
