# Expected-red evidence

Command:

```text
node .audit/haxe_ocaml-0uwin.26-same-symbol-model.js
```

Result: exit 1, as intended for the design checkpoint.

Both the valid `U1/U2` case and the corrupted `U2/U2` case reduced to the same
current authority result:

```json
{
  "requirementRoots": ["HxArray"],
  "observedModules": ["HxArray"],
  "withoutRequirementRoot": []
}
```

The final `assert.notDeepStrictEqual` failed because module-name authority has
discarded the occurrence identities. This is the precise failure the first
implementation child must turn green with an occurrence-aware reconciler.
