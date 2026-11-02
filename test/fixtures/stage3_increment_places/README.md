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

`Main.hx` covers prefix and postfix forms, statement and value positions,
`Int`, `Float`, `Int32`, and `Null<Int>` elements, Int and Float instance
fields, anonymous-structure fields, and an array and index whose expressions
record their evaluation. `npm run test:m14:stage3-increment-places` checks
that upstream Haxe 4.3.7 prints `expected.stdout`, then requires the Stage3
native executable to print the same text.

Not covered here:
- A `Null<Int>` index (`a[nullableIndex]++`). The lowering emits
  `a[index] = next`, and Stage3 still drops writes through a `Null<Int>`
  index (Bead `haxe_ocaml-atk5i`, in progress).
- `++` on a static field (`Counter.total++`), which is owned by PR #131.
- `++` on an `Int32` local (`var x:Int32 = 5; x++`) is still dropped (Bead
  `haxe_ocaml-xojcc`).
