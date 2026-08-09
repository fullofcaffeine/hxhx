Unchanged Haxe input now produces stable IMap conversion evidence across clean
compiler processes and harmless compiler-local allocation changes.

The old report published temporary Haxe variable numbers for local
initializers. The target now publishes the existing source-structured lexical
identity instead. Call, return, and assignment roles use explicit stable names.
The report model, schema, and root/nested plan revisions were advanced so stale
evidence fails closed.

The recorded red reproduction changed only an unrelated printer local and
showed conversion, runtime-requirement, aggregate, and full-report identity
drift. Repeating the same perturbation after the fix produced byte-identical
reports. The inspector rejects a recomputed report containing the old numeric
identity.

Verification passed for the standalone ledger, public inspector, four focused
IMap surfaces, deterministic two-run goldens, source/provenance guards, and all
107 portable fixtures. The second-pass review found no request-local identity
leak and no duplicate semantic path. Oracle was not needed because the existing
generic lexical identity seam was exact and already accepted.

README goals and readiness percentages are unchanged; this closes a
determinism defect rather than a product milestone.
