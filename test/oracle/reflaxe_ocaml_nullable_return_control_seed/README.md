# Exact nullable-primitive early-return behavior oracle

This fixture records what an ordinary Haxe function must return when an early
`return value;` carries exact `Null<Int>` or `Null<Bool>`.

The practical rule is that the returned carrier preserves all nullable states:
`null` stays distinct from boxed `0` or `false`, and nonzero/`true` values keep
their value. The fixture covers both a concrete final fallback such as
`return 7;` and an already-nullable final fallback such as
`return fallback;`. A return from inside `try` exits the function without
entering a source `catch`.

Run the upstream Haxe 4.3.7 oracle with:

```bash
npm run test:reflaxe-ocaml:nullable-return-oracle
```

The script compares interpreter, JavaScript, and Neko output with
`expected.stdout`. The portable `reflaxe.ocaml` fixture uses the same source
and additionally proves that the target consumes one sealed carrier-preserving
control record rather than boxing an existing `Obj.t` again.
