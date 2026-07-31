# Source-Native Target-Family Extraction Plan

This note records the ownership plan for `haxe_ocaml-cy8e`. It keeps
`SourceTargetCommon.hx` from becoming the permanent home for every
source-native target family while preserving current target IDs, emitted
artifacts, and Haxe 4.3.7 parity expectations.

This is an architecture checkpoint, not a behavior change. It does not move
README or North Star production-readiness bars unless strict gates and public
usability evidence change.

SOURCE_NATIVE_TARGET_FAMILY_PLAN:PASS

## Current Inventory

`SourceTargetCommon.hx` currently spans several independent responsibilities:

- target enum, descriptors, registrations, and the `emitTarget` dispatch path
  for `Python`, `Java`, `Cs`, `Php`, and `Lua`;
- executable, source-set, jar, dll, and library-output packaging for Java and
  C#;
- shared expression and statement rendering through `renderExpr`,
  `renderStmt`, `renderFunctionStmts`, switch/try/lambda lowering, local
  tracking, and return-expression helpers;
- target syntax and intrinsic surfaces such as `php.Syntax`, `__php__`,
  `php.Boot`, PHP superglobals, `cs.Lib`, and `__cs__`;
- Java support-class rendering, import stubs, runci helpers, array/std/signal
  helpers, and utility-process support;
- C# support-class rendering, import stubs, runtime support source, runci
  helpers, namespace/header generation, and utility-process support;
- PHP support-class rendering, helper overloads, generic specialization,
  reflection/meta/class-name maps, resource tables, runtime template inclusion,
  and many PHP-specific field/call/type-hint helpers;
- Python package aliases, helper-class rendering, runtime/support template
  inclusion, same-class member rewrites, and macro/test helper shims;
- Lua runtime prelude wiring, support-class bindings, utility-process support,
  main static helpers, and Lua-specific expression/statement forms.

Some extraction seams already exist:

- `SourceNativeBackend.hx` is the public registration facade and should remain
  the stable descriptor/target-ID spine.
- `JavaSourceTargetCore.hx` and `PhpSourceTargetCore.hx` are dedicated entry
  modules but still delegate to `SourceTargetCommon.emitTarget`.
- `SourceMvpTargetCore.hx` keeps Python, C#, and Lua behind one shared MVP
  entry while their target-specific ownership is still being split.
- `packages/hxhx-core/source-templates/` already contains stable runtime or
  support templates for `cs`, `java`, `lua`, `php`, and `python`.
- [`SOURCE_NATIVE_RUNTIME_PACKAGING_STRATEGY.md`](../02-user-guide/SOURCE_NATIVE_RUNTIME_PACKAGING_STRATEGY.md)
  defines the runtime-template direction; this plan defines target-family
  module ownership around that direction.
- `SourceIdentifier` owns the shared ASCII identifier subset,
  `PhpName` owns PHP reserved identifiers and type-path namespace spelling,
  and `PhpSyntax` owns deterministic PHP quoting and associative-array
  fragments.

## Ownership Rules

Keep common source-native code limited to genuinely shared compiler concerns:

- the `SourceNativeTarget` enum while callers still use it;
- temporary dispatch glue needed to preserve target IDs and CLI routing;
- template loading helpers such as `readSourceNativeTemplate` and
  `appendSourceNativeTemplateLines`;
- target-neutral program traversal utilities;
- target-neutral expression/statement lowering only when the rule is identical
  across target languages and does not encode runtime/API behavior.

Move target-specific work behind target-owned modules:

- packaging, output paths, executable/library construction, and host-tool
  commands;
- reserved words, identifier rules, namespace/package/module names, and
  file-path mapping;
- import stubs, runci helper stubs, support-class renderers, and test harness
  shims;
- runtime template inventories and target-language support modules;
- generated target tables such as PHP class-name, metadata, reflection, enum,
  resource, and overload maps;
- target-native syntax surfaces and intrinsics, including `php.Syntax`,
  `__php__`, `cs.Lib`, and `__cs__`.

Stable target-language runtime bodies belong in templates or repo-owned runtime
support modules. Generated glue may stay compiler-owned when it depends on the
typed program, such as resource tables, reflection visibility tables, class-name
maps, entrypoint wrappers, and metadata maps.

