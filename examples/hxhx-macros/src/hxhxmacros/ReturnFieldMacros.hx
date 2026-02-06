package hxhxmacros;

import haxe.macro.Context;
import haxe.macro.Expr;

/**
	Stage4 bring-up macro module: return `Array<Field>` from `@:build(...)`.

	Why
	- Upstream build macros return `Array<haxe.macro.Expr.Field>`.
	- Our earlier Stage4 rung required macros to explicitly call `Compiler.emitBuildFields(...)`, which
	  is smaller but not compatible with many existing macro libraries.

	What
	- `addGeneratedFieldReturn()`:
	  - calls `Context.getBuildFields()` (reverse RPC, bring-up payload)
	  - appends a new static function field (`generated_return()`)
	  - returns the full field array

	How
	- The macro host detects `Array<Field>` return values from allowlisted entrypoints and converts
	  *new* fields (by name delta vs the `getBuildFields()` snapshot) into raw Haxe member snippets via
	  `haxe.macro.Printer`, then sends them back to the compiler using `Compiler.emitBuildFields(...)`.

	Gotchas
	- Current bring-up semantics emit only **new** fields (delta by name). Modifications to existing fields
	  are intentionally ignored at this rung.
**/
class ReturnFieldMacros {
	public static function addGeneratedFieldReturn():Array<Field> {
		final fields = Context.getBuildFields();

		final traceCall:Expr = {
			expr: ECall(
				{ expr: EConst(CIdent("trace")), pos: null },
				[{ expr: EConst(CString("from_hxhx_build_macro_return", DoubleQuotes)), pos: null }]
			),
			pos: null
		};
		final body:Expr = { expr: EBlock([traceCall]), pos: null };

		fields.push({
			name: "generated_return",
			access: [APublic, AStatic],
			kind: FFun({ args: [], expr: body }),
			pos: null
		});

		return fields;
	}
}

