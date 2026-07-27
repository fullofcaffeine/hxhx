# Exact-Int early-return behavior oracle

This fixture records what an ordinary Haxe program must do when an `Int`
function returns from inside a branch, loop, nested block, `try`, or a nested
function.

The practical rule is that `return` exits the function that owns it. A source
`catch` must not intercept the compiler's private return mechanism, and a
return inside a function literal must target that function literal rather than
its enclosing method.

Run the upstream Haxe 4.3.7 oracle with:

```bash
npm run test:reflaxe-ocaml:early-return-oracle
```

The script compares interpreter, JavaScript, and Neko output with
`expected.stdout`. The portable `reflaxe.ocaml` fixture compiles this same
source and additionally checks that admitted exact-`Int` returns consume the
sealed typed control plan instead of the legacy result-repair path.
