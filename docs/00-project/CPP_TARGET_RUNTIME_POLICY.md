# Cpp Target Runtime Policy

This note is the runtime-helper invariant and default-stub audit for
`haxe_ocaml-moz7`. It blocks new broad Cpp runtime or stdlib semantics from
being added to `CppTargetCore.hx`, `CppProgramPrelude.hx`, or
`CppRuntimeSupport.hx` as ordinary helper burn-down work.

Strict Cpp Gate3 remains red. Runtime helper work is internal blocker burn-down
unless upstream-derived strict gates and public usability evidence change.
README and North Star progress bars stay unchanged by default.

## Classifications

Every Cpp runtime/helper surface must be classified before it is expanded:

- `parity_support`: behavior-scoped support with upstream Haxe 4.3.7 oracle
  evidence for meaningful edge cases.
- `bounded_bringup_support`: target-owned support used to unblock a narrow smoke
  or strict-gate frontier. It is not parity evidence and must name its limits.
- `declaration_only_support`: type/signature support only. It must not imply the
  runtime behavior exists.
- `unsupported_diagnostic`: explicit refusal or diagnostic. Prefer this to fake
  generated classes, no-op behavior, or silent target defaults.
- `review_required`: too broad or cross-cutting to expand without a behavior
  spec, oracle plan, and second-pass architecture review.

## Invariants

All new or expanded Cpp runtime/helper support must satisfy these invariants:

- It is repo-owned and provenance-safe. Do not copy or translate upstream Haxe
  compiler/test code.
- It has an observable behavior scope pinned to Haxe 4.3.7 expectations, or it
  is explicitly labeled `bounded_bringup_support` or `unsupported_diagnostic`.
- It states the validation lane: focused local smoke, strict stage0-free Cpp
  diagnostic, upstream oracle matrix, or Full1 gate.
- It does not silently return default values for missing behavior unless that is
  the documented Haxe behavior for the supported scope.
- It does not move broad semantics from `CppTargetCore.hx` into
  `CppProgramPrelude.hx` or `CppRuntimeSupport.hx` without classification.
- It uses declaration-only surfaces, target runtime modules, templates, or
  intrinsic lowering instead of fake generated classes when those are the real
  boundary.
- It records deterministic inclusion/order expectations when generated output is
  affected.
- It reviews null, exceptions, Dynamic/Reflect, metadata, comparisons,
  NaN/Infinity/signed zero, parsing/formatting, JSON, binary float encoding, and
  serialization impact whenever the surface can touch them.
- It records README/North Star status. The default is "progress bars unchanged"
  unless production readiness actually changes.

## CppRuntimeSupport Audit

