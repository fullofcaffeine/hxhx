# OCaml Interop: Labelled + Optional Arguments

OCaml has **labelled arguments** (`~x:`) and **optional labelled arguments** (`?x:`) that Haxe does not natively support.

For OCaml extern interop, `reflaxe.ocaml` supports a lightweight mapping using per-parameter metadata:

- `@:ocamlLabel("x")` on a parameter means “emit this argument as `~x:` (or `?x:` if the Haxe parameter is optional)”.
- Unlabelled parameters are emitted positionally, so you can mix labelled + unlabelled parameters in a single extern signature.

## Example

Haxe extern:

```haxe
@:native("Native.Mod")
extern class Foo {
  static function f(@:ocamlLabel("x") x:Int, y:Int, @:ocamlLabel("z") ?z:Int):Int;
}
```

Haxe callsites:

```haxe
Foo.f(1, 2, 3);
Foo.f(1, 2, null); // treat as "omit" -> None
Foo.f(1, 2);       // omit optional arg entirely
```

Emitted OCaml callsites (shape):

- `Foo.f(1, 2, 3)` → `Native.Mod.f ~x:1 2 ?z:(Some 3)`
- `Foo.f(1, 2, null)` → `Native.Mod.f ~x:1 2 ?z:None`
- `Foo.f(1, 2)` → `Native.Mod.f ~x:1 2`

## Notes / gotchas

- For **optional labelled args**, OCaml expects an `option` value (`None` / `Some v`).
  `reflaxe.ocaml` treats `null` as `None` for convenience at Haxe callsites.
- Nullable primitives (`Null<Int>`, `Null<Float>`, `Null<Bool>`) are represented with a
  runtime null sentinel; the backend detects the sentinel to decide between `None` and `Some`.
- This feature is currently scoped to **extern** interop. For non-extern code, use normal Haxe
  optional parameters (which compile to the target’s default calling conventions).

