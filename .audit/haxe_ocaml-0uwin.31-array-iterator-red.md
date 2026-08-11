# Expected red: checked private-runtime type references

Command:

```text
haxe \
  -cp packages/reflaxe.ocaml/src \
  -cp test/reflaxe_ocaml_runtime_use_authority/src \
  -D reflaxe_runtime \
  --macro 'nullSafety("reflaxe.ocaml")' \
  --run RuntimeUseAuthorityFixture
```

The command used Haxe 4.3.7 and failed before implementation. The relevant
errors say that `OcamlRuntimeUseAuthority.typeIdentifier`,
`OcamlRuntimeUseAuthority.reconcileType`, and `OcamlTypeExpr.TRuntimeIdent` do
not exist.

This is the intended failure. The current target can authorize expression,
pattern, and generated-text runtime names, but it cannot preserve proof on a
private runtime name used as an OCaml type.
