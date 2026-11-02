# Class instances as text

Run `npm run test:m14:stage3-class-to-string` from the repository root. The
test runs `Main.hx` with pinned upstream Haxe 4.3.7, builds it with the Stage3
native emitter, and requires both programs to print `expected.stdout` exactly.

Haxe calls an instance's `toString()` when `Std.string`, string concatenation,
`Array.join` or `Array.toString` turns it into text. A call through a supertype
reaches the override:

```haxe
final dog:Animal = new Dog("rex");
Sys.println(Std.string(dog)); // upstream prints "dog rex"
```

Stage3 printed the instance's stored fields instead (`{name: rex}`), because it
never told the runtime which function to call (haxe_ocaml-czx3v,
haxe_ocaml-x1ekz).

Now each generated class whose ancestry has a zero-argument `toString()`
returning `String` registers an adapter with
`HxDynamic.register_class_stringifier` under its own class name. The planner is
`backend/ocaml/Stage3OcamlClassStringifiers.hx`. The runtime selects the
adapter from the receiver's runtime class, so the override wins. A class
without `toString()` prints its class name, as upstream eval does.

Kept out of the fixture, and tracked separately:
- a grandchild class in an `Array<Animal>` literal is rejected by the typer, so
  the fixture stores it in an `Animal` local first (haxe_ocaml-he9qh);
- `final sum = x + y` on Int fields inside a method emits a placeholder
  (haxe_ocaml-edpn8);
- Bool values print `1`/`0` in `join` and concatenation (haxe_ocaml-caxgt);
- `Reflect.field` on class methods (PR #134, haxe_ocaml-pewzi).
