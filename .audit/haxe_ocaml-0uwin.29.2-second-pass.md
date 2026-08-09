# Second-pass review: reflected constructor generated text

## Outcome

No closure blocker remains for the reflected constructor slice. Enum and class
constructor registration still produce the same OCaml source and runtime
behavior, but every private runtime identifier now has a planned identity and
an exact requirement before the file can be published.

This does **not** complete all `HxTypeRegistry.ml` authority. Dynamic
stringifier registration remains one explicit legacy row owned by
`haxe_ocaml-0uwin.29.3`.

## What the boundary now proves

- The compiler first creates an immutable ordered list of constructor runtime
  uses. Each row records a stable constructor/argument role, the exact OCaml
  symbol, and the compiler capability that explains why the generated registry
  needs it.
- `HxType.register_enum_ctor` and `HxType.register_class_ctor` use the existing
  type-registry requirement. `HxArray.t`, `HxArray.length`, and `HxArray.get`
  use the reflected-argument requirement. Boolean conversion and omitted null
  values use their own `HxRuntime` requirements.
- `HxString.hx_null_string` has a separate generated-module requirement. The
  ordinary optional-null requirement names `HxRuntime`, so it cannot honestly
  authorize an `HxString` reference.
- The plan follows identifier order in the final OCaml file. For example, in
  `HxRuntime.unbox_bool_or_obj (HxArray.get args 0)`, the outer unbox use comes
  before the nested array read even though the Haxe builder obtains the array
  placeholder first.
- Actual emission must consume each planned use once with the same symbol and
  in the same order. Missing, duplicate, stale, wrong-symbol, wrong-root, and
  reordered uses fail before publication through the shared generated-text
  authority.
- Program module and constructor identifiers remain on the exact sealed
  program-identifier whitelist. They do not become runtime requirements merely
  because a user-defined OCaml module name starts with `Hx`.

## Design challenge

The planner and emitter both inspect the same final constructor argument types.
That duplication is bounded by fail-closed reconciliation: if planning predicts
too few uses, emission requests an unknown use; if it predicts too many, sealing
reports a missing use; and if it predicts the wrong nesting order or runtime
root, reconciliation fails. There is still one constructor implementation and
one generated output path.

No printer exception, unchecked string allowance, generated-file patch, or
second reflection implementation was added. The Haxe-owned compiler continues
to decide argument conversion and optional-value behavior; the extracted
emitter only validates and materializes the already selected identifiers.

## Evidence reviewed

- Expected red state, then green focused owner:
  `npm run test:reflaxe-ocaml:type-registry-generated-text`.
- Shared missing, duplicate, stale, wrong-symbol, wrong-root, profile, order,
  marker, and changed-hash checks:
  `npm run test:reflaxe-ocaml:runtime-use-authority`.
- Exact compiler-infrastructure requirements:
  `npm run test:reflaxe-ocaml:runtime-requirements`.
- Complete private-reference inventory and independent scanner fixture:
  `npm run guard:reflaxe-ocaml-runtime-reference-inventory`. The inventory fell
  from 441 to 429 rows, removing exactly the 12 constructor-family rows.
- New class/enum constructor tracer:
  `PORTABLE_FIXTURE_ALLOWLIST=type_reflection_constructors PORTABLE_JOBS=1 bash scripts/test-portable.sh`.
  Its `HxTypeRegistry.ml` remained byte-identical at SHA-256
  `9d83cb7474f79e8db02cf7d5b973e09de8fc9945d829d3d369210c09518079bf`.
- Existing enum layout, construction, deterministic regeneration, and tamper
  proof:
  `PORTABLE_FIXTURE_ALLOWLIST=enum_reflection_layout PORTABLE_JOBS=1 bash scripts/test-portable.sh`.
- Existing runtime packaging and reflected Boolean construction:
  `npm run test:m6:runtime`.
- Repository Haxe formatting: `npm run guard:hx-format`.

## Oracle disposition

No additional Oracle review was requested. The accepted parent architecture
already defines the complete-file fail-closed boundary, and the only subtle
issue found here—nested identifier order—had an immediate focused reproducer
and one local invariant. This written second pass is the appropriate review for
the bounded `thinking:xhigh` child.

## Deferred work

- `haxe_ocaml-0uwin.29.3` must migrate Dynamic stringifier registration and
  then delete the legacy runtime-token API.
- `haxe_ocaml-0uwin.31` remains responsible for proving that recorded
  requirements alone select the complete runtime source set.
- README goals and readiness remain unchanged because one generated-text
  legacy row and broader runtime-selection proof still remain.
