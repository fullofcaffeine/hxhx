# Unicode code points in the OCaml String runtime

Upstream Haxe 4.3.7 eval counts a String in Unicode code points. The OCaml
runtime stores UTF-8 bytes, so `HxString` converts code-point indices to byte
offsets. Before this fixture, `"héllo😀".length` printed 10 instead of 6.

`PortableMain` runs the shared checks in
`test/fixtures/stage3_string_unicode/Main.hx` through ordinary `reflaxe.ocaml`
output. It then checks String iteration, key-value iteration and
`StringTools.replace`, which the Stage3 fixture cannot run yet.

Every line except the last matches upstream `haxe --interp` output. The last
line is OCaml-only: upstream cannot create a String from ill-formed UTF-8, and
the runtime counts each such byte as one character whose code is the byte.

Run it from the repository root:

```sh
PORTABLE_FIXTURE_ALLOWLIST=string_unicode_code_points npm run test:portable
```
