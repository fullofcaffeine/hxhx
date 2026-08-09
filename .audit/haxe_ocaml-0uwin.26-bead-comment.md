## Design checkpoint complete

The current module-name check is proven insufficient. The expected-red model
plans two distinct uses, `U1` and `U2`, of the same `HxArray.set` symbol. The
valid `U1/U2` output and corrupted `U2/U2` output collapse to the same current
report, so one valid module-level reason can hide a missing and duplicated use.

The accepted design keeps semantic meaning in sealed Haxe-authored lowering
plans and adds one distinct immutable use occurrence per concrete target
reference. A restricted expression/type/pattern identifier carries only use
provenance into completed OCaml syntax. A checked constructor and final
structural reconciler reject missing, duplicate, stale, wrong-symbol,
wrong-domain, wrong-profile, post-seal, unbound, and owner-local order errors.
The printer remains mechanical.

Oracle request `orq_20260809T121711Z_41cda046` was reconciled and archived. Its
global-order suggestion was narrowed to owner-local lowered schedules so
incidental whole-AST traversal order does not become a new semantic contract.
Module overlap, symbol counting, object identity, receipt-only linkage,
rendered-text authority, general expression annotations, and a universal IR
were rejected.

Implementation is split into:

- `haxe_ocaml-0uwin.27`: freeze the legacy inventory and prevent growth;
- `haxe_ocaml-0uwin.28`: prove one occurrence-authorized Array assignment;
- `haxe_ocaml-0uwin.29`: check generated-text placeholders;
- `haxe_ocaml-0uwin.30`: reserve private runtime names at the raw boundary; and
- `haxe_ocaml-0uwin.31`: shadow, then hard-cut, requirements-only source selection.

The frozen inventory will create additional small semantic-family migration
children. Complete authority remains blocked until that inventory is zero and
the full same-candidate tamper and product matrix passes. README goals and
percentages remain unchanged.

Evidence:

- `.audit/haxe_ocaml-0uwin.26-oracle-disposition.md`
- `.audit/haxe_ocaml-0uwin.26-same-symbol-model.js`
- `.audit/haxe_ocaml-0uwin.26-red-evidence.md`
- `.audit/haxe_ocaml-0uwin.26.tsv`
