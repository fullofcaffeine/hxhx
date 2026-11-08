# Stage3 `@:isVar` properties

```haxe
@:isVar public var level(get, set):Int = 1;
function set_level(value:Int):Int return level = value;
```

Inside a property's own accessor, `level = value` writes the physical field
instead of calling the setter again. Typing marks that write as property
storage access. Before the fix, Stage3 admitted it only as a statement. In
value position, for example `return level = value`, the unsupported-
expression check rejected every field with a `set` accessor, so the write
became the `(Obj.magic 0)` placeholder. The field kept its initializer
value: `p.level = 5; p.level` printed `1`, and `p.level++` called the setter
with `2`.

The check now admits the write when the occurrence is marked as storage
access.

`Main.hx` covers:
- `(get, set)`, `(default, set)`, and `(null, set)` properties
- a setter that ends with `return field = value`
- writes from inside and outside the class
- `++` in statement and value position
- compound assignment (`+=`, `*=`) through the property

`npm run test:m14:stage3-isvar-properties` checks that upstream Haxe 4.3.7
prints `expected.stdout`, then requires the Stage3 native executable to
print the same text.

## Known failing: static `@:isVar` properties

`../stage3_isvar_properties_static` still prints `0` natively. On main,
Stage3 emits a static field as an immutable OCaml value, so a static write
cannot store. PR #131 (Bead `haxe_ocaml-nq65n`) adds static field storage. I
checked that this fixture matches upstream with PR #131 applied. The test
requires that the fixture still fails, so it notices when #131 lands.
