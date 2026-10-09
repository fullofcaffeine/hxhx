# A loop passed to a real expression macro

The compiler must give `SyntaxArguments.inspect` the written loop before it
checks runtime values. The macro checks the condition, brace body, loop kind,
and source span. It replaces the call with `"syntax-ok"`.

The loop refers to undefined names on purpose. The macro inspects those names
as syntax; they must not reach ordinary name resolution or runtime execution.
This fixture uses a real `macro function` returning `haxe.macro.Expr`.

From the repository root, run the upstream Haxe 4.3.7 behavior check:

```sh
haxe test/fixtures/expression_macro_while/oracle.hxml
```

The output must match `expected.stdout`. The ordinary-call control must fail
with `Void should be Dynamic`:

```sh
haxe -cp test/fixtures/expression_macro_while/ordinary --run Main
```

These commands establish the required behavior. Native `hxhx` support remains
unfinished under `haxe_ocaml-9sj5p` and `haxe_ocaml-geafz`. Upstream success
does not prove native macro support. Both native macro modes must eventually
compile this unchanged fixture and match its output.

Keep the full typed-body integration test as a separate closure requirement.
Do not replace its loop assertions with this upstream-only result.
