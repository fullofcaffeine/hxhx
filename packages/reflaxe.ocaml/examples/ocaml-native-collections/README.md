# ocaml-native-collections

This example demonstrates the **OCaml-native surface** (`ocaml.*`) by using a few `Stdlib` data structures:

- `ocaml.Array<T>` → `Stdlib.Array`
- `ocaml.Hashtbl<K,V>` → `Stdlib.Hashtbl`
- `ocaml.Bytes` / `ocaml.Char` → `Stdlib.Bytes` / `Stdlib.Char`
- `ocaml.Seq<T>` → `Stdlib.Seq`
- `ocaml.StringMap<V>` / `ocaml.StringSet` → `Stdlib.Map.Make` / `Stdlib.Set.Make` instantiations (emitted as `OcamlNative*`)

It exists both as documentation and as a QA harness (`npm run test:examples` compiles and runs it under dune).
