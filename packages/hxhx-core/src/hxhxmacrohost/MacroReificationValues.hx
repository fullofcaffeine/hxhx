package hxhxmacrohost;

import haxe.macro.Expr;

/**
	Run-time support for the `$v{}` value splice of lowered macro quotations.

	Why
	- `macro $v{names}` with `names:Array<String>` must become an `EArrayDecl` whose elements are
	  the constants of each item. The lowering (`MacroReificationLowering`) is an expression
	  rewrite, and the Stage3 native emitter does not yet accept a loop, a closure, or a block
	  value as the argument of an enum constructor, so the loop lives here as ordinary Haxe. One
	  function per element type keeps every signature concrete: Stage3 has no native generic
	  methods either.
	- Upstream Haxe lowers `$v{}` to `haxe.macro.Context.makeExpr`, which exists only in the macro
	  context. This module is on the classpath of every project-macro plugin build
	  (`packages/hxhx-core/src` is the plugin's support classpath), which is where `$v{}` runs.

	What
	- The `nullable*` functions read a `Null<T>` payload once and return `CIdent("null")` or the
	  scalar constant, as `makeExpr` does at macro run time. The array functions return the
	  `EArrayDecl` of one constant per element. Every node is at `pos`. Non-null scalars are
	  lowered inline by `MacroReificationLowering`; nested arrays and other element types are
	  rejected there.
**/
class MacroReificationValues {
	static function arrayOf(items:Array<Expr>, pos:Position):Expr
		return {expr: EArrayDecl(items), pos: pos};

	static function nullConstant(pos:Position):Expr
		return {expr: EConst(CIdent("null")), pos: pos};

	public static function nullableInt(value:Null<Int>, pos:Position):Expr
		return value == null ? nullConstant(pos) : {expr: EConst(CInt(Std.string(value), null)), pos: pos};

	public static function nullableFloat(value:Null<Float>, pos:Position):Expr
		return value == null ? nullConstant(pos) : {expr: EConst(CFloat(Std.string(value), null)), pos: pos};

	public static function nullableBool(value:Null<Bool>, pos:Position):Expr
		return value == null ? nullConstant(pos) : {expr: EConst(CIdent(value ? "true" : "false")), pos: pos};

	public static function nullableString(value:Null<String>, pos:Position):Expr
		return value == null ? nullConstant(pos) : {expr: EConst(CString(value, DoubleQuotes)), pos: pos};

	public static function ints(values:Array<Int>, pos:Position):Expr {
		final items:Array<Expr> = [];
		for (value in values)
			items.push({expr: EConst(CInt(Std.string(value), null)), pos: pos});
		return arrayOf(items, pos);
	}

	public static function floats(values:Array<Float>, pos:Position):Expr {
		final items:Array<Expr> = [];
		for (value in values)
			items.push({expr: EConst(CFloat(Std.string(value), null)), pos: pos});
		return arrayOf(items, pos);
	}

	public static function bools(values:Array<Bool>, pos:Position):Expr {
		final items:Array<Expr> = [];
		for (value in values)
			items.push({expr: EConst(CIdent(value ? "true" : "false")), pos: pos});
		return arrayOf(items, pos);
	}

	public static function strings(values:Array<String>, pos:Position):Expr {
		final items:Array<Expr> = [];
		for (value in values)
			items.push({expr: EConst(CString(value, DoubleQuotes)), pos: pos});
		return arrayOf(items, pos);
	}
}
