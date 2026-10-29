# Enum identity planning

This fixture verifies decisions before OCaml syntax generation. Ordinary enum
comparisons must retain their enum name and exact typed source occurrence.
Each operand owns one call to `HxEnum.unbox_or_obj`. The fixture rejects
changed operators, enum names, function revisions, missing helpers, and an
attempt to substitute the boxing helper.

Payload construction also retains its constructor name and argument count.
The fixture rejects changed construction facts and unrelated source nodes.
Null literals, Dynamic values, and nested function bodies do not become outer
enum comparisons.

Run from the repository root:

```sh
npm run test:reflaxe-ocaml:enum-identity
```

The runtime-ownership aggregate includes this command. Actual compilation and
runtime behavior have a separate observer in
`test/portable/fixtures/nullable_enum_comparison`.
