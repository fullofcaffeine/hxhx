# Guarded enum-pair switch with a throwing fallback

The constructor accepts matching operation/expression pairs and throws a String
for all other pairs. The guard compares two bound operator values. Both the
accepted branches and the failing guard must match upstream Haxe/eval.

Haxe can lower the tuple match into nested enum-index switches. An exhaustive
inner switch must not build an unused fallback and register a runtime operation
that never reaches generated output. The final runtime-use check remains enabled.

Run from the repository root:

```sh
PORTABLE_FIXTURE_ALLOWLIST=switch_guarded_enum_pair_throw bash scripts/test-portable.sh
```
