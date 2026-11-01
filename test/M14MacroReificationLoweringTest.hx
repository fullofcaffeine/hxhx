/**
	A macro quotation lowers to the ordinary syntax that builds its `haxe.macro.Expr`.

	Each case parses a quote (`macro ...` or `macro :T`), lowers it with a scripted static-type
	probe for `$v{}` payloads, and compares the result with hand-written Haxe source through the
	parser's exact expression fingerprint. `@P` in an expectation is the quote's position record,
	`ExprDef.`, `Constant.` and the other enum owners are the fully qualified
	`haxe.macro.Expr.<Enum>.` paths. Unsupported syntax must fail with a named reason.
**/
class M14MacroReificationLoweringTest {
	static final FILE = "Main.hx";
	static final ANCHOR = new HxPos(10, 2, 3);
	static final OWNERS = [
		"ExprDef",
		"Constant",
		"Binop",
		"Unop",
		"ComplexType",
		"StringLiteralKind",
		"EFieldKind",
		"FunctionKind",
		"QuoteStatus",
		"TypeParam"
	];

	static var types:Map<String, String> = new Map();

	static function probe(payload:HxExpr):TyType {
		return switch payload {
			case ENull: TyType.fromHintText("Null");
			case EIdent(name) if (types.exists(name)): TyType.fromHintText(types.get(name));
			case _: TyType.unknown();
		};
	}

	static function lower(source:String):HxExpr {
		return switch HxParser.parseExprText(source) {
			case EMacroExpr(inner, wrappers): MacroReificationLowering.lowerExpression(inner, wrappers, FILE, ANCHOR, probe);
			case EMacroType(text): MacroReificationLowering.lowerType(text, FILE, ANCHOR);
			case other: throw "not a quotation: " + Std.string(other);
		};
	}

	static function position(index:Int):String
		return 'cast({file: "' + FILE + '", min: ' + index + ', max: ' + index + '}, haxe.macro.Expr.Position)';

	static function expand(expected:String):String {
		var text = StringTools.replace(expected, "@P", position(ANCHOR.getIndex()));
		for (owner in OWNERS)
			text = StringTools.replace(text, " " + owner + ".", " haxe.macro.Expr." + owner + ".");
		return text;
	}

	static function expect(label:String, source:String, expected:String):Void {
		final lowered = TypedBodyFingerprint.exactExpression(lower(source));
		final wanted = TypedBodyFingerprint.exactExpression(HxParser.parseExprText(expand(expected)));
		if (lowered != wanted)
			throw label + ": lowered syntax differs from the expectation\n  lowered:  " + lowered + "\n  expected: " + wanted;
	}

	static function expectFailure(label:String, source:String, fragment:String):Void {
		final message = try {
			lower(source);
			"";
		} catch (error:String) {
			error;
		}
		if (!StringTools.startsWith(message, "macro reification:") && !StringTools.startsWith(message, "macro syntax export:"))
			throw label + ": expected a named failure, got `" + message + "`";
		if (message.indexOf(fragment) < 0)
			throw label + ": expected `" + fragment + "` in `" + message + "`";
	}

	static function constant(definition:String):String
		return "{expr: ExprDef.EConst( Constant." + definition + "), pos: @P}";