| Surface | Current classification | Audit note |
| --- | --- | --- |
| `borrowedSharedPtrLines` | `bounded_bringup_support` | Target-internal ownership bridge. Mechanical support, not a user-facing runtime claim. |
| `resourceLines` | `bounded_bringup_support` | Target-owned resource table. Needs oracle cases for missing names, byte/string conversion, and list ordering before parity. |
| `sha1Lines` | `bounded_bringup_support` | Compact primitive helper. Must be frozen behind edge-case oracle coverage before parity claims. |
| `missingDeclarationLines` | `declaration_only_support` plus partial bring-up | `IMap` is signature-only; `StringMap` includes a small implementation; `Date.toString` currently returns an empty string and is not parity. |
| `missingMethodReturnType` | `declaration_only_support` | Signature helper only. It must not imply behavior exists. |
| `anySupportLines` | `bounded_bringup_support`, `review_required` before expansion | `Any.__promote` returns `T{}` for unsupported conversions. That is smoke scaffolding, not Dynamic parity. |
| `listSupportLines` | `bounded_bringup_support` | Package/source-gated stdlib `List<T>` / `haxe.ds.List<T>` support used to reduce strict Cpp helper-render pressure. It preserves common List API shape and existing iterator helper return types, but broader collection parity still needs oracle coverage. |
| `fpReinterpretLines` | `review_required` | Binary float support touches NaN, Infinity, signed zero, and platform representation. Use [`FLOAT_NUMERIC_REVIEW_GATE.md`](FLOAT_NUMERIC_REVIEW_GATE.md) before expansion. |
| `dateIntrinsicLines` | `bounded_bringup_support` | UTC construction helper. Date/timezone behavior needs oracle coverage before parity. |
| `stdIntrinsicLines` | `bounded_bringup_support` | `parseInt`, integer literal, and Int64 narrowing helpers. Numeric parsing changes must use oracle evidence. |
| `baseCodeLines` | `bounded_bringup_support` | Compact BaseCode support. Needs invalid input, empty input, byte, and non-ASCII oracle coverage before parity. |
| `serializerEnumSupportLines` | `bounded_bringup_support`, `review_required` before expansion | Target-owned Cpp `Serializer` / `Unserializer` support for focused enum carrier cases only: constructor-name `w` tokens and constructor-index `j` tokens via `Serializer.USE_ENUM_INDEX`, enum name, constructor identity, payload order, and original `std::any` payloads for zero-arg and `Int`/`String` payload smoke coverage. It is not broad Serializer parity. |
| `vectorSupportLines` | `bounded_bringup_support` | Vector/array helpers use target defaults for some invalid access/empty cases. Not broad Array parity. |
| `sysEventLoopLines` | `bounded_bringup_support`, not parity | Lock/Mutex have bounded primitive support, while Timer/Http/MainLoop/EntryPoint remain simplified/no-op in several places. They unblock compile/smoke surfaces only; see [`CPP_SYS_EVENT_LOOP_SMOKE_AUDIT.md`](CPP_SYS_EVENT_LOOP_SMOKE_AUDIT.md). |
| `rttiMetaLines` | `bounded_bringup_support`, `review_required` | Metadata and Reflect helpers mostly return empty/default values or no-op mutation. This is false-parity risk; see [`CPP_REFLECT_DYNAMIC_SUPPORT_AUDIT.md`](CPP_REFLECT_DYNAMIC_SUPPORT_AUDIT.md). |
| `enumValueTypeLines` | `bounded_bringup_support`, `review_required` before expansion | Lightweight enum carrier. See the enum carrier behavior matrix below; current support is not enum parity. |
| `anyIsTypeLines` | `bounded_bringup_support`, `review_required` | Partial `Std.isOfType`/Dynamic-style checks for a small set of C++ carriers. |
| `enumValueDynamicLines` | `bounded_bringup_support`, `review_required` | Dynamic enum helpers and `std::any` conversions return defaults for unsupported values; Float conversion catches parse errors and returns `0.0`. |
| `compareLines` | `review_required` | Comparison touches Dynamic, enums, strings, numbers, NaN, and signed zero. Use [`FLOAT_NUMERIC_REVIEW_GATE.md`](FLOAT_NUMERIC_REVIEW_GATE.md) before expansion. |

## C++ Prelude and CppTargetCore Runtime Helper Audit

Parameterless enum Map keys have `bounded_bringup_support`. The Haxe enum plan
admits an ordinary nongeneric enum only when every constructor has no parameters.
The existing descriptor validates key identity before a constructor index selects
integer-keyed physical storage. The source runtime family remains EnumValueMap;
erased Map-family tests remain rejected. This does not grant object-identity
equality to enums. Payload-bearing and generic enums require a structural key
plan under `haxe_ocaml-60jwu`. Null-key error timing and the actual generic
EnumValueMap comparison provider remain outside this focused proof. The native
descriptor accessor checks physical identity only; it does not select semantics.
README and North Star progress estimates remain unchanged.

`CppManagedValueTransfer` and `CppManagedNullCompare` provide
`bounded_bringup_support` for null-preserving common-value storage. The focused
null fixture covers locals, fields, arguments, results, statics, arrays, and
String-backed abstracts against upstream Haxe. Null comparisons inspect the
value tag after evaluating both operands in source order. They do not compare
object payloads or perform numeric coercion. Nullable scalar values keep their
boxed representation; non-nullable scalar destinations reject literal null.
The existing cast plan resolves abstract backing types before storage selection.
Incomplete types, checked casts, and representation-changing conversions remain
rejected. No Float arithmetic, parsing, serialization, reflection, or general
Dynamic conversion behavior is added. Full1 and public readiness remain unchanged.

`CppManagedStaticUpdate` provides `bounded_bringup_support` for increment and
decrement on exact mutable Int static fields. It uses existing field ownership,
write-permission checks, and integer wraparound operations. Prefix and postfix
results are covered by the collecting static-field observer. The unchanged Map
runtime-family source also verifies a discarded increment and exactly-once
evaluation. Instance-field updates and wider numeric conversions remain unsupported.