Extern/core API surfaces should be real extern/core declarations, runtime
modules, templates, or intrinsic lowering. Do not add fake generated classes to
`SourceTargetCommon.hx` merely to satisfy one target failure when the correct
model is target-owned API or syntax behavior.

## Conservative Extraction Order

1. Preserve `SourceNativeBackend.hx` as the registration facade.
   New target-family modules must keep target IDs, descriptors, capabilities,
   CLI routing, and emitted artifact contracts stable.

2. Move Java implementation behind `JavaSourceTargetCore`.
   Java already has a dedicated entry module and a smaller target-specific
   surface: packaging/source-set output, import stubs, runci helpers, support
   classes, array/std/signal helpers, and utility-process support.

3. Continue PHP runtime-template split, then move PHP-owned lowering behind
   `PhpSourceTargetCore`.
   PHP is the largest family and should move after stable runtime bodies,
   generated tables, resource support, helper overloads, and intrinsic surfaces
   have clear ownership boundaries. The
   [PHP render-session hard-cut plan](PHP_RENDER_SESSION_HARD_CUT_PLAN.md)
   defines the state-lifetime boundary for that move: immutable program facts,
   sealed per-function lowering plans, explicit lexical scopes, and no
   process-global current-renderer pointer. `SourceIdentifier`, `PhpName`, and
   `PhpSyntax` are the first bounded extractions: one shared base identifier
   contract plus PHP-owned naming and syntax, all with explicit inputs and no
   compiler/request state.

4. Split C# from the shared MVP path before adding broader C# API/runtime
   support.
   A future `CsSourceTargetCore` should own C# packaging, namespace/header
   generation, import stubs, runtime support source, `cs.Lib` and `__cs__`
   intrinsics, runci helpers, and utility-process support.

5. Split Python and Lua after their template inventories are guarded.
   Future `PythonSourceTargetCore` and `LuaSourceTargetCore` modules should own
   package/module aliasing, helper-class rendering, runtime/support templates,
   macro/test shims, main support, and target-specific expression forms.

6. Extract shared lowering only after target modules own packaging and runtime
   surfaces.
   A later `SourceSharedLowering`, `SourceNameModel`, or similar module should
   contain only target-neutral Haxe lowering facts, not target-family runtime
   APIs or syntax shims.

This order is intentionally incremental. Bounded Full 1.0 repairs may still
touch `SourceTargetCommon.hx` when the fix is narrow, covered, and recorded in
the owning bead, but another broad runtime/API surface should create or use a
target-owned module first.

## Guardrails

Allowed during this checkpoint:

- docs, inventories, and CI guards that clarify target ownership;
- moving stable target-language bodies into templates;
- extracting packaging or support rendering into target-owned modules without
  changing generated behavior;
- adding focused tests that prove emitted artifacts remain equivalent after an
  extraction;
- urgent bounded Full 1.0 repairs with focused coverage and a bead note that
  records why the mega-file touch was acceptable.

Blocked without a separate architecture bead or review:

- broad new target-runtime or stdlib API behavior inside
  `SourceTargetCommon.hx`;
- fake generated classes for target extern/core APIs that should be
  declarations, templates, runtime modules, or intrinsics;
- expanding PHP/C#/Java/Python/Lua runtime support by moving large inline
  `out.push` blocks from one common helper to another;
- weakening Haxe 4.3.7 parity or upstream-oracle expectations to make a
  source-native target pass;
- README or North Star progress-bar movement from internal extraction planning
  alone.

## Validation

Minimum validation for this plan and the first non-semantic extractions:

- `npm run guard:source-native-target-family-plan`
- `npm run test:m14:source-native-backend-smoke`
- target-specific smoke or oracle runs when an extraction moves generated
  behavior for one family
- README/North Star progress bars recorded as unchanged unless strict gate and
  public usability evidence changes

The first implementation slices should compare generated files or runtime
output before and after extraction. Passing a local smoke remains supporting
evidence; upstream Haxe 4.3.7 suite evidence stays the primary proof for strict
Full 1.0 claims.
