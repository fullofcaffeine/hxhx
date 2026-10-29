# Native compiler metadata check

This fixture compiles the compiler's JSON parser and metadata readers to OCaml.
It checks nested JSON values, plugin manifest fields, macro receipt versions,
and artifact digests. Expression preprocessing is disabled to exercise the
same representation constraint as the compiler source build.

Run from the repository root with Haxe 4.3.7, Reflaxe, OCaml, and Dune installed:

```sh
npm run test:m14:compiler-metadata-native
```

The unique `CompilerMetadataNativeTest` entry point prevents another classpath's
`Main` from being selected. The stdout comparison proves that the intended
fixture ran.

The inferred OCaml interface must also return the concrete `CompilerJsonValue`
type. Correct stdout alone cannot detect an unsafe cast that erases that type.

The command has a 15-minute build deadline and requires native compilation to
succeed. It belongs to the required Core OCaml packaging test group.

This fixture proves the native metadata readers. Full compiler source builds,
bootstrap regeneration, and plugin package checks remain separate evidence.
