# OCaml-native Mode (`ocaml.*` surface)

The **portable** surface (default) lets you write “normal Haxe” and still target OCaml.
The **OCaml-native** surface is opt-in: you import/use `ocaml.*` APIs to get output that maps
more directly to OCaml idioms and library ecosystems.

This doc explains:

- when to use the OCaml-native surface (and when not to),
- the “native” types we currently expose,
- how extern interop works (`@:native`, `@:ocamlLabel`),
- how target-runtime facade authors declare checked compatibility support,
- and the key caveats.

## When to use `ocaml.*`

Use the OCaml-native surface when:

- You are writing code that is intentionally OCaml-specific (not meant to be portable).
- You want 1:1 interop with existing OCaml libraries (`Stdlib`, `Hashtbl`, `Seq`, ExtLib, …).
- You are implementing compiler-like tooling where OCaml idioms are a better fit.

Stick to the portable surface when:

- You want code to also compile to JS/HashLink/etc.
- You want Haxe stdlib semantics (`Array<T>`, `haxe.io.Bytes`, `Map`, …) and predictable cross-target behavior.

## Native types/APIs available today

### Algebraic data types (emitted as native constructors)

- `ocaml.List<T>` → OCaml `'a list` (`[]` / `(::)`)
- `ocaml.Option<T>` → OCaml `'a option` (`None` / `Some`)
- `ocaml.Result<T,E>` → OCaml `('a,'e) result` (`Ok` / `Error`)

These are special-cased by the backend, so constructors and pattern matches are emitted as real OCaml ADTs.

### Refs (explicit mutability)

- `ocaml.Ref<T>` → OCaml `'a ref` (`ref` / `!` / `(:=)`)

This is an opt-in “native surface” for explicit ref usage:

- `ocaml.Ref.make(v)` → `ref v`
- `ocaml.Ref.get(r)` → `!r`
- `ocaml.Ref.set(r, v)` → `r := v`

### Stdlib modules (extern + opaque values)

These surfaces are small-but-useful, typed wrappers over `Stdlib.*`:

- `ocaml.Array<T>` → OCaml `'a array` (`Stdlib.Array`)
- `ocaml.Bytes` → OCaml `bytes` (`Stdlib.Bytes`)
- `ocaml.Char` → OCaml `char` (`Stdlib.Char`)
- `ocaml.Hashtbl<K,V>` → OCaml `('k,'v) Hashtbl.t` (`Stdlib.Hashtbl`)
- `ocaml.Seq<T>` → OCaml `'a Seq.t` (`Stdlib.Seq`)
- `ocaml.StringMap<V>` / `ocaml.IntMap<V>` → `Stdlib.Map.Make(...)` instantiations (emitted as `OcamlNative*Map`)
- `ocaml.StringSet` / `ocaml.IntSet` → `Stdlib.Set.Make(...)` instantiations (emitted as `OcamlNative*Set`)

See `packages/reflaxe.ocaml/std/ocaml/*.hx` for the authoritative API surface.

## Extern interop

### `@:native` (module/function mapping)

For **extern classes**, `@:native("A.B")` maps the class to an OCaml module path.
For **extern fields**, `@:native("foo")` (or `@:native("A.B.foo")`) maps the identifier emitted.

Example:

```haxe
@:native("Stdlib.List")
extern class StdListNative {
  @:native("map")
  static function map<A,B>(f:A->B, xs:ocaml.List<A>):ocaml.List<B>;
}
```

Callsites emit `Stdlib.List.map ...` in OCaml.

### `@:ocamlRuntime` (checked target-runtime requirement)

Most externs point to OCaml itself or to an external library. They do not use
this metadata. Authors of the reflaxe.ocaml compatibility layer use
`@:ocamlRuntime("capability")` when a typed extern calls one of the checked
`Hx*` runtime modules:

```haxe
@:ocamlRuntime("haxe-standard-io")
@:native("HxStdio")
private extern class NativeHxStdio {
  static function flush(stream:Int):Void;
}
```

The two metadata entries answer different questions:

- `@:native("HxStdio")` says which OCaml module receives the call.
- `@:ocamlRuntime("haxe-standard-io")` says why Haxe behavior needs a
  compatibility helper.

The capability name is not an arbitrary module name. The compiler owns a closed
mapping from supported capabilities to reviewed runtime sources, verifies that
the resolved native call uses the expected module, and records the reason in
`ocaml_runtime_requirement_report.json`. An unknown capability or a mismatch
such as declaring standard I/O while targeting another module stops compilation
before OCaml output is packaged.

The current first slice supports declarations on a static extern class or
static extern field. This is an advanced target/runtime-authoring contract, not
a way to declare opam libraries; external native dependencies need their own
structured package manifest.

### `@:ocamlLabel` (labelled + optional labelled args)

OCaml has labelled arguments (`~x:`) and optional labelled arguments (`?x:`) that Haxe doesn’t.

For extern interop, add `@:ocamlLabel("x")` to the parameter:

- non-optional parameter → emits `~x:`
- optional parameter (`?x:T`) → emits `?x:` and wraps the value as `Some v` / `None`

See `docs/02-user-guide/OCAML_INTEROP_LABELLED_ARGS.md:1` for a copy-pasteable example.

## Caveats

- `ocaml.*` APIs are **not portable**. Treat them like a target-specific stdlib.
- Some OCaml types (like `Seq.t`) are intentionally modeled as **opaque** values; the goal is
  idiomatic interop, not forcing OCaml’s exact type representation into Haxe.
- Optional labelled args currently emit `?label:(Some v)` / `?label:None`. This is valid OCaml,
  but may be more verbose than hand-written code (`~label:v`).
