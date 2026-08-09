1. One current generated module uses checked literal and runtime-reference chunks without changing its output bytes.
2. Missing, duplicate, reordered, stale, wrong-symbol, and changed-hash placeholders fail closed.
3. A private `Hx...` name in an unchecked literal fails the negative guard.
4. The checked record reports owner, plan revision, ordered use IDs, and deterministic content hash without machine-local paths.
5. Remaining generated-text inventory entries are split into bounded follow-up children; this task does not claim complete migration.
6. Focused generated-module tests and the owning vertical compile/build/run fixture pass.
