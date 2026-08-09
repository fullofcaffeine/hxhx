## Legacy inventory and no-growth gate complete

The repository now has a deterministic source-level migration inventory for
every direct private-runtime construction shape covered by this checkpoint:

- 398 structured expression references;
- 13 structured type references;
- 15 structured pattern references;
- 17 known generated-text references; and
- 2 raw OCaml construction boundaries.

That is 445 entries across 15 Haxe owners and 32 migration families. The large
`OcamlBuilder.hx` owner accounts for 372 entries, so its records are divided by
semantic family and the inventory explicitly prohibits centralizing the
migration there.

The guard is deliberately not runtime correctness authority. It freezes the
legacy Haxe source surface and fails if a direct constructor is added, removed,
or changed without an explicit reviewed regeneration. `--write` requires an
active Bead ID, CI never rewrites the expected file, and failures report the
current owner line and symbol.

Focused evidence:

- `npm run guard:reflaxe-ocaml-runtime-reference-inventory`: pass;
- expected growth/change and clean-repeat fixtures: pass;
- explicit regeneration produced an identical file digest: pass;
- JSON parsing and `git diff --check`: pass;
- local-path privacy guard: pass;
- QA risk-routing and product-surface guards: pass.

No generated OCaml, runtime selection, runtime report authority, or README goal
changed. The next child is `haxe_ocaml-0uwin.28`, which turns one real
`Array<Int>` assignment from an inventoried plain reference into a checked
occurrence-authorized target reference.
