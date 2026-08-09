## User-visible outcome

User-authored raw OCaml cannot silently impersonate a compiler-owned `Hx...`
runtime helper and thereby bypass runtime requirements.

## Scope

Reserve the compiler-private runtime namespace in portable `__ocaml__` literal
text and preserve metal's existing no-raw rule. Determine from real consumers
whether a checked runtime placeholder is needed; do not add one speculatively.
