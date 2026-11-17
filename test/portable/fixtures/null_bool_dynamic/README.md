# `Null<Bool>` values in `Dynamic`

A `Null<Bool>` value that enters `Dynamic` or `Any` must still be a Boolean: `Std.string`
prints `true`, and `Std.isOfType(value, Bool)` is `true`, as in upstream Haxe 4.3.7. The
fixture also reads the values back as `Null<Bool>` and `Bool`, and covers `null` and a cast
to `Dynamic`.

`reflaxe.ocaml` stores `Null<Bool>` as an `Obj.t` that holds a plain OCaml `bool`.
`Dynamic` needs the tagged form from `HxRuntime.box_bool`, because a plain `true` is the
same immediate as the integer `1`. The value went into `Dynamic` unchanged, so it printed
`1` and tested as an `Int` (`haxe_ocaml-9cqxj`, the silently wrong cell of the
representation matrix). The conversion table `OcamlValueConversion` now adds the tag.

Run `PORTABLE_FIXTURE_ALLOWLIST=null_bool_dynamic bash scripts/test-portable.sh`.
The portable runner builds and runs native output against expected.stdout.
The extra test compares the same program with upstream Haxe eval.