| Surface | Current classification | Audit note |
| --- | --- | --- |
| `CppProgramPrelude` fixed prelude plus string/vector/base64/basecode/hash/resource lowering | `bounded_bringup_support` | The extracted module preserves the established output order; compact target-owned primitives are acceptable when edge-case oracle coverage exists. Do not broaden them without behavior specs. |
| `runtime/cpp/ManagedHeap.hpp` | `bounded_bringup_support`, not source parity | Native allocation, explicit roots, and precise non-moving collection only. Haxe must own payload selection, capture placement, and call/root plans. Independent graph, injected allocation-failure, and sanitizer tests run through `test:m14:cpp-managed-heap`. Generated-source integration, host memory exhaustion, external retention, and performance remain unproved under `haxe_ocaml-9jezt`. |
| `runtime/cpp/ManagedValue.hpp` | `bounded_bringup_support`, not source parity | Common value transport and array storage preserve allocation identity through erasure. Physical layout checks protect recovery; they do not implement `Std.isOfType`, reflection, numeric conversion, or Haxe indexing policy. Mixed graph and buffer-growth tests support the storage contract only. The native closure witness remains required. |
| `CppManagedClassStorage`, `CppManagedConstructor`, and `CppManagedInstanceField` | `bounded_bringup_support`, not broad class parity | Exact program-owned declarations select ordinary nongeneric instance layouts and authored constructor bodies. Arguments and receivers remain rooted through allocation and field writes. The native payload only stores and traces Haxe-selected fields. The class fixture checks source order, final initialization, nested fields, static construction, closure construction, and compound assignment against upstream Haxe. Inheritance, interfaces, generic layouts, instance field initializers, property accessors, general instance calls, and class reflection remain unsupported. This descriptor table must also own future class-value handles; do not add a second native registry. |
| `CppManagedStoragePlan` and `CppManagedFunctionOwner` | `declaration_only_support`, not execution admission | Promote exact captured bindings into shared cell plans and preserve their source allocation events. Ordinary roots require their exact projection object; closures require their exact cataloged expression. Root parameter order comes from semantic binding identities, and its ABI omits the closure environment. Root parameter promotion passes native lifetime checks, but general root-body emission and normal target integration remain required. Named functions keep initialize-once policy. Descendants share cell identities and receiver requirements remain explicit. Physical payload, call, and temporary-root plans must be complete before these facts authorize generation. |
| `runtime/cpp/ManagedCallable.hpp` and `CppManagedClosureAbi` | `bounded_bringup_support`, not source parity | Native cells preserve presence and the Haxe-selected write contract. Active invocation roots retain selected callables through replacement and unwind. The Haxe ABI plan uses cataloged semantic signatures, preserves source arity, and selects caller-owned roots for managed results. Generated native type checks and sanitizer invocation tests pass; normal source emission and external callback retention remain required under `haxe_ocaml-9jezt`. |
| `CppManagedRuntime` and its build macro | `bounded_bringup_support`, not source parity | Embed authored native headers with content hashes and publish them without checkout lookup. Upstream warm-build invalidation and source-free Neko publication pass. The ABI fixture compiles against published files only. Native hxhx bootstrap and normal target publication remain unproved. |
| `runtime/cpp/ManagedThrow.hpp` and managed source throw emission | `bounded_bringup_support`, not source parity | Evaluate an authored throw operand once and retain its existing managed value across native unwinding. Copies share a stable external root. Native sanitizer checks cover collection during unwinding, array mutation and identity, rethrow, escaped closures, and final release. The heap must outlive all retained transports. Source objects must not store this transport. Ordered catches, standard exception views, numeric matching, foreign errors, and ordinary target integration remain required under `haxe_ocaml-qrk0u`. |
| `CppManagedEnvironmentEmitter` | `bounded_bringup_support`, not source parity | Emit immutable environment fields and trace functions from exact captured binding identities. Generated cell, receiver, and empty layouts pass native sanitizer checks. Callers must root input cells before allocation. Function-body emission and complete temporary-root placement remain required under `haxe_ocaml-9jezt`. |
| `CppManagedCallEmitter` | `bounded_bringup_support`, not source parity | Generate ordered call blocks with roots for the selected callable, managed arguments, and managed results. Sanitizers cover collection during argument effects and exceptions. Null invocation preserves upstream argument effects. Inputs must already have source arity and conversions resolved. Normal source-call selection, callee parameter ingress, and complete function-body emission remain required. |
| `CppManagedCellEmitter` and `CppManagedParameterEmitter` | `bounded_bringup_support`, not source parity | Generate exact-event cell allocation, rooted reads/assignments, and parameter ingress. All incoming managed arguments acquire roots before promoted parameter allocation. Forced-collection observers cover right-hand-side effects, recursive cycles, and a returned child retaining an input array. Placing these operations in normal source bodies and replacing ordinary callable signatures/returns remain required under `haxe_ocaml-9jezt`. |
| `CppManagedFunctionBody` and `CppControlRegion` result transport | `bounded_bringup_support`, not source parity | Use one control-flow renderer for direct, Void, and caller-rooted returns. Exact root methods and nested closures preserve return destinations and lexical roots. The real counter factory and captured-array creator render their entire bodies; root branch, scalar, and void returns pass native checks. Root loop/catch projection, receiver transport, and normal carrier/signature/body-service integration remain required. |
| Managed Boolean condition emission | `bounded_bringup_support`, not source parity | Complete exact Bool expressions in a synchronous native scope before shared branch/loop control consumes the value. The unchanged original counter factory passes native lifetime checks. Collecting branch, while, and do-while conditions preserve evaluation counts and unwind roots on exceptions. Non-Boolean conditions and unadmitted source control expressions fail explicitly. The full original program still needs aggregate expressions and normal target integration. |
| `CppManagedFunctionEmitter` and `CppManagedBodyServices` | `bounded_bringup_support`, not source parity | Emit a checked method and its closures as one native unit, owning forward declarations, closure links, ABI signatures, parameter ingress, and body services. Counter and root-method observers use independently asserted native signatures. Mutated projections, local symbol collisions, and unadapted root defaults are rejected. Receivers, full common-carrier selection, and normal target integration remain required. |
| `CppManagedProgramEmitter` and `CppManagedStaticTarget` | `bounded_bringup_support`, not source parity | Link static calls through exact typed declaration identities and current semantic signatures. Shared call sequencing preserves argument effects and result roots. Native observers cover cross-method counter calls, later declarations, same-named methods on different classes, static calls from escaped closures, managed results, and void effects. Missing/wrong targets and stale/copied calls fail. Receiver effects, defaults, aggregate expression support, runtime publication, and normal target selection remain required. |
| `CppManagedLocalAccess` | `bounded_bringup_support`, not source parity | Resolve exact parameter, ordinary-local, and captured-cell reads, typed Boolean conditions, and same-type leaf returns. Authored conditional and child-capture returns pass native lifetime checks. General expressions, conversions, and normal target integration remain required. |
| `CppManagedRootedExpression` | `bounded_bringup_support`, not source parity | Emit an authored child function return through rooted environment construction and publication. Separate creator invocations preserve independent captured arrays after return. Only exact compiler-added callable annotations can be removed; authored casts require explicit conversion support. Normal C++ target integration remains required. |
| `CppManagedLocalStorage` | `bounded_bringup_support`, not source parity | Allocate ordinary roots and promoted cells at exact declaration events. An authored local survives creator exit; an authored named function retains its own callable identity and its cycle is collected after external roots leave. Uninitialized storage, other allocation events, conversions, compound updates, source calls, and normal target integration remain required. |
| `CppManagedPlace` and rooted assignment emission | `bounded_bringup_support`, not source parity | Retain a selected captured cell before RHS effects and publish assignment results after successful writes. Authored chained assignments, local/managed-parameter writes, and collecting closure replacement pass lifetime checks. Direct leaf-parameter writes, compound updates, conversions, general places, and normal target integration remain required. |
| `CppManagedSourceCall` and `CppManagedLeaf` | `bounded_bringup_support`, not source parity | Resolve callable locals from semantic signatures and use the shared native call sequencer. Source tests cover callee replacement during arguments, allocating argument closures, nested calls, Boolean/Void transport, and null-call argument effects. Direct integer returns finish collecting expression steps before scalar extraction. String uses common rooted transport to preserve null versus empty text; Bool, Int, and Float retain exact scalar transport without conversions or arithmetic. Exact arity is required; defaults, rest packing, other callee forms, conversions, null literal lowering, and normal target integration remain unfinished. |
| `CppManagedInteger` and rooted integer expressions | `bounded_bringup_support`, not source parity | Sequence exact Int operands left to right, use widened arithmetic for signed 32-bit wrapping, preserve prefix/postfix results on selected local or captured storage, and evaluate only the selected conditional branch. The authored recursive counter body passes after creator exit, including copies, independent creators, and cycle cleanup. Native entry symbols still come from the fixture; normal target integration and mixed object/array/callback proof remain required. Float, numeric conversions, and direct scalar-parameter writes are not admitted here. |
| `CppManagedAggregate`, retained aggregate occurrences, and `RecordPayload` | `bounded_bringup_support`, not source parity | Preserve exact aggregate types and ordered projected children. Construct parents and children in rooted storage, then publish only a completed result. Native sanitizer checks cover nested arrays and objects, an escaped callback sharing the array, initializer order, copied results, exception cleanup, and exact String bytes. Missing providers and unplanned conversions fail. Authored field access, iteration, reflection, and ordinary target integration remain required under `haxe_ocaml-9jezt`. |
| `LocalSlot`, compiler result declarations, and `CppManagedSwitch` | `bounded_bringup_support`, not source parity | Compiler temporary identities authorize deferred result assignment. Stack slots retain rooted values and distinguish unassigned storage from null. Literal scalar switches select once, defer default until other patterns fail, and preserve enclosing loop exits. Native checks cover collecting branches, early returns, nested switches, null, and exceptions. Ordinary uninitialized source variables and binding/extractor patterns remain unsupported at this boundary. |
| `CppManagedOutput` and `runtime/cpp/ManagedOutput.hpp` | `bounded_bringup_support`, not source parity | Explicit program bindings join selected Sys print/println declarations by exact identity. Haxe evaluates rooted operands before formatting Bool, Int, or String values. The native primitive writes and flushes exact bytes and reports I/O failure. Native observers cover UTF-8, embedded zeroes, null strings, collecting callbacks, argument exceptions, and escaped closures. Dynamic, Float, and object formatting, complete Sys behavior, and normal target integration remain required. |
| `CppRuntimeTypePlan` and `CppRuntimeType.validate` | `declaration_only_support`, `unsupported_diagnostic` | Plan exact cataloged class values and instance tests across functions and field initializers. Share descriptors by semantic target identity and retain real declaration owners. This does not provide native class-object storage, public reflection names, erased-value membership, or ordinary dynamic-target call admission. Unsupported execution still fails before publication. `m14_cpp_map_runtime_type_inventory_test.hxml` checks the real provider inventory; native Map and class-value contracts remain required. README/North Star progress bars are unchanged. |
| `renderMissingInterfaceDeclaration` and missing declarations | `declaration_only_support` | Signature/declaration boundary only. Avoid fake generated classes for runtime behavior. |
| `renderRttiMetaHelper` and `rttiMetaLines` callers | `bounded_bringup_support`, `review_required` | Empty/default metadata results must not count as strict Reflect/RTTI parity. |
| `renderDceReflectionHelperStringOverload` | `bounded_bringup_support` | Narrow string overload support for current DCE/reflection helper shapes. Expansion needs behavior cases. |
| `dceReflectionHelperCallExpr`, `Reflect.field`, `Reflect.callMethod`, `Reflect.isFunction` | `bounded_bringup_support`, `review_required` | Reflect field/call/mutation is partial and may return `std::any()` or `false`. Unsafe as parity evidence. |
| `Reflect.compare` / `Reflect.compareMethods` lowering | `review_required` | Must use [`FLOAT_NUMERIC_REVIEW_GATE.md`](FLOAT_NUMERIC_REVIEW_GATE.md) before expansion. |
| Serializer/Unserializer object and enum helper lowering | `bounded_bringup_support` for focused enum round trips; `review_required` before expansion | The supported runtime behavior is limited to focused enum round trips through target-owned support: constructor-name `w` tokens from `haxe_ocaml-73r4j` and constructor-index `j` tokens from `haxe_ocaml-nd2nh`. Object/class/reference/cache/custom-resolver/custom-hook behavior still needs the Serializer/Unserializer spec and oracle matrix before implementation. |
| Sys/event-loop and Http helper lowering | `bounded_bringup_support`, not parity | Simplified/no-op behavior is smoke support only; see [`CPP_SYS_EVENT_LOOP_SMOKE_AUDIT.md`](CPP_SYS_EVENT_LOOP_SMOKE_AUDIT.md). |
| Raw try/catch and dynamic fallback lowering | `bounded_bringup_support` | Catch-all fallbacks that return defaults are scaffolding unless explicitly oracle-backed. |

