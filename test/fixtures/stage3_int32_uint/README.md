# Stage3 `Int32` updates and `UInt` text

```haxe
var x:Int32 = 5;
x++;                       // upstream 6; native kept 5 (haxe_ocaml-xojcc)
final big:UInt = 0xFFFFFFFF;
Sys.println("v " + big);   // upstream "v 4294967295"; native printed "v -1" (haxe_ocaml-5uhcj)
```

**Int32.** `++`/`--` on an `Int32` local, parameter, or field was dropped
natively. PR #136 lowers those updates; this branch is stacked on it, and
this fixture pins prefix and postfix forms, value positions, and the wrap
at 2^31.

**UInt.** `UInt` is an abstract over the 32-bit Int. Where the static type
is `UInt`, upstream converts the value to text with `UInt.toString`, which
prints the unsigned value. Stage3 printed the underlying Int instead. Now
`Std.string`, String concatenation operands, and `trace` print the unsigned
value for a `UInt` or `Null<UInt>`
(`Stage3OcamlStringConversion.isUnsigned`). Upstream itself prints the
erased Int (`-1`) in these cases, and so does Stage3:

- `Array<UInt>.join`
- `Std.string(array)`
- a bare `Sys.println(uint)`, which passes the value as `Dynamic`

Comparisons, division, remainder, wrap-around, and `++`/`--` on `UInt`
already matched upstream once the value printed correctly. They are covered
here too.

`npm run test:m14:stage3-int32-uint` checks that upstream Haxe 4.3.7 prints
`expected.stdout`, then requires the Stage3 native executable to print the
same text. It also checks that `trace(uint)` prints the unsigned value.
Native `trace` omits upstream's `File.hx:line:` prefix (Bead
`haxe_ocaml-00tpu`), so that check compares only the value.

Not covered: `Std.int(uint)`. Upstream converts the UInt to Float, then
`Std.int(4294967295.0)` wraps to `-1`. Natively `Std.int` of a Float outside
the 32-bit range does not wrap; that is a Float-to-Int conversion bug for
every Float (Bead haxe_ocaml-3lpr4).
