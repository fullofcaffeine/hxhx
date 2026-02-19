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
	  supported fields into raw Haxe member snippets, then sends them back to the compiler using
	  `Compiler.emitBuildFields(...)`.

	Gotchas
	- Current bring-up semantics:
	  - support **add** (new field names), and
	  - support **replace** by name (emitted member replaces an existing member with the same name).
	- Deletion by omission is not supported yet.
**/
class ReturnFieldMacros {
	public static function addGeneratedFieldReturn():Array<Field> {
		final fields = Context.getBuildFields();

		final traceCall:Expr = {
			expr: ECall({expr: EConst(CIdent("trace")), pos: null}, [{expr: EConst(CString("from_hxhx_build_macro_return", DoubleQuotes)), pos: null}]),
			pos: null
		};
		final body:Expr = {expr: EBlock([traceCall]), pos: null};

		fields.push({
			name: "generated_return",
			access: [APublic, AStatic],
			kind: FFun({args: [], expr: body}),
			pos: null
		});

		return fields;
	}

	/**
		Stage4 bring-up: replace an existing field by returning a modified `Field`.

		Why
		- Many upstream build macros call `Context.getBuildFields()`, mutate one of the returned
		  `Field` values, and return the full array.
		- Even without full typed AST transport, we can support a conservative replacement model by:
		  1) printing a supported `Field` back to a raw member snippet, and
		  2) replacing the old member compiler-side by name.

		What
		- Looks for a member named `generated_replace`.
		- If it is an `FFun`, overwrite its body with `trace("from_hxhx_build_macro_replaced")`.
		- Returns the full (possibly modified) field array.
	**/
	public static function replaceGeneratedFieldReturn():Array<Field> {
		final fields = Context.getBuildFields();

		final traceCall:Expr = {
			expr: ECall({expr: EConst(CIdent("trace")), pos: null}, [
				{expr: EConst(CString("from_hxhx_build_macro_replaced", DoubleQuotes)), pos: null}
			]),
			pos: null
		};
		final body:Expr = {expr: EBlock([traceCall]), pos: null};

		for (f in fields) {
			if (f == null || f.name != "generated_replace")
				continue;
			switch (f.kind) {
				case FFun(fn):
					if (fn != null)
						fn.expr = body;
				case _:
			}
		}

		return fields;
	}
}