## Enum Carrier Behavior Matrix

This matrix exists because a Cpp strict timing checkpoint found repeated
`Assertation` enum-constructor helper cost. A direct shortcut that renders those
constructors as tag-returning methods would preserve today's generated Cpp shape
for some helpers, but it would also harden the current partial enum model.

The runnable Haxe 4.3.7 oracle seed for this matrix is repo-owned and should be
kept as the behavior source of truth before changing the Cpp enum carrier model:

```bash
npm run test:cpp-enum-carrier-oracle-seed
```

The runner enforces an upstream `haxe` version of `4.3.7`, executes
`test/oracle/cpp_enum_carrier_seed/src/Main.hx` with `--interp`, diffs against
`test/oracle/cpp_enum_carrier_seed/expected.stdout`, and writes
`.tmp/cpp-enum-carrier-oracle-seed/report.json`. On 2026-07-09 it reported:

```text
CPP_ENUM_CARRIER_ORACLE_SEED:PASS zero=2 payload=2 enumEq=3 switch=1 typeFactory=4 reflection=3 dynamic=2 serializer=4
```

The seed uses this enum:

```haxe
enum Color {
  Red;
  Green;
  Pair(i:Int, s:String);
}
```

The expected stdout pins zero-argument and payload `Std.string`, constructor
summary via `Type.enumConstructor` / `Type.enumIndex` /
`Type.enumParameters`, `Type.enumEq`, switch payload binders,
`Type.createEnum`, `Type.createEnumIndex`, `Type.allEnums`,
`Type.getEnumConstructs`, `Type.getEnumName`, Dynamic stringification, and
Serializer/Unserializer round-trip prerequisites. The current Cpp backend is
not expected to pass all of those behaviors yet; the seed defines the target
contract for follow-up implementation seams.

