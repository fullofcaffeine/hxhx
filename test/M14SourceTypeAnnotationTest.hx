import backend.source.SourceNativeTarget;

/** Source annotations check compatibility and retain selected conversions without becoming authored casts. */
@:access(backend.source.SourceTargetCommon)
class M14SourceTypeAnnotationTest {
	static function main():Void {
		run();
	}

	static function typed(source:String):TypedModule {
		final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		return TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
	}

	static function ungroup(value:TypedExpr):TypedExpr {
		return value.getTag() == Parenthesized ? ungroup(value.getExpressions()[0]) : value;
	}

	static function value(source:String):TypedExpr {
		for (owner in typed(source).getTypedClasses())
			for (initializer in owner.getFieldInitializers())
				if (initializer.getField().getName() == "value")
					return ungroup(initializer.getExpression());
		throw "annotation fixture lacks its value initializer";
	}

	static function rejected(source:String, message:String):Void {
		try
			typed(source)
		catch (failure:haxe.Exception) {
			if (failure.message.indexOf(message) >= 0)
				return;
			throw failure;
		}
		throw "incompatible source annotation was accepted";
	}

	/** Both syntax and selected conversion effects must survive the shared typed representation. */
	public static function run():Void {
		final annotation = HxParser.parseCompleteExprText("(box:Int)");
		final checked = HxParser.parseCompleteExprText("(cast(box,Int))");
		if (!annotation.match(EParenthesized(ECheckType(EIdent("box"), "Int"), _))
			|| !checked.match(EParenthesized(ECast(EIdent("box"), "Int"), _)))
			throw "source annotation and checked cast lost their distinct syntax";
		if (TypedBodyFingerprint.exactExpression(annotation) == TypedBodyFingerprint.exactExpression(checked))
			throw "source operation is absent from exact revision identity";

		final fields = "class Main { static var box:Box<Int> = 7; static var value:Int = ";
		final tail = "; static function main():Void {} } ";
		rejected(fields + "(box:Int)" + tail + "abstract Box<T>(T) from T {}", "should be Int");
		rejected("class Main { static var value:String = (7:String); static function main():Void {} }", "should be String");
		final castValue = value(fields + "cast(box,Int)" + tail + "abstract Box<T>(T) from T {}");
		if (castValue.getTag() != Cast || castValue.isRepresentationPreservingCast())
			throw "authored checked cast acquired annotation or representation permission";
		final header = value(fields + "(box:Int)" + tail + "abstract Box<T>(T) from T to T {}");
		if (header.getTag() != CheckType
			|| header.getExpressions()[0].getTag() != Cast
			|| !header.getExpressions()[0].isRepresentationPreservingCast())
			throw "annotation lost its selected header conversion";

		final converted = value("class Main { static var box:Box = 7; static var value:Int = (box:Int); static function main():Void {} }"
			+ "abstract Box(Int) from Int { @:to public function toInt():Int { return this + 1; } }");
		final call = converted.getExpressions()[0];
		if (converted.getTag() != CheckType
			|| call.getTag() != Call
			|| call.getDeclaration() == null
			|| call.getDeclaration().getSignature().getName() != "toInt")
			throw "annotation erased its executable output conversion";

		typed("class Main { static function main():Void { var f = ((function(x) { return x + 1; }):Int->Int); var result:Int = f(6); } }");
		typed("class Main { static var value:String = untyped (7:String); static function main():Void {} }");
		final quoted = HxParser.parseCompleteExprText("macro (7:String)");
		final quote = TypedBodyBuilder.buildExpression(quoted, HxPos.unknown(), null);
		final restored = TypedSourceSyntax.expression(quote);
		if (TypedBodyFingerprint.exactExpression(quoted) != TypedBodyFingerprint.exactExpression(restored))
			throw "quoted invalid annotation was checked, converted, or reconstructed as a cast";
		for (target in [Python, Java, Cs, Php, Lua]) {
			// In particular, PHP must not add its checked-cast runtime operation.
			final output = backend.source.SourceTargetCommon.renderExpr(target, ECheckType(EInt(7), "Int"));
			if (output != "7")
				throw "source annotation acquired a target runtime operation: " + output;
		}
		JsRuntimeFixture.assertRuntime(typed("class Main { static var calls:Int = 0;"
			+ "static function fresh():Int { calls++; return 7; }"
			+ "static function main():Void { var annotated:Int = (fresh():Int); var checked:Int = cast(fresh(),Int);"
			+ "var apply = ((function(value) { return value + 1; }):Int->Int);"
			+ "Sys.println(apply(annotated)); Sys.println(checked); Sys.println(calls); } }"),
			"Main", "8\n7\n2\n");
		Sys.println("SOURCE_TYPE_ANNOTATION:PASS");
	}
}
