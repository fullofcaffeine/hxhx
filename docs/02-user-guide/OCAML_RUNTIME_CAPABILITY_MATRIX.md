# OCaml Runtime Capability Matrix (`portable` vs `metal`)

This matrix documents runtime module status for:

- `-D ocaml_profile=portable` (full compatibility-oriented runtime surface)
- `-D ocaml_profile=metal` (minimal native-oriented runtime layering + verifier constraints)

## How runtime source is checked

The compiler's compatibility runtime is a set of OCaml source modules copied into generated projects when Haxe behavior needs them. For example, a growable Haxe array can require `HxArray.ml`; that module in turn uses the core support in `HxRuntime.ml`.

[`runtime-manifest.json`](../../packages/reflaxe.ocaml/std/runtime/runtime-manifest.json) is the locked catalog for those source files. It records, for every module:

- the exact source-file SHA-256 digest;
- its direct dependencies on other runtime modules;
- required Dune libraries such as `unix` or `str`;
- whether it belongs to application output or compiler tooling;
- eligible build profiles and the source license.

Validation stops before copying if a declared file is missing or modified, an unlisted OCaml source appears, a dependency is unknown, or a requested module is not legal for that profile. This prevents an incomplete or locally modified runtime from quietly entering generated output.

This catalog answers “which reviewed source files implement this module?” The
runtime requirement ledger also answers questions such as “which Haxe
expression required `HxInt` or `HxArray`?”, “why did the compiler-generated
`HxTypeRegistry` require `HxType`?”, “why does the typed standard-I/O facade
require `HxStdio`?”, and “why is the core runtime packaged?” in
`ocaml_runtime_requirement_report.json` on every runtime-enabled build. Each
explanation names the supported Haxe type, generated module, compiler rule, or
typed native boundary; the decision that required support; the implementation
feature; the eligible profiles; and the checked root module. The report then
follows that root through the catalog to the exact source hashes, dependencies,
Dune libraries, profiles, and licenses that were packaged.

When `-D ocaml_lowering_report` is enabled, `ocaml_lowering_report.json` shows
the same requirement identities next to the typed assignment/update plans that
caused them. This makes it possible to trace one source operation through the
compiler decision and into the packaged OCaml files without searching generated
source text. Native-boundary explanations additionally name the typed extern
declaration that made the checked target-runtime call.

Those explanations currently cover core packaging, the compiler-generated type
registry, explicitly declared static native runtime boundaries, and the
admitted assignment/update family. Other compiler paths still
discover runtime names from generated OCaml structure or explicitly declare
them while building string/template output. The requirement report lists those
names under `unexplainedCompilerObservedModules`, so the whole-program runtime
authority and generated artifact manifest correctly remain incomplete under
`haxe_ocaml-0uwin`.

Typed target-runtime externs declare their need by capability rather than by
copying a module name into the packaging plan. For example,
`@:ocamlRuntime("haxe-standard-io")` selects the checked `HxStdio`
implementation and is validated against the resolved `@:native` target. See
`OCAML_NATIVE_MODE.md` for the target-authoring contract. This metadata is not
used for ordinary external OCaml libraries.

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
| `HxAnon` | yes | `metal-forbidden (current)` | Dynamic anonymous-object reflection path (portable uses shape/slot runtime with explicit presence tracking + repeated-field cache); migrate to typed records/classes for metal. |
| `HxArray` | yes | `metal-supported` | Arrays are supported; future metal specialization may reduce runtime dependence. |
| `HxBacktrace` | yes | `metal-supported` | Runtime stack/backtrace helpers. |
| `HxBytes` | yes | `metal-supported` | Typed bytes APIs. |
| `HxEnum` | yes | `metal-supported` | Enum helpers for typed enum flows. |
| `HxFPHelper` | yes | `metal-supported` | Float helper utilities. |
| `HxFile` | yes | `metal-supported` | File I/O helper module; linked only when needed. |
| `HxFileStream` | yes | `metal-supported` | Stream/file descriptor helpers; linked only when needed. |
| `HxFileSystem` | yes | `metal-supported` | Filesystem helpers; linked only when needed. |
| `HxHxBackendPluginDynlink` | yes | `tooling-only` | Loads native backend plugins for `hxhx`; never an application runtime module. |
| `HxHxBackendPluginHost` | yes | `tooling-only` | Defines the native backend-plugin host boundary used by `hxhx`. |
| `HxHxCompilerServer` | yes | `tooling-only` | hxhx compiler server support module. |
| `HxHxMacroModuleDynlink` | yes | `tooling-only` | Loads native macro modules for `hxhx`; never an application runtime module. |
| `HxHxMacroModuleHost` | yes | `tooling-only` | Defines the native macro-module host boundary used by `hxhx`. |
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
| `HxThread` | yes | `metal-supported` | Thread primitives for `sys.thread.*` (locks, mutexes, conditions, semaphores, deque, TLS, thread messaging). |
| `HxType` | yes | `metal-forbidden (current)` | Reflection-style `Type.*` flows are blocked by verifier today. |
| `Math` | yes | `metal-supported` | Math helpers/constants. |
| `Std` | yes | `metal-supported` | Standard helper module; keep typed usages. |
| `haxe_CallStack` | yes | `metal-supported` | Haxe call stack/runtime diagnostics support. |