| Surface | Haxe 4.3.7 expectation | Current Cpp state | Decision |
| --- | --- | --- | --- |
| Zero-argument enum constructors | Values preserve constructor identity; `Std.string(Red)` is `Red`; `Type.enumEq(Red, Red)` is true. | Parser-scanned zero-arg constructors become enum metadata fields. Typed enum value contexts now create carriers with constructor tag/index metadata, and typed `Std.string` / `Type.enumEq` can read that metadata. Raw helper output may still use tag-shaped methods in non-carrier contexts. | Keep bounded support. A shortcut is only eligible after it proves it does not widen or confuse payload behavior. |
| Payload enum constructors | Constructor payloads are observable through `Std.string`, switch binders, equality, Dynamic, and reflection APIs. | Typed enum value contexts preserve two payload views on `std::shared_ptr<Enum>` carriers: string metadata for `Std.string` / focused switch binders, and original `std::any` payloads for equality, `Type.enumParameters`, and focused Serializer round trips. Payload constructor helper methods now return carrier instances instead of tag strings when rendered on enum carrier classes. Broad erased switch extraction and non-scalar payload support are still incomplete. | Continue as bounded bring-up. Do not optimize payload constructors as pure tag methods. |
| Switch payload binders | `case Pair(i, s)` binds the actual payload values. | Typed enum carrier switches can match constructor metadata and bind stringified payload metadata for focused cases. Non-string payload identity and broader erased/non-carrier extraction are still incomplete. | Not full parity. Any switch/payload expansion needs focused oracle cases and cannot be justified by render timing alone. |
| `Type.enumEq` | Equality compares constructor identity and payload values; differing payloads are not equal. | Same-carrier typed enum cases compare preserved tag/index/payload metadata, including static and dynamic factory-created carriers. Generic erased flows still depend on bounded helpers and are not full parity. | Expansion is `review_required`; a shortcut must not bypass payload equality requirements. |
| `Type.createEnum` / `Type.createEnumIndex` | Runtime factory calls create real enum values, including payload values for named constructors. | Static enum class plus literal constructor-name/index factory calls lower directly to typed metadata carriers. Dynamic constructor-name/index calls now route through a generated `Enum` metadata carrier and return typed carriers for known enum classes, preserving the original `std::any` payload vector alongside string metadata. | Treat as bounded bring-up. Serializer/Unserializer enum support must still wait for erased-flow and encoding prerequisites. |
| `Type.getEnumConstructs` / `Type.allEnums` | Construct names are complete and stable; `allEnums` returns zero-argument enum values. | Cpp now registers generated enum constructor metadata for known enum classes. `Type.getEnumConstructs` returns that constructor list, and `Type.allEnums<T>` builds typed zero-arg carriers while skipping payload constructors. Dynamic unknown enum metadata remains best-effort. | Keep as bounded typed-value support, not broad reflection parity. |
| Dynamic / `EnumValue` flows | Enum values keep constructor and payload identity when stored as `Dynamic` / `EnumValue`. | Typed enum carriers are converted to `std::shared_ptr<EnumValue>` when passed to `std::any` parameters. `EnumValue` now carries both stringified parameters and original `std::any` payloads, with erased equality falling back to string parameters for older metadata-only construction. Unsupported `std::any` values still default or return null. | Remains `review_required`; update `CPP_REFLECT_DYNAMIC_SUPPORT_AUDIT.md` when expanding beyond this typed-carrier boundary. |
| Serializer / Unserializer enum flows | Round trips preserve constructor name, constructor index mode, payload order, and payload values. | `haxe_ocaml-73r4j` adds bounded constructor-name support for generated enum carriers: `Serializer.run` emits `w` tokens with enum name and constructor tag, `Unserializer.run` decodes through `Type.createEnum<EnumValue>`, and focused runtime smoke proves zero-arg plus `Int`/`String` payload values survive the round trip. `haxe_ocaml-nd2nh` adds `Serializer.USE_ENUM_INDEX` support for the same focused carrier scope using upstream-compatible `j` tokens and `Type.createEnumIndex<EnumValue>` for zero-arg values. Custom enum resolvers, references/cache behavior, object/class payloads, arrays/maps, bytes, floats, and custom hooks remain unsupported or unclassified. | Keep as bounded bring-up. Use the Serializer matrix before expanding beyond this focused enum path. |

