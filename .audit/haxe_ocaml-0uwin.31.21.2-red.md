# Runtime inventory regression: expected red

The portable behavior portfolio passed, but the private-runtime migration guard
rejected three new unchecked target references.

Command:

```text
PATH="$PWD/node_modules/.bin:$PATH" \
npm run guard:reflaxe-ocaml-runtime-reference-inventory
```

Expected failure:

```text
new legacy runtime reference: OcamlBuilder.hx pattern HxRuntime.Hx_continue
new legacy runtime reference: OcamlBuilder.hx pattern HxRuntime.Hx_break
new legacy runtime reference: OcamlBuilder.hx expression HxArray.get
```

The runtime helpers exist, so compile and runtime tests cannot detect this
authority gap. The inventory guard is the lowest faithful red contract: it
proves that source syntax gained private names which no sealed occurrence owns.
