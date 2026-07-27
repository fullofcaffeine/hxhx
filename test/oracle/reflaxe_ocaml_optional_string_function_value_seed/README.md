# Optional String function-value oracle

This fixture records what Haxe does when a local function value has one trailing
optional `String` parameter. A missing optional value performs no source
evaluation; a supplied value or explicit null is evaluated in its source
position before the callback runs.

The same source runs through upstream Haxe 4.3.7's interpreter, JavaScript, and
Neko routes. The checked output is behavior evidence only; no upstream compiler
implementation is copied or translated.

Run it with:

```bash
bash scripts/reflaxe-ocaml/run-optional-string-function-value-oracle.sh
```
