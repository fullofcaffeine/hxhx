# Nullable enum locals passed to constructors

A nullable local must keep its nullable storage even when its initializer is a
known enum constructor. Constant folding must not change that contract.

This fixture passes four nullable values to a recursive enum constructor:
null, a conditional payload, an always-present payload, and a typedef-backed
nullable payload. Upstream Haxe 4.3.7 establishes the expected output. The
portable runner generates OCaml, builds it, and compares the executable output.

Before the repair, the always-present local used concrete enum storage. Its
next use expected nullable storage, so native OCaml compilation failed.

Run from the repository root:

```sh
HAXE_BIN="$PWD/node_modules/.bin/haxe" \
PORTABLE_FIXTURE_ALLOWLIST=nullable_enum_constructor_local \
bash scripts/test-portable.sh
```

Tracked by `haxe_ocaml-23goa`. This regression does not establish full enum or
compiler compatibility and does not change the README Goals status.
