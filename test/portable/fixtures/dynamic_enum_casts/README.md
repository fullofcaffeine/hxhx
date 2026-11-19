# Casts from `Dynamic` to an enum

`cast` of a `Dynamic` that holds an enum value must give that value, as upstream Haxe 4.3.7
does: `Green` stays `Green`, and `Circle(4)` keeps its argument. A Dynamic enum is boxed with
its enum name (`HxEnum.box_if_needed`). The assignment path unboxed it with
`HxEnum.unbox_or_obj`, but the cast path used a bare `Obj.obj` on the box, so the native
program printed `blue` for `Green` and a garbage radius for `Circle(4)`. The conversion table
`OcamlValueConversion` now gives casts the same unbox (`haxe_ocaml-9cqxj`, found by an
independent review of PR #211).

Run `PORTABLE_FIXTURE_ALLOWLIST=dynamic_enum_casts bash scripts/test-portable.sh`.
