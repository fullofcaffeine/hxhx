# What Delegates Today (Truth Table)

This table answers one question quickly:
**does this lane require upstream `haxe` (stage0) at runtime compile time?**

| Lane / Command | Runtime compile path delegates to stage0? | Macro level | Plugin level | Intended use |
| --- | --- | --- | --- | --- |
| `haxe -lib reflaxe.ocaml ...` | **Yes** | Upstream macro behavior | N/A for `hxhx` loader | Mainstream Haxe + OCaml backend |
| `hxhx --target js-compat ...` | **Yes** | Delegated through upstream lane | N/A | Compatibility lane |
| `hxhx --target ocaml-compat ...` | **Yes** | Delegated through upstream lane | N/A | Compatibility lane with `reflaxe.ocaml` |
| `hxhx --target js ...` | **No** (native runtime path) | Native lane with current scoped support | Supports backend plugin loading in native path | Native JS backend validation/use |
| `hxhx --target ocaml ...` | **No** (native runtime path) | Native lane with current scoped support | Supports backend plugin loading in native path | Native OCaml backend validation/use |

## Two practical caveats

1. **Building binaries** and **running compile commands** are different:
   - runtime compile may be non-delegating,
   - but refreshing certain bootstrap artifacts can still use stage0.
2. Stage0-forbidden policy is enforced by dedicated checks; see:
   - `docs/00-project/STAGE0_POLICY.md`
   - `docs/01-getting-started/HXHX_SELF_HOSTING_CHECKLIST.md`
   - `docs/01-getting-started/TESTING.md`
