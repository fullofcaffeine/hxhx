# What Delegates Today (Canonical Target-Preset Truth Table)

This table answers one question quickly:
**for each target preset, does runtime compilation require upstream `haxe` (stage0)?**

| Target preset / command | Lane kind | Runtime compile path delegates to stage0? | Macro level | Plugin level | Intended use |
| --- | --- | --- | --- | --- | --- |
| `haxe -lib reflaxe.ocaml ...` | Upstream lane | **Yes** | Upstream macro behavior | N/A for `hxhx` loader | Mainstream Haxe + OCaml backend |
| `hxhx --target js-compat ...` | Delegated compat lane | **Yes** | Delegated through upstream lane | N/A | Compatibility lane |
| `hxhx --target ocaml-compat ...` | Delegated compat lane | **Yes** | Delegated through upstream lane | N/A | Compatibility lane with `reflaxe.ocaml` |
| `hxhx --target js ...` | Native lane | **No** (native runtime path) | Native lane with current scoped support | Supports backend plugin loading in native path | Native JS backend validation/use |
| `hxhx --target ocaml ...` | Native lane | **No** (native runtime path) | Native lane with current scoped support | Supports backend plugin loading in native path | Native OCaml backend validation/use |

Source for target preset behavior:

- `packages/hxhx/src/hxhx/TargetPresets.hx`

## Two practical caveats

1. **Building binaries** and **running compile commands** are different:
   - runtime compile may be non-delegating,
   - but refreshing certain bootstrap artifacts can still use stage0.
2. Stage0-forbidden policy is enforced by dedicated checks; see:
   - `docs/00-project/STAGE0_POLICY.md`
   - `docs/01-getting-started/HXHX_SELF_HOSTING_CHECKLIST.md`
   - `docs/01-getting-started/TESTING.md`
