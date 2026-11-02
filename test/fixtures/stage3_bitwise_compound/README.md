# Stage3 bitwise compound assignment

`Main.hx` applies the six bitwise compound operators `|= &= ^= <<= >>= >>>=`
to these targets:

- Int locals, as statements and as values (`final r = (y <<= 2)`), including
  negative values, shift-count masking (`1 << 33` is `2`), a right operand
  that prints when it runs (the old value is read first), a `Null<Int>` local,
  and a `Dynamic` local;
- instance fields through a value receiver (`flags.bits |= 2`) and through the
  implicit receiver inside a method (`bits ^= mask`);
- fields of an anonymous structure (`anon.mask |= 6`), which also covers
  arithmetic `+=` and `-=` on such fields;
- `Array<Int>` elements;
- `haxe.Int32` locals, fields, array elements and anonymous fields, which wrap
  at 32 bits.

Before the fix, the native program dropped each local update (it printed
`3` for `local` and `0 3` for `value`). Array updates stopped emission with
`unsupported OCaml indexed compound operation`, instance-field updates were
dropped, and compound updates of anonymous fields, arithmetic ones included,
removed the whole statement. The `haxe.Int32` and `Dynamic` updates already
worked, because they lower through the abstract operator and the Dynamic
runtime. They stay in the fixture so both representations remain covered.

Static fields are not covered. Stage3 has no mutable static storage yet
(haxe_ocaml-nq65n), and static bitwise updates are tracked in
haxe_ocaml-8k5ja.

`npm run test:m14:stage3-bitwise-compound` checks that upstream Haxe 4.3.7
prints `expected.stdout`. It then builds the program with Stage3 and
requires the native executable to print the same text.
