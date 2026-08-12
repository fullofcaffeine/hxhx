# StringTools URL codec ownership

This fixture proves that both OCaml compilation modes use the Haxe-authored
`StringTools` URL codec. The default build can inline the implementation. The
`no-inline` build calls the generated `StringTools` functions. Both builds must
produce the same output.

The cases cover ordinary text, reserved characters, Unicode text, malformed
percent escapes, nested calls, static initialization, and source expressions
with side effects. The side-effect counter proves that each argument is
evaluated once.

Malformed URL input has different behavior on Haxe 4.3.7 targets. The OCaml
target deliberately preserves an invalid percent escape. The independent
oracle and this target-specific decision are documented in
`test/oracle/reflaxe_ocaml_early_return_control_seed/README.md`.

Run only this fixture with:

```bash
PORTABLE_FIXTURE_ALLOWLIST=string_url_codec_haxe_owner PORTABLE_JOBS=1 bash scripts/test-portable.sh
```
