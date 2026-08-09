1. The current failure is reproduced with a fixture or model test where one
   explained runtime-module use could hide a second unexplained use of the
   same module.
2. The review defines the exact authoritative record for expression, type,
   pattern, generated-text, and raw-boundary runtime uses.
3. The review explains how final syntax is checked without making syntax or
   rendered text the source of semantic truth.
4. Stable identity, request lifetime, duplication, omission, reordering,
   corruption, and deterministic-report behavior are specified.
5. The design preserves one Haxe-authored semantic target core, keeps
   `OcamlExpr` and its printer semantic-free, and adds no universal IR or new
   mega-file.
6. A staged implementation sequence names bounded children, deletion gates,
   focused red/green tests, full portable evidence, and the exact condition
   that may change `authorityStatus` from `partial`.
7. The Oracle reply is reconciled against current source and recorded as
   retained, rejected, deferred, or requiring an owner decision.
8. README Goals remain unchanged because this Bead chooses a design rather
   than completing the runtime-authority product gate.
