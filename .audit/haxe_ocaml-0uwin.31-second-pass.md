# Written xhigh second pass: requirements-only runtime-selection shadow

## Outcome

Accept the observation-only slice after one implementation correction. The new
report compares today's runtime packaging with a selection derived only from
sealed semantic requirements, but it does not choose or copy runtime files.
`RuntimeCopier` still publishes the same authoritative `selectedEntries`.

Do not close `haxe_ocaml-0uwin.31` and do not change README readiness. The hard
cut remains blocked by the 428-entry private-runtime legacy inventory, complete
occurrence reconciliation, and the same-candidate full matrix named by the
Bead.

## Review questions and dispositions

### Can the shadow accidentally change generated program behavior?

No selected module or copied source comes from the shadow result. The existing
runtime-mode switch still computes the current roots and resolves the current
entries through `RuntimeSourceManifest`. The only refactor exposes those roots
beside the already selected entries. The shadow verifies that resolving those
roots reproduces the authoritative entries, writes a compiler report excluded
from source-bundle authority, and returns no value used by packaging.

The M6 matrix proves that its runtime-plan selected modules equal the shadow's
current closure in full portable and selective metal modes. Portable and metal
native tracers preserve their existing compile/build/run behavior.

### Can a matching report hide a different source file or hash?

No. Both sides resolve dependencies through the same manifest-checked catalog.
Each snapshot records module, path, byte count, and SHA-256 identity. Source
selection matches only when module closure and all source identities match.
Unknown or profile-illegal roots fail through the manifest resolver, and the
current roots must reproduce the exact authoritative entries. Missing,
modified, unlisted, or stale runtime files continue to fail when the manifest
is loaded, before this comparison runs.

### Does a redundant observation look like missing runtime support?

No. The report keeps two statuses:

- `sourceSelectionStatus` compares dependency closure and exact checked source
  bytes; and
- `exactComparisonStatus` additionally compares direct roots and reasons.

This distinction matters when a compiler observation repeats a module already
selected by a requirement. The representative selective metal request has a
source match but an exact reason mismatch, so the observation remains visible
without being misreported as a different copied program.

### Is the report identity complete enough for evidence?

The first implementation omitted the sealed requirement revision and active
runtime/selection modes. That could have assigned the same report revision to
different requirement facts when their module roots happened to match. The
second pass added `requirementRevision`, `runtimeMode`, and `selectionMode` to
the report payload and revision. Focused tests now prove input-order stability,
revision sensitivity, and rejection of an invalid requirement revision.

### Can the report overstate authority or readiness?

No. Its authority is the literal `observation-only`; its messages say the
current compiler remains authoritative. A mismatch explicitly blocks a hard
cut. A match also says the occurrence and zero-inventory gates remain. The
existing requirement report remains `partial`, the artifact/source-bundle
authority is unchanged, and README goals are unchanged.

### Does this add another dependency algorithm or compiler-language owner?

No. Haxe-authored requirements supply roots, and the existing checked runtime
manifest supplies dependencies, profiles, source identities, and hashes. The
new Haxe module only normalizes and compares those results. It adds no source
scan, output patch, handwritten OCaml, target lowering, runtime implementation,
or fallback.

## Representative evidence

- Focused expected-red: the ledger fixture passed while the new fixture failed
  because `RuntimeSelectionShadowReportWriter` did not exist.
- Focused green: `npm run test:reflaxe-ocaml:runtime-requirements`.
- Full/selective/manual/debug comparison matrix: `npm run test:m6:runtime`.
- Portable native tracer: `place_array_simple_assign` compiled, built, and ran
  with the existing result/evaluation-order output.
- Metal native tracer: the existing metal-positive `test/Main.hx` compiled,
  built, and ran; its shadow source selection matched.
- The attempted portable-fixture-as-metal run was rejected by the existing
  explicit-`Dynamic` rule. The proof used a legitimate metal fixture instead
  of weakening that contract.
- Runtime manifest, artifact manifest, runtime-use authority, generated-text,
  private-reference inventory, and inspection tests passed.

## Remaining work

- Migrate the 428 legacy private-runtime references to occurrence authority.
- Run the complete supported portable, metal, raw, generated-text,
  package/example, tamper, and clean-repeat matrix on one candidate when the
  zero-inventory hard-cut precondition becomes reachable.
- Remove compiler-observed roots from correctness only after that evidence.
- Only then may the requirement report's authority or README readiness change.

Oracle was deliberately skipped for this slice. The accepted occurrence review
already specified the shadow seam, and this implementation is a bounded,
observation-only realization with a pure comparison owner and executable
evidence. A new Oracle review would be appropriate if the later hard cut finds
non-converging closure differences or requires a new selection authority.
