# Second-pass review: base `HxTypeRegistry` generated text

## Outcome

No closure blocker remains for the base metadata slice. The generated OCaml
bytes are unchanged, but the Haxe source now records why each private runtime
identifier may appear before it publishes `HxTypeRegistry.ml`.

This does **not** complete generated-text runtime authority. Reflection
constructor adapters still account for 12 legacy inventory rows, and Dynamic
stringifier registration accounts for one. Those rows remain explicit and
block the later requirements-only completeness claim.

## Boundary review

- Base `HxType` calls are planned from immutable copies of class, enum, layout,
  field, inheritance, and tag inputs. Each use has a stable owner-local ID, the
  exact type-registry requirement, one permitted profile set, and one output
  position.
- `HxType.EnumBlock` and `HxType.EnumImmediate` are checked separately from the
  layout registration call. The complete-file scan discovered that the prior
  inventory had missed these indirectly assembled names.
- Deferred constructor and stringifier calls use temporary legacy placeholders.
  Their IDs are reported separately and never appear in `orderedUseIds`, which
  is the list of uses that have real semantic authority.
- Program modules can legitimately start with `Hx`. They use a third category
  that is neither checked nor legacy runtime authority. Each identifier must be
  whitelisted by stable role and exact value from the current registry inputs,
  consumed once, and placed in an OCaml identifier position. This prevents the
  `HxProgramOwned` false positive without creating a general runtime escape.
- The complete rendered file is still scanned. A private name in ordinary text,
  a placeholder hidden in a string/comment, a forged marker, a missing or
  reordered checked occurrence, an unplanned program identifier, or a changed
  content hash fails before publication.

## Evidence reviewed

- Focused red then green: `npm run test:reflaxe-ocaml:type-registry-generated-text`.
- Generic authority and corruption portfolio:
  `npm run test:reflaxe-ocaml:runtime-use-authority`.
- Inventory scanner and independent fixture:
  `npm run guard:reflaxe-ocaml-runtime-reference-inventory`.
- Exact base reflection output: the before/after `HxTypeRegistry.ml` SHA-256 is
  `e2a31a5d4719004d7c219ac21245332624c1a6af973b5f998c7bd5cc0944be75`.
- Enum compile/build/run and deterministic regeneration:
  `PORTABLE_FIXTURE_ALLOWLIST=enum_reflection_layout PORTABLE_JOBS=1 bash scripts/test-portable.sh`.
- Broad runtime matrix: `npm run test:m6:runtime`; it first exposed the
  `HxProgramOwned` false positive, then passed after the scoped identifier fix.
- Final targeted compiles rechecked `m6_runtime_program_module` and
  `m6_runtime_type_registry` after whitelist hardening.
- The first `npm run ci:guards` attempt passed its semantic server matrix but
  exceeded the final-ten RSS plateau allowance by 5.4 MiB. An immediate
  isolated rerun of the exact server gate passed all cases and ended 3.7 MiB
  below its request-20 RSS sample, so this review found no reproducible retained
  state introduced by the slice. Both results remain in the decision log.

## Oracle disposition

No additional Oracle review was requested. The accepted parent design already
required a fail-closed complete-file boundary, and each issue found here had a
bounded local owner plus executable evidence. The written second pass was the
appropriate independent review for this `thinking:xhigh` child.

## Deferred work

- `haxe_ocaml-0uwin.29.2`: replace all constructor-family legacy tokens with
  checked occurrences and exact `HxType`, `HxArray`, `HxRuntime`, and `HxString`
  requirements.
- `haxe_ocaml-0uwin.29.3`: check Dynamic stringifier registration, then delete
  the temporary type-registry legacy-token API once no legacy row remains.
- README goals and readiness stay unchanged because runtime-use authority is
  still partial.