Decision for the `Assertation` timing seam:

- Do not add an `Assertation`-specific renderer shortcut.
- Do not add a general payload-constructor shortcut that returns only tags.
- A future zero-arg-only shortcut may be considered only after the helper can
  prove it never applies to payload constructors and generated output/runtime
  behavior remains equivalent for the supported scope.
- The first `haxe_ocaml-puquq` implementation seam is typed enum carrier
  metadata: generated enum carriers store constructor tag, index, and
  stringified payloads; typed `Std.string`, same-carrier `Type.enumEq`, and
  `std::any` erasure can consume that metadata. Later bounded slices added
  typed switch payload binders, metadata-backed dynamic `Type.createEnum` /
  `Type.createEnumIndex`, and typed `Type.allEnums` for zero-argument
  constructors.
- The `haxe_ocaml-a3xh8` slice added the next payload boundary: generated
  carriers and erased `EnumValue` now keep original payloads as
  `std::vector<std::any>` in parallel with the string metadata. `Type.enumEq`
  compares those original payloads for the supported scalar/erased enum cases,
  and `Type.enumParameters` returns the original payload vector. This is still
  intentionally smaller than parity: broad erased switch extraction and
  Serializer/Unserializer remain follow-ups.
- The `haxe_ocaml-73r4j` slice uses that carrier foundation for a focused
  Serializer/Unserializer enum round trip. It also changes rendered payload
  enum constructor methods from tag-string helpers to carrier factories, because
  serialization can only preserve payload order and values if the constructor
  call still has the original payload vector. The generated C++ smoke verifies
  constructor-name `w` encoding for a zero-arg enum and an `Int`/`String`
  payload enum. README and North Star progress bars stay unchanged because this
  is still a Cpp bring-up seam, not public production readiness.