## Policy notes

- Metal mode always includes helper modules backed by an explicit runtime
  requirement. Compiler observations temporarily supply roots for the remaining
  families. The locked source manifest, rather than an OCaml text scan, supplies
  and validates every transitive runtime dependency.
- Runtime planning can be overridden in Stage0 with:
  - `-D ocaml_runtime_mode=full|selective`
  - `-D ocaml_runtime_modules=<comma-separated module list>`
  - `-D ocaml_runtime_no_infer`
    - disables compiler-observed discovery, but never removes a module already
      recorded as necessary for a Haxe operation, generated module, or
      packaging rule
    - remains fail-closed: manual seeds must include every runtime module still
      observed from an unmigrated compiler family
- Metal mode currently forbids dynamic/reflection-heavy constructs via `MetalProfileVerifier`:
  - `untyped`
  - `Reflect.*` and `Type.*`
  - explicit `Dynamic` hints in key typed positions
  - bootstrap fallback nodes (`EUnsupported`, `ETryCatchRaw`, `ESwitchRaw`)
- Stage0 metal boundary checks can be downgraded to warnings with
  `-D ocaml_metal_allow_fallback` during migration/debugging.
- Portable profile can enforce `ocaml.*` usage policy with:
  - `-D ocaml_portable_native_surface=warn|allow|error` (default: `warn`)
- Portable builds can opt in strict metal checks for selected modules via `@:haxeMetal`.
- Metal mode has no implicit fallback to portable; switching lanes requires explicit
  `-D ocaml_profile=portable`.
- Optional runtime token-scan fallback (`-D ocaml_runtime_token_scan_fallback`) requires
  `-D ocaml_runtime_debug_lane`; it is debug-only and must not be enabled for release builds.
- These constraints are intentional for predictable native performance and deterministic semantics.

## `HxArray` adaptive storage strategy (portable runtime)

`HxArray` now uses deterministic adaptive stores in portable mode:

- `ObjStore` for fully dynamic / nullable slots.
- `IntStore` for dense integer arrays.
- `FloatStore` for dense float arrays.
- `StringStore` for dense string arrays.

Promotion/deopt rules:

- `ObjStore` promotes to typed stores only when live slots are dense, non-null, and uniformly typed.
- Typed stores deopt back to `ObjStore` when an operation requires nullable holes (for example sparse set or grow-resize) or mixed-type writes.
- Deopt is explicit and local to `HxArray`; portable semantics remain unchanged.

This keeps portable as the default compatibility lane while reducing boxing overhead for typed hot loops (for example `Array<Int>` accumulation workloads).

## Related docs

- Profile contract and verifier error map: `docs/02-user-guide/OCAML_PROFILE_CONTRACT.md`
- Backend layering overview: `docs/02-user-guide/HXHX_BACKEND_LAYERING.md`
