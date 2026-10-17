# JavaScript syntax calls

Run `haxe test/m14_js_syntax_typeof_test.hxml` from the repository root.
The test compiles this authored fixture with upstream Haxe 4.3.7 and runs it
with Node. It then loads the real `js.Syntax` declarations, compiles the same
fixture with the shared hxhx typer and JavaScript backend, and runs that output.
Both executions must finish without output or an exception.

The assertions cover the JavaScript `typeof` operator for null, numbers,
Booleans, strings, objects, functions, undefined values, and an undeclared
JavaScript identifier. They also check one operand evaluation, expression
grouping, imported aliases, and ordinary user methods with matching names.
The `js.Syntax.code` calls are the explicit boundary for JavaScript values
that Haxe has no literal for.

Statement-valued arguments also cover code interpolation, `typeof`, deletion,
and constructors selected by a literal name or runtime value. These checks
preserve argument order and effects when an argument needs several statements.
The template and literal constructor name must remain native syntax. An
ordinary user method with the same name must remain an ordinary call.

This fixture checks the syntax APIs. Bare `trace` binding and the broader
logging contract remain tracked separately under `haxe_ocaml-hgtz2`.
