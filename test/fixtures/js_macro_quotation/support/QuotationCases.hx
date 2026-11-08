import haxe.macro.Expr;

/** Observe the original quoted syntax through real public enum constructors and payloads. */
class QuotationCases {
	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function isInt(value:Expr, expected:String):Bool
		return switch value.expr {
			case EConst(CInt(text, _)): text == expected;
			case _: false;
		};

	/** A quotation in a static initializer is lowered like one in a function body. */
	static final initialized = macro 1 + 2;

	public static function run():Void {
		switch initialized.expr {
			case EBinop(OpAdd, left, right):
				require(isInt(left, "1") && isInt(right, "2"), "static initializer operands");
			case _:
				throw "static initializer quotation";
		}
		final string = macro "bar";
		switch string.expr {
			case EConst(CString("bar", _)):
			case _:
				throw "string quotation";
		}
		final field = macro null.foo;
		switch field.expr {
			case EField({expr: EConst(CIdent("null"))}, "foo", _):
			case _:
				throw "field quotation";
		}
		final binary = macro 1
		in 0;
		switch binary.expr {
			case EBinop(OpIn, left, right):
				require(isInt(left, "1") && isInt(right, "0"), "in operands");
			case _:
				throw "in quotation";
		}
		final name = "selected";
		final splice = macro deq(0, $i{name}(0));
		switch splice.expr {
			case ECall({expr: EConst(CIdent("deq"))}, [left, {expr: ECall({expr: EConst(CIdent("selected"))}, [right])}]):
				require(isInt(left, "0") && isInt(right, "0"), "splice arguments");
			case _:
				throw "identifier splice";
		}
		final absent = macro if (1) 2;
		switch absent.expr {
			case EIf(condition, yes, no):
				require(isInt(condition, "1") && isInt(yes, "2") && no == null, "missing else");
			case _:
				throw "if quotation";
		}
		final present = macro if (1) 2 else 3;
		switch present.expr {
			case EIf(condition, yes, no):
				require(isInt(condition, "1") && isInt(yes, "2") && no != null && isInt(no, "3"), "present else");
			case _:
				throw "if else quotation";
		}
		final type = macro :X->Y;
		switch type {
			case TFunction([TPath({name: "X"})], TPath({name: "Y"})):
			case _:
				throw "function type quotation";
		}
		final constructed = TOptional(TNamed("a", macro :Int));
		switch constructed {
			case TOptional(TNamed("a", TPath({name: "Int"}))):
			case _:
				throw "nested enum construction";
		}
		// `$v{}` needs the macro context upstream (`Context.makeExpr`); the native
		// project-macro-reification fixture covers it.
		splices();
		positions();
		forms();
		QuotationShadowCases.run();
	}

	/** Expression, block, array, field, and type-path splices. */
	static function splices():Void {
		final one = macro 1;
		final items = [macro 2, macro 3];
		final field = "size";
		final path:TypePath = {pack: ["p"], name: "T", params: []};
		switch (macro $one + $e{one}).expr {
			case EBinop(OpAdd, left, right):
				require(isInt(left, "1") && isInt(right, "1"), "expression splice operands");
			case _:
				throw "expression splice";
		}
		switch (macro $b{items}).expr {
			case EBlock([a, b]):
				require(isInt(a, "2") && isInt(b, "3"), "block splice entries");
			case _:
				throw "block splice";
		}
		switch (macro f($a{items})).expr {
			case ECall(_, [a, b]):
				require(isInt(a, "2") && isInt(b, "3"), "sole argument splice");
			case _:
				throw "argument splice";
		}
		switch (macro f(0, $a{items})).expr {
			case ECall(_, [zero, {expr: EArrayDecl([a, b])}]):
				require(isInt(zero, "0") && isInt(a, "2") && isInt(b, "3"), "mixed argument splice");
			case _:
				throw "mixed argument splice";
		}
		switch (macro [$a{items}]).expr {
			case EArrayDecl([a, b]):
				require(isInt(a, "2") && isInt(b, "3"), "array literal splice");
			case _:
				throw "array literal splice";
		}
		switch (macro {$a{items};}).expr {
			case EBlock([a, b]):
				require(isInt(a, "2") && isInt(b, "3"), "block entry splice");
			case _:
				throw "block entry splice";
		}
		switch (macro box.$field).expr {
			case EField({expr: EConst(CIdent("box"))}, "size", _):
			case _:
				throw "field splice";
		}
		switch (macro new $path(1)).expr {
			case ENew({pack: ["p"], name: "T"}, [a]):
				require(isInt(a, "1"), "constructor splice argument");
			case _:
				throw "type path splice";
		}
	}

	/** Every node carries a position in this file; `@:pos(p)` replaces the positions it covers. */
	static function positions():Void {
		final quoted = macro 1 + 2;
		final at:{file:String, min:Int, max:Int} = cast quoted.pos;
		require(StringTools.endsWith(at.file, "QuotationCases.hx") && at.min >= 0 && at.max >= at.min, "quote position");
		final elsewhere:Position = cast {file: "elsewhere.hx", min: 5, max: 9};
		final moved = macro @:pos(elsewhere) f(1);
		final movedAt:{file:String, min:Int, max:Int} = cast moved.pos;
		require(movedAt.file == "elsewhere.hx" && movedAt.min == 5 && movedAt.max == 9, "replaced position");
		switch moved.expr {
			case ECall(callee, [argument]):
				final calleeAt:{file:String, min:Int, max:Int} = cast callee.pos;
				final argumentAt:{file:String, min:Int, max:Int} = cast argument.pos;
				require(calleeAt.file == "elsewhere.hx" && argumentAt.file == "elsewhere.hx", "replaced inner positions");
			case _:
				throw "positioned call";
		}
	}

