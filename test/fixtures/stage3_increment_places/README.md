# Stage3 `++` and `--` on array elements and fields

```haxe
final a = [1, 2, 3];
a[0]++;          // upstream: 2,2,3
final old = a[1]--;
```

Before the fix, Stage3 lowered `++` and `--` only on mutable locals and on
Int instance fields. On an array element, a Float instance field, or a field
of an anonymous structure, the update became the `(Obj.magic 0)` placeholder.
The statement was dropped, so `a` stayed `1,2,3`, and a value-position result
such as `old` was a placeholder value.

`OcamlFieldUpdateLowering` now rewrites these updates on the typed tree into
operations Stage3 already emits. It binds the array and index (or the
receiver) once, reads the old value, stores old plus or minus 1, and yields
the old value (postfix) or the new value (prefix).

`Main.hx` covers:
- prefix and postfix forms, in statement and value positions
- `Int`, `Float`, `Int32`, and `Null<Int>` elements
- Int, Float, `Null<Int>`, and `Null<Float>` instance fields, and anonymous-structure fields
- an array, an index, and a field receiver whose expressions record their evaluation
- a nested index (`a[a[0]++]++`), and `a[0]++ + a[0]`
- Int overflow wrap, and a null element, which throws as on upstream eval `npm run test:m14:stage3-increment-places` checks
that upstream Haxe 4.3.7 prints `expected.stdout`, then requires the Stage3
native executable to print the same text.

## Known failing: Int literals in Float slots

`../stage3_increment_places_int_in_float` crashes natively (exit 139):

```haxe
final fl:Array<Float> = [1, 2];
fl[0]++;
box.v = 3; box.v++;   // v:Float
```

Stage3 stores an Int literal into a Float slot without widening it, so the
slot holds an Int representation. Reading it back as a Float for `++` then
crashes. `fl[0] = fl[0] + 1.0` crashes the same way on main, so the bug is
in the store. That is PR #123 (Bead `haxe_ocaml-ljotn`). Before this PR the
update was silently dropped; now it crashes. The test requires that this
fixture still fails, so the fix is noticed and its lines move into
`Main.hx`.

## Not covered here

- A `Null<Int>` index (`a[nullableIndex]++`). The lowering emits
  `a[index] = next`, and Stage3 still drops writes through a `Null<Int>`
  index (Bead `haxe_ocaml-atk5i`, in progress).
- `++` on a static field (`Counter.total++`), which is owned by PR #131.
- `++` on an `@:isVar` property, whose setter writes to the backing field are
  dropped (Bead `haxe_ocaml-2njv2`).
- UInt values above `0x7FFFFFFF` print as negative Ints (Bead
  `haxe_ocaml-5uhcj`). The `++` itself is correct.
- `++` on an `Int32` local (`var x:Int32 = 5; x++`) is still dropped (Bead
  `haxe_ocaml-xojcc`).
