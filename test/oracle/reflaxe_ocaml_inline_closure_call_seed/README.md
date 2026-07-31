# Immediate inline-closure call oracle

This fixture answers one practical question before reflaxe.ocaml generates
target code: when Haxe creates and immediately calls a closure, what runs and in
which order?

For example:

```haxe
final result = (function(value:Int):Int {
	return offset + value;
})(argument());
```

The observable contract is:

1. create the closure and capture `offset`;
2. evaluate `argument()`;
3. invoke the closure exactly once; and
4. preserve whether the call returns a value or only performs an effect.

The fixture runs unchanged through upstream Haxe 4.3.7's interpreter,
JavaScript, and Neko routes. The checked output is behavior evidence only; the
project does not copy or translate upstream compiler implementation.

Run it with:

```bash
bash scripts/reflaxe-ocaml/run-inline-closure-call-oracle.sh
```
