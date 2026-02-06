package hxhxmacros;

import haxe.macro.Context;
import haxe.macro.Expr;

/**
	Stage4 bring-up macro module: exercise the `Array<Field>` → snippet printer subset.

	Why
	- `hxhx` currently transports build-macro results as *raw member snippets* that are re-parsed
	  by the Stage3 bootstrap parser.
	- The macro host therefore needs a small, deterministic "Field → member snippet" printer.
	- This module acts as a regression fixture so we can expand the supported subset safely.

	What
	- `addArgFunctionAndVar()`:
	  - calls `Context.getBuildFields()` (required for this bring-up rung)
	  - appends:
	    - `generated_with_args(a, b)` which traces a string literal
	    - `generated_var:Dynamic`
	  - returns the full field array

	How
	- The macro host prints these fields into Haxe class members and forwards them via
	  `compiler.emitBuildFields`, and the compiler merges them into the typed program.
**/
class FieldPrinterMacros {
	public static function addArgFunctionAndVar():Array<Field> {
		final fields = Context.getBuildFields();

		final traceCall:Expr = {
			expr: ECall(
				{ expr: EConst(CIdent("trace")), pos: null },
				[{ expr: EConst(CString("from_hxhx_field_printer", DoubleQuotes)), pos: null }]
			),
			pos: null
		};
		final body:Expr = { expr: EBlock([traceCall]), pos: null };

		fields.push({
			name: "generated_with_args",
			access: [APublic, AStatic],
			kind: FFun({
				args: [
					{ name: "a", type: null, opt: false, value: null },
					{ name: "b", type: null, opt: false, value: null },
				],
				expr: body
			}),
			pos: null
		});

		fields.push({
			name: "generated_var",
			access: [APublic, AStatic],
			kind: FVar(null, { expr: EConst(CInt("123")), pos: null }),
			pos: null
		});

		return fields;
	}
}
