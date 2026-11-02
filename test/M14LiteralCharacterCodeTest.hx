/** Literal character codes must become exact Int constants before backend projection. */
class M14LiteralCharacterCodeTest {
	static function typedValue(expression:String, hint:String = ":Int"):TypedExpr {
		final source = "class Main { static var value" + hint + " = " + expression + "; static function main():Void {} }";
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		return typed.getTypedClasses()[0].getFieldInitializers()[0].getExpression();
	}

	/** The `expr` field of a lowered `{expr: <ExprDef>, pos: <Position>}` record. */
	static function loweredDefinition(record:TypedExpr):TypedExpr {
		if (record.getTag() != Anonymous || record.getTexts().join(",") != "expr,pos")
			throw "quotation was not lowered to an Expr record";
		return record.getExpressions()[0];
	}

	/** A lowered constructor call; this fixture loads no `haxe.macro.Expr`, so the callee's last segment names it. */
	static function loweredConstruction(call:TypedExpr, name:String):TypedExpr {
		final callee = call.getTag() == Call ? call.getExpressions()[0] : null;
		if (callee == null || callee.getTag() != FieldRead || callee.getTexts()[0] != name)
			throw "expected the lowered `" + name + "` construction";
		return call;
	}

	static function main():Void {
		for (entry in [
			{source: '"A".code', value: 65},
			{source: '" ".code', value: 32},
			{source: '"\\n".code', value: 10},
			{source: '"\\x00".code', value: 0},
			{source: '"\\101".code', value: 65},
			{source: '"\\177".code', value: 127},
			{source: '"\\000".code', value: 0},
			{source: "'A'.code", value: 65},
			{source: '"é".code', value: 233},
			{source: '"😀".code', value: 128512},
			{source: '"\\u00E9".code', value: 233},
			{source: '"\\u{1F600}".code', value: 128512},
			{source: "'\\u{1F600}'.code", value: 128512},
			{source: '"\\u{10FFFF}".code', value: 1114111},
			{source: '"\\u{000000041}".code', value: 65}
		]) {
			final value = typedValue(entry.source);
			if (value.getType().getSemanticKey() != "primitive:Int" || value.getTag() != IntValue || value.getIntValue() != entry.value)
				throw "literal character code differs: " + entry.source;
		}
		for (source in ['"".code', '"ab".code', '"é".code', "'$" + "$'.code", "'$" + "{\"A\"}'.code"]) {
			var rejected = false;
			try
				typedValue(source)
			catch (failure:TyperError) {
				if (failure.toString().indexOf("String must be a single UTF8 char") < 0)
					throw failure;
				rejected = true;
			}
			if (!rejected)
				throw "invalid literal code accepted: " + source;
		}
		for (source in ['("A").code', '("" + "A").code', '{ var text:String = "A"; text.code; }']) {
			var rejected = false;
			try
				typedValue(source)
			catch (failure:TyperError) {
				if (failure.toString().indexOf("String has no field code") < 0)
					throw failure;
				rejected = true;
			}
			if (!rejected)
				throw "nonliteral code accepted: " + source;
		}
		for (escape in [
			"\\xE9",
			"\\uD800",
			"\\u{110000}",
			"\\u{}",
			"\\u{GG}",
			"\\u041",
			"\\xGG",
			"\\0",
			"\\b",
			"\\200",
			"\\377",
			"\\400"
		]) {
			for (quote in ['"', "'"]) {
				var rejected = false;
				try
					HxParser.parseCompleteExprText(quote + escape + quote)
				catch (_:HxParseError)
					rejected = true;
				if (!rejected)
					throw "invalid escape accepted: " + escape;
			}
		}
		switch HxParser.parseCompleteExprText('macro "A".code') {
			case EMacroExpr(EField(EString("A"), "code"), _):
			case _:
				throw "literal code was folded before macro quotation";
		}
		// The typer lowers a quote to the construction of its `Expr` value. Inside it, `"A".code`
		// stays the field access `EField(EConst(CString("A")), "code")`: it is neither folded to a
		// character code nor rejected for an empty or multi-character string.
		for (text in ["A", "", "ab"]) {
			final quote = typedValue('macro "' + text + '".code', "");
			final field = loweredConstruction(loweredDefinition(quote), "EField");
			final constant = loweredConstruction(loweredConstruction(loweredDefinition(field.getExpressions()[1]), "EConst").getExpressions()[1], "CString");
			if (constant.getExpressions()[1].getTag() != StringValue
				|| constant.getExpressions()[1].getTexts()[0] != text
				|| field.getExpressions()[2].getTag() != StringValue
				|| field.getExpressions()[2].getTexts()[0] != "code")
				throw "typing changed quoted literal syntax";
		}
		switch HxParser.parseCompleteExprText("'$" + "$'") {
			case EString(value) if (value == "$"):
			case _:
				throw "ordinary string interpolation changed";
		}
		final ordinary = typedValue("({code: 17}).code");
		if (ordinary.getTag() != FieldRead)
			throw "ordinary code field became a literal intrinsic";
		Sys.println("LITERAL_CHARACTER_CODE:PASS");
	}
}
