# Typed function-value call oracle

This fixture answers one practical question before reflaxe.ocaml generates
target code: when Haxe calls a computed function value, which work happens
first?

The observable contract is:

1. evaluate the expression that produces the function;
2. evaluate the argument;
3. invoke the selected function; and
4. skip the argument and invocation if producing the function throws.

The fixture runs unchanged through upstream Haxe 4.3.7's interpreter,
JavaScript, and Neko routes. The checked output is behavior evidence only; the
project does not copy or translate upstream compiler implementation.

Run it with:

```bash
bash scripts/reflaxe-ocaml/run-function-value-call-oracle.sh
```
