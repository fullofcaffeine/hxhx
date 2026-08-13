# Second-pass review: repeated private-runtime outputs

The change remains limited to one known compiler behavior: Haxe can place one
typed early-return occurrence more than once in a completed function tree.

- The new pass matches the exact `raise-function-return-signal` role. It does
  not authorize Array, throw, loop, type, or other private runtime references.
- It runs after argument defaults and unused-parameter handling, when the final
  function body exists. It does not guess during individual expression builds.
- The first reference keeps the planned identity. Each later reference receives
  a deterministic output-copy identity tied to the owning function.
- A focused negative test confirms that an unselected duplicated helper still
  fails the final-output check.
- The parser-shaped early-return fixture and the separate wildcard-switch Array
  fixture both compile generated OCaml and execute the result.

No readiness or README Goal changed. The next proof is the full macro-host
regeneration that originally exposed the repeated helper.
