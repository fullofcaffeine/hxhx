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

## Subclass catch representation red state

The first runtime-tagged catch fixture proved only which branch ran. A stronger
version added `Base.label` and `Child.detail`, then read those fields after
exact, superclass, base-static-type, and `Dynamic` catches.

Command:

```text
PATH="$PWD/node_modules/.bin:$PATH" \
PORTABLE_FIXTURE_ALLOWLIST=typed_catches PORTABLE_JOBS=1 \
bash scripts/test-portable.sh
```

The generated source built, but the executable exited with signal 11. The
generated layouts explained the failure:

```text
type base_t = { __hx_type : Obj.t; mutable label : string }
type child_t = { __hx_type : Obj.t; mutable detail : int }
```

The runtime class tag correctly identified `Child` and `Base`. However, a tag
cannot make those two OCaml record layouts compatible. The compiler already
computed a base-prefix layout for inheritance chains with method slots; the
fix applies that same layout to field-only chains. After the fix, `child_t`
contains `__hx_type`, `label`, then `detail`, and the same command passes.