	static function main():Void {
		types = [
			"n" => "Int",
			"f" => "Float",
			"s" => "String",
			"b" => "Bool",
			"maybe" => "Null<Int>",
			"words" => "Array<String>",
			"grid" => "Array<Null<Int>>",
			"obj" => "{a:Int}"
		];

		// Constants, identifiers, and nesting through every exported form share the quote's position.
		expect("int", "macro 1", constant('CInt("1", null)'));
		expect("string", "macro \"x\"", constant('CString("x", StringLiteralKind.DoubleQuotes)'));
		expect("ident", "macro foo", constant('CIdent("foo")'));
		expect("binop", "macro a + 1", "{expr: ExprDef.EBinop( Binop.OpAdd, "
			+ constant('CIdent("a")')
			+ ", "
			+ constant('CInt("1", null)')
			+ "), pos: @P}");
		expect("field", "macro a.b", "{expr: ExprDef.EField(" + constant('CIdent("a")') + ', "b", EFieldKind.Normal), pos: @P}');
		expect("call", "macro f(a)", "{expr: ExprDef.ECall("
			+ constant('CIdent("f")')
			+ ", ["
			+ constant('CIdent("a")')
			+ "]), pos: @P}");
		expect("if without else", "macro if (c) 1", "{expr: ExprDef.EIf("
			+ constant('CIdent("c")')
			+ ", "
			+ constant('CInt("1", null)')
			+ ", null), pos: @P}");
		expect("untyped", "macro untyped x", "{expr: ExprDef.EUntyped(" + constant('CIdent("x")') + "), pos: @P}");
		expect("unary", "macro !x", "{expr: ExprDef.EUnop( Unop.OpNot, false, " + constant('CIdent("x")') + "), pos: @P}");

		// A brace group owns its own parser position (index 6 in this text); its children inherit it.
		expect("block", "macro { 1; }",
			'{expr: ExprDef.EBlock([{expr: ExprDef.EConst( Constant.CInt("1", null)), pos: '
			+ position(6)
			+ "}]), pos: "
			+ position(6)
			+ "}");

		// `$v{}` selects the constant from the payload's static type.
		expect("value int", "macro $v{n}", constant("CInt(Std.string(n), null)"));
		expect("value float", "macro $v{f}", constant("CFloat(Std.string(f), null)"));
		expect("value string", "macro $v{s}", constant("CString(s, StringLiteralKind.DoubleQuotes)"));
		expect("value bool", "macro $v{b}", constant('CIdent(b ? "true" : "false")'));
		expect("value null", "macro $v{null}", constant('CIdent("null")'));
		expect("value nullable", "macro $v{maybe}", "maybe == null ? "
			+ constant('CIdent("null")')
			+ " : "
			+ constant("CInt(Std.string(maybe), null)"));
		expect("value array", "macro $v{words}", "hxhxmacrohost.MacroReificationValues.strings(words, @P)");
		expectFailure("value nested array", "macro $v{grid}", "arrays of Int, Float, Bool, or String; this payload has type Array<Null<Int>>");

		// Identifier, expression, block, array, field, and type-path splices.
		expect("ident splice", "macro $i{name}", "{expr: ExprDef.EConst( Constant.CIdent(name)), pos: @P}");
		expect("expr splice", "macro $e{e}", "e");
		expect("bare splice", "macro $e + 1", "{expr: ExprDef.EBinop( Binop.OpAdd, e, " + constant('CInt("1", null)') + "), pos: @P}");
		expect("block splice", "macro $b{es}", "{expr: ExprDef.EBlock(es), pos: @P}");
		expect("array splice alone", "macro [$a{es}]", "{expr: ExprDef.EArrayDecl(es), pos: @P}");
		expect("array splice as sole argument", "macro f($a{es})", "{expr: ExprDef.ECall(" + constant('CIdent("f")') + ", es), pos: @P}");
		expect("array splice beside an argument", "macro f(0, $a{es})",
			"{expr: ExprDef.ECall("
			+ constant('CIdent("f")')
			+ ", ["
			+ constant('CInt("0", null)')
			+ ", {expr: ExprDef.EArrayDecl(es), pos: @P}]), pos: @P}");
		expect("array splice in place", "macro $a{es}", "{expr: ExprDef.EArrayDecl(es), pos: @P}");
		expect("field splice", "macro o.$name", "{expr: ExprDef.EField(" + constant('CIdent("o")') + ", name, EFieldKind.Normal), pos: @P}");
		expect("type path splice", "macro new $tp(1)", "{expr: ExprDef.ENew(tp, [" + constant('CInt("1", null)') + "]), pos: @P}");

		// `@:pos(p)` binds to the unary expression and replaces every position inside it.
		expect("pos on a call", "macro @:pos(p) f(1)",
			'{expr: ExprDef.ECall({expr: ExprDef.EConst( Constant.CIdent("f")), pos: p}, [{expr: ExprDef.EConst( Constant.CInt("1", null)), pos: p}]), pos: p}');
		expect("pos on an operand", "macro @:pos(p) 1 + 2",
			'{expr: ExprDef.EBinop( Binop.OpAdd, {expr: ExprDef.EConst( Constant.CInt("1", null)), pos: p}, ' + constant('CInt("2", null)') + "), pos: @P}");

		// Type quotations.
		final path = (name:String) -> ' ComplexType.TPath({pack: [], name: "' + name + '", params: [], sub: null})';
		expect("type path", "macro :X", path("X"));
		expect("function type", "macro :X->Y", " ComplexType.TFunction([" + path("X") + "], " + path("Y") + ")");
		expect("type arguments", "macro :Array<Int>",
			' ComplexType.TPath({pack: [], name: "Array", params: [ TypeParam.TPType(' + path("Int") + ")], sub: null})");
		expect("module sub-type", "macro :haxe.macro.Expr.ExprDef", ' ComplexType.TPath({pack: ["haxe", "macro"], name: "Expr", params: [], sub: "ExprDef"})');
		expect("optional named", "macro :(?a:Int)->Void",
			" ComplexType.TFunction([ ComplexType.TParent( ComplexType.TOptional( ComplexType.TNamed(\"a\", "
			+ path("Int")
			+ ")))], "
			+ path("Void")
			+ ")");

		// Explicit failures.
		expectFailure("path splice", "macro $p{parts}", "`$p{}` is not lowered yet");
		expectFailure("other metadata", "macro @:keep 1", "metadata `@keep` inside a quotation is not lowered yet");
		expectFailure("value of a structure", "macro $v{obj}", "this payload has type {a:Int}");
		expectFailure("value of unknown type", "macro $v{mystery}", "requires a payload whose type is known");
		expectFailure("switch", "macro switch x { case 1: 2; }", "switch expressions are not exported yet");

		Sys.println("M14_MACRO_REIFICATION_LOWERING:PASS");
	}
}
