# OCaml Runtime Capability Matrix (`portable` vs `metal`)

This matrix documents runtime module status for:

- `-D ocaml_profile=portable` (full compatibility-oriented runtime surface)
- `-D ocaml_profile=metal` (minimal native-oriented runtime layering + verifier constraints)

## Legend

- `portable`: module is part of the portable runtime surface.
- `metal-required`: always linked in metal mode.
- `metal-supported`: allowed in metal mode when referenced; linked on-demand.
- `metal-forbidden (current)`: blocked by current metal verifier policy.
- `tooling-only`: intended for hxhx/tooling internals, not application runtime usage.

## Matrix

| Runtime module (`std/runtime/*.ml`) | Portable | Metal | Notes / migration |
|---|---|---|---|
| `Date` | yes | `metal-supported` | Keep as typed date/time usage. |
| `EReg` | yes | `metal-supported` | Regex support is allowed; keep typed call sites. |
| `HxAnon` | yes | `metal-forbidden (current)` | Dynamic anonymous-object reflection path; migrate to typed records/classes. |
| `HxArray` | yes | `metal-supported` | Arrays are supported; future metal specialization may reduce runtime dependence. |
| `HxBacktrace` | yes | `metal-supported` | Runtime stack/backtrace helpers. |
| `HxBytes` | yes | `metal-supported` | Typed bytes APIs. |
| `HxEnum` | yes | `metal-supported` | Enum helpers for typed enum flows. |
| `HxFPHelper` | yes | `metal-supported` | Float helper utilities. |
| `HxFile` | yes | `metal-supported` | File I/O helper module; linked only when needed. |
| `HxFileStream` | yes | `metal-supported` | Stream/file descriptor helpers; linked only when needed. |
| `HxFileSystem` | yes | `metal-supported` | Filesystem helpers; linked only when needed. |
| `HxHxCompilerServer` | yes | `tooling-only` | hxhx compiler server support module. |
| `HxHxMacroRpc` | yes | `tooling-only` | hxhx macro-host RPC support module. |
| `HxHxNativeLexer` | yes | `tooling-only` | hxhx native frontend support module. |
| `HxHxNativeParser` | yes | `tooling-only` | hxhx native frontend support module. |
| `HxInt` | yes | `metal-supported` | Int helpers; hot-path specialization tracked separately. |
| `HxIterator` | yes | `metal-supported` | Iterator helpers for typed iteration patterns. |
| `HxMap` | yes | `metal-supported` | Map helpers; metal-specialized paths may reduce usage later. |
| `HxProcess` | yes | `metal-supported` | Process execution helpers; linked only when needed. |
| `HxReflect` | yes | `metal-forbidden (current)` | Reflection-heavy APIs are blocked by MetalProfileVerifier (`Reflect.*`). |
| `HxRuntime` | yes | `metal-required` | Core runtime module; always linked in metal mode. |
| `HxStdio` | yes | `metal-supported` | stdio helpers (`stdin/stdout/stderr`) when referenced. |
| `HxString` | yes | `metal-supported` | String helpers. |
| `HxSys` | yes | `metal-supported` | `Sys.*` host interaction helpers. |
| `HxType` | yes | `metal-forbidden (current)` | Reflection-style `Type.*` flows are blocked by verifier today. |
| `Math` | yes | `metal-supported` | Math helpers/constants. |
| `Std` | yes | `metal-supported` | Standard helper module; keep typed usages. |
| `haxe_CallStack` | yes | `metal-supported` | Haxe call stack/runtime diagnostics support. |

## Policy notes

- Metal mode links runtime modules **on-demand** from emitted references plus transitive runtime dependencies.
- Metal mode currently forbids dynamic/reflection-heavy constructs via `MetalProfileVerifier`:
  - `untyped`
  - `Reflect.*` and `Type.*`
  - explicit `Dynamic` hints in key typed positions
  - bootstrap fallback nodes (`EUnsupported`, `ETryCatchRaw`, `ESwitchRaw`)
- These constraints are intentional for predictable native performance and deterministic semantics.

## Related docs

- Profile contract and verifier error map: `docs/02-user-guide/OCAML_PROFILE_CONTRACT.md`
- Backend layering overview: `docs/02-user-guide/HXHX_BACKEND_LAYERING.md`
