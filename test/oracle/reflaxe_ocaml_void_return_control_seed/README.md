# Payloadless `Void` early-return behavior oracle

This fixture records what an ordinary Haxe program must do when `return;`
appears below a branch, loop, `try`/`catch`, catch body, or nested anonymous
function in a `Void` function.

The practical rule is that `return;` exits only the function that owns it. It
does not carry a Haxe value, a source `catch` cannot intercept it, and a return
inside a function literal cannot exit its enclosing method.

Run the upstream Haxe 4.3.7 oracle with:

```bash
npm run test:reflaxe-ocaml:void-return-oracle
```

The script compares interpreter, JavaScript, and Neko output with
`expected.stdout`. The portable `reflaxe.ocaml` fixture uses the same source
and additionally proves that target syntax consumes a sealed effect-only
control record.