- The `haxe_ocaml-nd2nh` slice extends that same support to
  `Serializer.USE_ENUM_INDEX`. The Cpp support exposes a target-owned
  `Serializer::USE_ENUM_INDEX` bool, emits upstream-compatible `j` tokens, and
  decodes indexed zero-arg and payload enum values through the generated enum
  metadata registry. README and North Star progress bars stay unchanged for the
  same reason: this is bounded Cpp runtime support, not full Serializer parity.

## Required Follow-Ups

The unchanged escaping counter now passes through the normal C++ target.
Run `haxe test/m14_source_named_function_test.hxml` to check its output and
unchanged typed source. The check also runs native builds with address and
undefined-behavior sanitizers at O0 and O2. It loads the real Array and Sys
dependencies and rejects the old owning function carriers in generated output.
This proves that workload; it does not establish general C++ or Full1 parity.

Unchecked casts retain their destination types through shared typing.
`CppManagedCastPlan` admits a cast only when its exact program occurrence and
substituted storage types agree. Generic abstract unwrapping does not require
an implicit output conversion. Checked casts and conversions that change
storage still require separate runtime plans. Run
`npm run test:m14:cpp-managed-authored-cast` for focused typing, rejection,
and native sanitizer checks.

The managed Array loop and record-read fixtures add bounded evidence under
`haxe_ocaml-9jezt`. A lowered Array value loop retains its selected array and
allocates captured bindings once per iteration. Required anonymous fields use
their structural types; String equality distinguishes null from empty text.
Key/value loops, general iterators, root-statement loops, and optional fields
remain outside that evidence. The full counter adds normal target evidence,
but these other behaviors still need their own contracts and runtime checks.

