# Unicode code points in the OCaml String runtime

Upstream Haxe 4.3.7 eval counts a String in Unicode code points. The OCaml
runtime stores UTF-8 bytes, so `HxString` converts code-point indices to byte
offsets. Before this fixture, `"héllo😀".length` printed 10 instead of 6.

`PortableMain` runs the shared checks in
`test/fixtures/stage3_string_unicode/Main.hx` through ordinary `reflaxe.ocaml`
output. It then checks String iteration, key-value iteration,
`StringTools.replace` and the positions `EReg` reports, which the Stage3
fixture cannot run yet. For example, after `~/b/` matches `"éb"`,
`matchedPos().pos` is 1 and `"éb".substr(1)` is `b`.

Every line except the last four matches upstream `haxe --interp` output. Those
four are OCaml-only:

- The three `ereg-sub-*` lines after `ereg-map` show `matchSub` counting code
  points, so it agrees with `matchedPos` and `String`. Upstream eval reads `pos`
  and `len` as bytes, so its `matchedPos` scan loop never ends on this text
  (`haxe_ocaml-4aoh2`).
- The `invalid` line covers ill-formed UTF-8. Upstream cannot create such a
  String, and the runtime counts each such byte as one character whose code is
  the byte.

Run it from the repository root:

```sh
PORTABLE_FIXTURE_ALLOWLIST=string_unicode_code_points npm run test:portable
```
