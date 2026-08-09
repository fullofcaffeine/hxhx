Use Haxe source structure, not generated OCaml text, as the positive inventory
source. A narrow lexical/AST-aware guard may identify direct constructors and
known string-output boundaries, but it is migration evidence rather than
semantic authority.

The inventory format must be deterministic, reviewable, and grouped into small
semantic migration families. It must not encourage adding a new helper to the
large `OcamlBuilder`; new ownership should move toward focused modules.