- Convert unsafe Reflect/Dynamic/default-return scaffolding into explicit
  `unsupported_diagnostic` behavior or oracle-backed support. The current
  inventory lives in
  [`CPP_REFLECT_DYNAMIC_SUPPORT_AUDIT.md`](CPP_REFLECT_DYNAMIC_SUPPORT_AUDIT.md).
- Put Serializer/Unserializer expansion behind
  [`SERIALIZER_UNSERIALIZER_BEHAVIOR_MATRIX.md`](SERIALIZER_UNSERIALIZER_BEHAVIOR_MATRIX.md).
- Keep Cpp enum carrier expansion behind `haxe_ocaml-puquq` and the enum
  carrier behavior matrix above; do not treat tag-only or shell-carrier output
  as enum parity.
- Put Float/NaN/Infinity/Math/JSON/binary serialization and comparison changes
  behind [`FLOAT_NUMERIC_REVIEW_GATE.md`](FLOAT_NUMERIC_REVIEW_GATE.md).
- Freeze compact primitive helpers with black-box oracle edge cases before they
  are treated as parity support. The current inventory and runner plan live in
  [`CPP_COMPACT_PRIMITIVE_ORACLE_FREEZE.md`](CPP_COMPACT_PRIMITIVE_ORACLE_FREEZE.md).
- Keep declaration-only support separate from runtime behavior in code, tests,
  bead notes, and README/North Star status.

Map-comprehension construction has bounded native evidence under `haxe_ocaml-20jan`.
The shared lowerer retains authored loop bindings and creates typed map insertions.
`CppManagedMapStorage` selects integer or string keys from the real Map provider.
`ManagedMap.hpp` owns physical keyed storage and traces its values; it does not select source operations.
Insertion evaluates the map, key, and value in order while retaining all three roots.
The focused capture observer proves duplicate replacement, escaped closures, and complete reclamation for both key representations.
It runs at O0 and O2 with both sanitizers.
Ordinary Map methods, other key kinds, nullable keys, conversions, and ordinary target integration remain required.
The broader map execution fixture remains blocked by managed Int remainder, tracked in `haxe_ocaml-6gjt1`.
Neither the focused pass nor the runtime header establishes general Map parity.

The managed Map consumer under `haxe_ocaml-0i4lh` also admits anonymous keys and
ordinary class keys whose exact program-owned instance layouts are supported.
These use the same traced ObjectMap storage and compare allocation identity.
Map literals, comprehension insertions, reads, and runtime-family tests consume
the same representation choice. Class field contents never select key equality.
The source Map.get fixture checks equal-valued distinct keys, replacement,
missing entries, and non-Map instance controls against upstream Haxe.
The native object-map observer checks class-key retention and unreachable cycles.
This remains `bounded_bringup_support`: enum keys, erased Map identity, unsupported
class layouts, other Map methods, and the complete original Map acceptance remain open.

## Closure Rule

This policy is sufficient to resume bounded non-semantic Cpp work and small
classified helper work. It is not sufficient to resume broad runtime semantics
for Reflect/Dynamic, Serializer/Unserializer, Float/Math/JSON/binary encoding,
or comparison. Those need their owning P1 beads and second-pass review before
implementation.
