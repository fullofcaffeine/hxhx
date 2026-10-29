# Read enums from ordinary structural fields

This fixture stores `Item(37)` in an ordinary anonymous `value` field, then passes the field into an enum consumer. The native program must print `item:37`. Previously, it interpreted an enum box as a native constructor and printed a corrupt payload. Renaming the field to `payload` already worked.

The fixture covers the overlapping names `key`, `value`, `next` and `hasNext`, typedef aliases, constant constructors, nullable values, field writes and single receiver evaluation. A concrete StringMap enum iterator remains a native tuple projection. The lowering-report checks require the exact enum identity and its `HxEnum.unbox_or_obj` runtime use. The public inspector must reject changed enum identity, nullability or helper ownership.

Run the focused native fixture from the repository root:

```sh
PORTABLE_FIXTURE_ALLOWLIST=structural_enum_field_read bash scripts/test-portable.sh
```

The independent expectation is checked with upstream Haxe 4.3.7 on Neko. From this directory, compile `-cp src -main Main --neko <temporary-file>`, run it with Neko and compare stdout with `expected.stdout`.

## Separate IMap enum argument diagnostic

Defining `ocaml_structural_enum_imap_diagnostic` changes only the final map's static type to `haxe.Constraints.IMap<String, Payload>`. This is a retained diagnostic, not passing acceptance coverage. Upstream Neko produces the same expected text. The existing OCaml interface adapter instead boxes the enum at `set` and decodes it with plain `Obj.obj`, so the native tuple contains the wrong carrier. The original full failing source, expected output and emitted source were preserved in the PR92 audit before the focused repair.

The separate owner is `OcamlIMapInterfaceSyntax.decodeArgument`, tracked by `haxe_ocaml-2zrg9`. This fixture's enum field recovery does not repair that interface boundary or authorize enum unboxing on raw map tuples. The concrete StringMap control proves the tuple path independently. This distinction limits the repair's claim; it does not imply general IMap enum parity.

The per-field controls use separate records. Combining enum-valued `next` and `hasNext` fields also exposed a name-only iterator-literal classification failure, tracked by `haxe_ocaml-mo3tp`. Its exact failing source and log are retained separately in the PR92 audit. Upstream Haxe 4.3.7 on Neko accepts that combined record and matches the independent expected output. The native allocation failure remains outside this stored-enum read repair.
