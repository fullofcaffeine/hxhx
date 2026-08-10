# Expected-red evidence: portable portfolio restoration

Command:

```text
PATH="$PWD/node_modules/.bin:$PATH" PORTABLE_JOBS=2 \
PORTABLE_FIXTURE_ALLOWLIST=class_monomorphic_carrier,do_while_basic,dynamic_throw_control,enum_reflection_layout \
bash scripts/test-portable.sh
```

The four fixtures failed for separate reasons:

- `class_monomorphic_carrier` counted every instance boundary in the report.
  Its claim owns only `Counter.bump`.
- `enum_reflection_layout` expected lowering schema 73. The current compiler
  writes schema 79.
- `dynamic_throw_control` produced a valid Bool-to-Dynamic runtime requirement.
  The public inspector rejected it as unreferenced because it did not validate
  that call requirement family.
- `do_while_basic` reported the same standard Array runtime-use occurrence
  twice. The OCaml builder inserted the same built loop body into two syntax
  locations to emulate `do ... while`.

These are the intended red states. The first two need narrower current
expectations. The latter two need product fixes with focused regression checks.