	/** Blocks, declarations, loops, functions, literals, and wrappers keep their public form. */
	static function forms():Void {
		switch (macro {var x = 1; x + 1;}).expr {
			case EBlock([
				{expr: EVars([{name: "x", expr: {expr: EConst(CInt("1", _))}}])},
				{expr: EBinop(OpAdd, _, _)}
			]):
			case _:
				throw "block form";
		}
		switch (macro function(a:Int, ?b:String):Int return a).expr {
			case EFunction(FAnonymous,
				{args: [{name: "a", type: TPath({name: "Int"})}, {name: "b", opt: true}], ret: TPath({name: "Int"}), expr: {expr: EReturn(_)}}):
			case _:
				throw "function form";
		}
		switch (macro while (true)
			step()).expr {
			case EWhile({expr: EConst(CIdent("true"))}, {expr: ECall(_, [])}, true):
			case _:
				throw "while form";
		}
		switch (macro for (i in 0...3) i).expr {
			case EFor({expr: EBinop(OpIn, {expr: EConst(CIdent("i"))}, {expr: EBinop(OpInterval, _, _)})}, {expr: EConst(CIdent("i"))}):
			case _:
				throw "for form";
		}
		switch (macro try risky() catch (e:String) 0).expr {
			case ETry({expr: ECall(_, [])}, [{name: "e", type: TPath({name: "String"})}]):
			case _:
				throw "try form";
		}
		switch (macro throw "x").expr {
			case EThrow({expr: EConst(CString("x", _))}):
			case _:
				throw "throw form";
		}
		switch (macro {a: 1}).expr {
			case EObjectDecl([{field: "a", expr: {expr: EConst(CInt("1", _))}}]):
			case _:
				throw "object form";
		}
		switch (macro c ? 1 : 2).expr {
			case ETernary({expr: EConst(CIdent("c"))}, _, _):
			case _:
				throw "ternary form";
		}
		switch (macro untyped x).expr {
			case EUntyped({expr: EConst(CIdent("x"))}):
			case _:
				throw "untyped form";
		}
		switch (macro(x : Int)).expr {
			case EParenthesis({expr: ECheckType(_, TPath({name: "Int"}))}):
			case _:
				throw "check type form";
		}
		switch (macro a[0]).expr {
			case EArray({expr: EConst(CIdent("a"))}, {expr: EConst(CInt("0", _))}):
			case _:
				throw "array access form";
		}
		switch (macro a += 1).expr {
			case EBinop(OpAssignOp(OpAdd), _, _):
			case _:
				throw "compound assignment form";
		}
		switch (macro - x).expr {
			case EUnop(OpNeg, false, {expr: EConst(CIdent("x"))}):
			case _:
				throw "unary form";
		}
		switch (macro new p.Foo<Int>(1)).expr {
			case ENew({pack: ["p"], name: "Foo", params: [TPType(TPath({name: "Int"}))]}, [_]):
			case _:
				throw "constructor form";
		}
		switch (macro :{a:Int, ?b:String}) {
			case TAnonymous([
				{name: "a", kind: FVar(TPath({name: "Int"}), null)},
				{name: "b", meta: [{name: ":optional"}]}
			]):
			case _:
				throw "anonymous type form";
		}
	}
}

/**
	Quotations whose surrounding scope declares the names `haxe`, `Std`, and `hxhxmacrohost`.

	Upstream builds the quoted tree inside the compiler, so a user local, parameter, or field with
	one of those names never changes what `macro ...` produces. The authored splice payloads still
	read the user's own bindings.
**/
class QuotationShadowCases {
	static var haxe = 7;
	static var Std = 8;
	static var hxhxmacrohost = 9;

	static function check(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function intText(value:Expr):String
		return switch value.expr {
			case EConst(CInt(text, _)): text;
			case _: "";
		};

	public static function run():Void {
		check(intText(fields()) == "1", "field shadow");
		check(intText(local()) == "1", "local haxe shadow");
		check(intText(parameters(1, 2, 3)) == "2", "parameter shadow");
		switch rootLocals().expr {
			case ECall({expr: EConst(CIdent("f"))}, [{expr: EConst(CIdent("haxe"))}, value, {pos: at}]):
				final facts:{file:String, min:Int, max:Int} = cast at;
				check(intText(value) == "3" && facts.file.length > 0, "shadowed root splice");
			case _:
				throw "shadowed root splice";
		}
		ordinary();
	}

	/** Ordinary code that declares a root name keeps reading its own binding. */
	static function ordinary():Void {
		final haxe = {ds: {Expr: 3}};
		final hxhxmacrohost = {MacroReificationValues: 4};
		check(haxe.ds.Expr + hxhxmacrohost.MacroReificationValues == 7, "ordinary locals named like roots");
	}

	static function fields():Expr {
		check(haxe + Std + hxhxmacrohost == 24, "shadowing fields");
		return macro 1;
	}

	static function local():Expr {
		var haxe = 42;
		check(haxe == 42, "shadowing local");
		return macro 1;
	}

	static function parameters(Std:Int, hxhxmacrohost:Int, haxe:Int):Expr {
		check(Std + hxhxmacrohost + haxe == 6, "shadowing parameters");
		return macro 2;
	}

	/** A payload named like a root still means the user's binding. */
	static function rootLocals():Expr {
		final haxe = "haxe";
		final Std = macro 3;
		final hxhxmacrohost = macro 4;
		return macro f($i{haxe}, $Std, $hxhxmacrohost);
	}
}
