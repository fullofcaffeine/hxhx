# Optional String function-value oracle

This fixture records what Haxe does when a local or call-produced function value
has one trailing optional `String` parameter. For example,
`makeGreeter()(required())` calls `makeGreeter()` first, evaluates `required()`
only after the factory returns, materializes the omitted trailing value without
another source expression, and then invokes the returned callback. The failure
case proves that an argument does not run when the factory throws.

The same source runs through upstream Haxe 4.3.7's interpreter, JavaScript, and
Neko routes. The checked output is behavior evidence only; no upstream compiler
implementation is copied or translated.

Run it with:

```bash
bash scripts/reflaxe-ocaml/run-optional-string-function-value-oracle.sh
```
