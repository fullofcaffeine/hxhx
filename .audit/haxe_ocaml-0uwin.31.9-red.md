# Expected-red evidence: sealed return runtime use

Command:

```text
npm run test:reflaxe-ocaml:return-runtime-use
```

Observed failure before implementation:

```text
test/reflaxe_ocaml_return_runtime_use/src/ReturnRuntimeUseFixture.hx:9: characters 8-56 : Type not found : reflaxe.ocaml.lowered.OcamlReturnRuntimeUseModel
test/reflaxe_ocaml_return_runtime_use/src/ReturnRuntimeUseFixture.hx:56: characters 16-45 : Type not found : OcamlReturnRuntimeUseContract
```

This is the intended failure. The existing control plan decides what an early
return means, but it does not yet provide the narrower occurrence record needed
to authorize the private `HxRuntime` identifier used by that exact return.
