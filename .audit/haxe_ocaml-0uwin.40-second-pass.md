# IMap runtime-use authority — xhigh second pass

## Outcome

The change is bounded and fail-closed. A generated `IMap` adapter can still
produce the same OCaml and runtime behavior, but it can no longer introduce a
private project runtime name merely because syntax knows that name. Each such
name must first appear in the saved conversion decision with its exact owner,
symbol, requirement, source location, profile, order, and one-use limit.

No Oracle escalation was needed. The behavior is fixed by the existing Haxe
4.3.7 `IMap` contract, the implementation boundary is one already-sealed
conversion, and the focused failures identify a local correction rather than a
competing compiler architecture.

## Challenges and dispositions

### Can one saved permission authorize several generated calls accidentally?

No. Each retained method contributes a distinct role such as
`standard-map:get` or `wrap-iterator:keys`. Syntax resolves that role through
the request-local authority and returns every identifier it inserted. Final
reconciliation checks the complete list and enforces cardinality one. The
corruption suite rejects both a duplicated occurrence and a repeated order.

### Does planned order match the syntax owner rather than report sorting?

Yes. Planning walks the retained method surface in its validated declaration
order. For each method it records Boolean argument conversion first, then the
Map operation, then any iterator or formatting helpers. Syntax constructs and
records those identifiers in the same order. Saved-report inspection rebuilds
the expected list and compares every index. The real standard fixture produced
five adapters with 21 contiguous, uniquely named occurrences each.

### Can dead-code elimination change the method surface safely?

Yes. Both occurrence derivation and syntax consume the same retained `methods`
list. A missing, reordered, or type-conflicting method fails the existing pure
conversion contract. Removing a method from a saved report without updating
its runtime occurrences is rejected as an incomplete inventory.

### Are user-written `IMap` implementations over-authorized as standard maps?

No. User adapters never receive `HxMap`, iterator, array, or text-helper
capabilities. The three real String/Int user adapters each own only
`HxType.class_`, which supplies the generated interface record's runtime type
marker. A separate framework-free Bool-key case proves that a retained Boolean
argument adds exactly `HxRuntime.unbox_bool_or_obj` after the type marker.

### Are ordinary OCaml operations being mislabeled as project runtime modules?

No. `Obj.repr`, `Obj.obj`, tuple access, primitive string conversion, and local
function calls remain ordinary OCaml operations. The authority list covers only
the private `Hx*` names inserted by this adapter syntax owner.

### Does saved evidence fail closed when edited?

Yes. Focused inspection rejects an unknown source kind and missing, duplicate,
reordered, stale, wrong-owner, wrong-symbol, and wrong-profile runtime-use
records. The generic authority fixture rejects a plain private identifier that
bypasses `ERuntimeIdent`. The static boundary guard also detects reintroduced
direct `HxMap`, `HxIterator`, `HxArray`, `HxString`, `HxDynamic`, `HxType`, or
`HxRuntime` construction in the focused syntax module.

### Did the authority work change Haxe behavior?

No observed behavior changed. The standard fixture compiled through
`reflaxe.ocaml`, built with Dune, and ran StringMap, IntMap, ObjectMap, nullable,
copy, iteration, formatting, and nested-interface cases successfully. The same
source compiled with the installed upstream Haxe 4.3.7 JavaScript target and
matched the manually retained expected output exactly. User implementations
also compiled, built, ran, and continued to call their real methods.

### Is the inventory reduction exact and honestly scoped?

Yes. The generated migration inventory fell from 402 to 390 entries and the
12-entry `imap-interface-syntax` family disappeared. The three
`standard-map-carrier-model` references remain. One shared carrier helper can
serve many declarations, so claiming those references through this
per-conversion task would be unsound.

## Verification

Passed in the current worktree:

- upstream Haxe 4.3.7 JavaScript compilation and runtime output comparison for
  `imap_runtime_boundary`;
- real Haxe-to-OCaml compile, Dune build, runtime, report inspection, and
  corruption tests for `imap_runtime_boundary` and
  `imap_user_implementation_boundary`;
- real compile/build/runtime checks for `imap_nullable_standard_boundary` and
  `imap_storage_alias_negative`;
- deterministic double-build golden checks for every report changed by the v5
  model, including the focused call and simple-array fixtures;
- `npm run test:reflaxe-ocaml:runtime-requirements`;
- direct `RuntimeUseAuthorityFixture`, `CheckedGeneratedTextFixture`, and
  `TypeRegistryGeneratedTextFixture` runs;
- `npm run guard:reflaxe-ocaml-imap-boundary`;
- `npm run guard:reflaxe-ocaml-runtime-reference-inventory`;
- `npm run guard:hx-format:changed`;
- `npm run guard:mega-file-gravity-watch`;
- `npm run guard:local-paths`; and
- `git diff --check`.

## Verification limitation

The package-wide `npm run test:reflaxe-ocaml:runtime-use-authority` wrapper was
stopped after its Haxe 4.3.7 null-safety traversal remained CPU-active for 19
minutes without reaching fixture output. This is the already recorded tooling
defect `haxe_ocaml-850ii.23`; the same path was previously stack-confirmed in
`camlNullSafety` after more than 34 minutes. The direct authority,
checked-generated-text, and type-registry fixtures all passed in the current
worktree. This limitation is recorded rather than presented as broad wrapper
closure.

## Readiness decision

README Goals remain unchanged. This closes one private-runtime syntax family,
not complete runtime authority, standalone target 1.0, Full1, or the authentic
shared-target route.
