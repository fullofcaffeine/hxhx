# Stage3 compound updates on anonymous-structure and Float instance fields

```haxe
var o = {n: 1};
o.n += 2;              // upstream Haxe prints 3

final h = new Holder();
h.ratio -= 0.25;       // Float instance field: upstream stores 1.25
```

Before the fix, the native Stage3 route turned these updates into the
`(Obj.magic 0)` placeholder. The statement was dropped, so the program printed
the old value, and a value-position result such as `final r = (o.n += 4)` was
a placeholder value.

`OcamlFieldUpdateLowering` now rewrites these updates on the typed tree into
operations Stage3 already emits: bind the receiver once, read the old value,
run the right operand, store the result, and yield the stored value.

`Main.hx` covers:
- `+=`, `-=`, `*=`, `/=`, and `%=` in statement and value positions
- Int, Float, and String anonymous-structure fields, also behind a typedef
- Float instance fields written as `this.f`, a bare `f`, and `h.f`
- Int right operands of a Float field, such as `h.f += count()`
- `Null<Int>` and `Null<Float>` right operands, and Int field `%=`
- `|=`, `&=`, `^=`, `<<=`, `>>=`, and `>>>=` on anonymous Int fields, in both positions
- a Float instance field declared with a type parameter (`Cell<Float>`)
- receivers and right operands that record their evaluation order, and a right
  operand that updates the same field

Printed Floats stay non-whole on purpose: whole-number Floats print differently
natively until haxe_ocaml-iffj5 lands, and that difference is not what this
fixture measures.

`npm run test:m14:stage3-field-compound-updates` checks that upstream Haxe 4.3.7
prints `expected.stdout`, then requires the Stage3 native executable to print
the same text. It also requires a named emit-time refusal for a `Dynamic` right
operand on these fields, instead of a dropped update.
