# Unicode source offsets

The compiler lexer uses the string indices provided by its runtime. Those
indices can count bytes, UTF-16 units or Unicode characters. Shared class
origins need the same Unicode character offset on every runtime.

This fixture compiles the production `HxSourceOffsetCursor` through
`reflaxe.ocaml` and checks ASCII plus two-, three- and four-byte characters.
Repeated boundaries keep the same offset. Rewinds and out-of-range boundaries
fail before changing the cursor.

Run it from the repository root:

```sh
PORTABLE_FIXTURE_ALLOWLIST=source_offset_unicode npm run test:portable
```

The parser regression also compares actual class ranges with upstream Haxe:

```sh
haxe test/m14_class_source_range_test.hxml
```
