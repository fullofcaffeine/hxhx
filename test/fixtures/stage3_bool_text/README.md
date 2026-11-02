# Bool values as text

Run `npm run test:m14:stage3-bool-text` from the repository root. The test runs
`Main.hx` with pinned upstream Haxe 4.3.7, builds it with the Stage3 native
emitter, and requires both programs to print `expected.stdout` exactly.

An OCaml `bool` and `int` share one runtime shape, so the shared runtime
conversion (`HxDynamic.toStdString`) cannot tell `true` from `1`. A Bool must
reach text through its checked type. Stage3 lost that type in two places:

| Haxe expression | Upstream | Old native output |
| --- | --- | --- |
| `"static " + flag` (static Bool field) | `static true` | `static 1` |
| `"is " + (value is Child)` | `is true` | `is 1` |
| `"nullable " + maybe` (`Null<Bool>` local) | `nullable true` | `nullable 1` |
| `"echo " + value` (optional `?value:Bool`) | `echo true` | `echo 1` |
| `"map " + map.get("a")` (`Map<String, Bool>`) | `map true` | `map 1` |
| `[true, false].join(",")` | `true,false` | `1,0` |

Now:
- Typing records each String concatenation's operand types
  (`TypedBackendStringConcatOccurrence`, recorded by `projectBinary`). Stage3
  converts a Bool or `Null<Bool>` operand through
  `Stage3OcamlStringConversion.convert`, which boxes the Bool before runtime
  conversion, or uses the nullable Bool helper.
- `Array.join` on a checked `Array<Bool>` or `Array<Null<Bool>>` receiver
  converts each element through the same typed conversion.

The fixture also covers literals, locals, comparisons, function results,
`Null<Bool>` results, ternaries, interpolation, `Std.string`,
`Array.toString`, anonymous-object fields, Dynamic values, mixed
`Array<Dynamic>`, `StringBuf.add`, null checks, a `Null<Bool>` condition, and
optional Bool parameters. Integers still print `1` and `0`.

`trace` is left out of the exact comparison. Native `trace(true)` prints
`true`, but it has no `file:line:` prefix (haxe_ocaml-00tpu).

Not changed here: `Null<Bool>` locals and optional Bool parameters still store
a raw OCaml `bool` rather than the nullable box (`HxRuntime.box_bool`). Their
text, null checks and conditions in this fixture match upstream. Moving them to
the box is the remaining part of haxe_ocaml-s1dgz.

Beads: haxe_ocaml-agc6n, haxe_ocaml-caxgt.
