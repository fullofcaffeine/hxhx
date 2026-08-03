# Exact-value early-return behavior oracle

This fixture records what an ordinary Haxe program must do when an exact
`Int`, `Bool`, or represented `String` function returns from inside a branch,
loop, nested block, `try`, or a nested function. The String cases include the
existing runtime null sentinel; they do not imply support for the separate
`Null<Int>` or `Null<Bool>` carriers.

The practical rule is that `return` exits the function that owns it. A source
`catch` must not intercept the compiler's private return mechanism, and a
return inside a function literal must target that function literal rather than
its enclosing method.

The represented-array cases also make construction observable. Their element
helpers record left-to-right evaluation, and the catch mutates the received
array through one alias. Matching output therefore proves behavior and object
identity; it does not treat generated OCaml text as the expected result.

The URL-decoder cases are the independent public-behavior oracle for the
standard-library `_hexValue` helper. They cover numeric, upper-case, lower-case,
and invalid hexadecimal input through `StringTools.urlDecode`, while a counter
proves that each source argument is evaluated once. `_hexValue` itself remains
private, so the fixture deliberately observes its public caller instead of
copying the helper's algorithm into the test.

Haxe 4.3.7 does not define one cross-target result for the invalid `%G0` input:
the interpreter returns `G0`, JavaScript throws, and Neko returns an empty
string. The oracle therefore compares the valid cases and all other behavior
across all three routes, then checks each route's invalid-input result
separately. The OCaml target preserves the invalid escape as `%G0`; that is an
explicit target-library contract, not a false claim that every Haxe target
agrees on malformed URLs.

Run the upstream Haxe 4.3.7 oracle with:

```bash
npm run test:reflaxe-ocaml:early-return-oracle
```

The script compares interpreter, JavaScript, and Neko output with
`expected.stdout`. The portable `reflaxe.ocaml` fixture compiles this same
source and additionally checks that admitted exact-value returns consume the
sealed typed control plan instead of the legacy result-repair path.
