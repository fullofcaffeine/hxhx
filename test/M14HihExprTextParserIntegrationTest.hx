class M14HihExprTextParserIntegrationTest {
	static function fail(msg:String):Void {
		throw msg;
	}

	static function assertTrue(ok:Bool, msg:String):Void {
		if (!ok)
			fail(msg);
	}

	static function main() {
		// Native parser payloads can compact escaped quote strings to `"""`.
		// This should still parse as a normal string literal (`"`).
		final denseArrayRaw = '[" ".code,"(".code,")".code,"%".code,"!".code,"^".code,""".code,"<".code,">".code,"&".code,"|".code,"\\n".code,"\\r".code,",".code,";".code]';
		final denseArrayExpr = HxParser.parseExprText(denseArrayRaw);
		switch (denseArrayExpr) {
			case EArrayDecl(values):
				assertTrue(values.length == 15, "expected 15 array elements");
				switch (values[6]) {
					case EField(EString(v), "code"):
						assertTrue(v == "\"", 'expected index 6 to be quote char, got "' + v + '"');
					case _:
						fail("expected index 6 to parse as quote-char .code access");
				}
			case _:
				fail("expected dense quote payload to parse as EArrayDecl");
		}

		// Block-expression initializers should not degrade to EUnsupported when they
		// appear in dense native payload text with trailing tokens.
		final denseBlockRaw = '{varh=newhaxe.ds.StringMap();h.set("quot",""");h;}staticpublicfunctionparse(){}';
		final denseBlockExpr = HxParser.parseExprText(denseBlockRaw);
		switch (denseBlockExpr) {
			case ETryCatchRaw(raw):
				assertTrue(raw == "opaque_block_expr", "expected opaque block marker");
			case EUnsupported(raw):
				fail("dense block payload parsed as unsupported: " + raw);
			case _:
				fail("dense block payload should parse as opaque block expression");
		}

		// Constructor expressions with dotted type paths should stay as ENew nodes.
		final newExprRaw = "new js.lib.DataView(new js.lib.ArrayBuffer(8))";
		final newExpr = HxParser.parseExprText(newExprRaw);
		switch (newExpr) {
			case ENew(typePath, args):
				assertTrue(typePath == "js.lib.DataView", "expected outer constructor type path");
				assertTrue(args.length == 1, "expected one constructor argument");
				switch (args[0]) {
					case ENew(innerTypePath, innerArgs):
						assertTrue(innerTypePath == "js.lib.ArrayBuffer", "expected nested constructor type path");
						assertTrue(innerArgs.length == 1, "expected nested constructor argument");
						switch (innerArgs[0]) {
							case EInt(v):
								assertTrue(v == 8, "expected nested constructor literal argument");
							case _:
								fail("expected nested constructor argument to parse as EInt");
						}
					case _:
						fail("expected nested constructor argument to parse as ENew");
				}
			case _:
				fail("constructor expression should parse as ENew");
		}

		// Native payloads may compact `new` spacing (`newFoo(...)`); keep constructor parsing resilient.
		final compactNewExprRaw = "newjs.lib.DataView(newjs.lib.ArrayBuffer(8))";
		final compactNewExpr = HxParser.parseExprText(compactNewExprRaw);
		switch (compactNewExpr) {
			case ENew(typePath, args):
				assertTrue(typePath == "js.lib.DataView", "expected compact outer constructor type path");
				assertTrue(args.length == 1, "expected compact constructor argument");
				switch (args[0]) {
					case ENew(innerTypePath, innerArgs):
						assertTrue(innerTypePath == "js.lib.ArrayBuffer", "expected compact nested constructor type path");
						assertTrue(innerArgs.length == 1, "expected compact nested constructor argument");
						switch (innerArgs[0]) {
							case EInt(v):
								assertTrue(v == 8, "expected compact nested constructor literal argument");
							case _:
								fail("expected compact nested constructor argument to parse as EInt");
						}
					case _:
						fail("expected compact nested constructor argument to parse as ENew");
				}
			case _:
				fail("compact constructor expression should parse as ENew");
		}

		// Haxe accepts float literals with a trailing decimal point. Upstream math
		// tests use this shape in call arguments, so the lexer must not leave the
		// dot behind and make the body parser recover with `body_parse_error`.
		final trailingDotStmts = HxParser.parseFunctionBodyText("eq(Math.floor(-10000000000.7)*1.0, -10000000001.);");
		assertTrue(trailingDotStmts.length == 1, "expected trailing-dot float statement to parse as one statement");
		switch (trailingDotStmts[0]) {
			case SExpr(EUnsupported(raw), _):
				fail("trailing-dot float statement parsed as unsupported: " + raw);
			case _:
		}

		final quotedKeyExpr = HxParser.parseExprText('{ "new": "test" }');
		switch (quotedKeyExpr) {
			case EAnon(names, values):
				assertTrue(names.length == 1, "expected one quoted-key object field");
				assertTrue(names[0] == "new", "expected quoted object key to be preserved");
				switch (values[0]) {
					case EString(v):
						assertTrue(v == "test", "expected quoted-key object value to parse");
					case _:
						fail("expected quoted-key object value to parse as string");
				}
			case ETryCatchRaw(raw):
				fail("quoted-key object literal degraded to opaque block: " + raw);
			case _:
				fail("quoted-key object literal should parse as EAnon");
		}

		final localFunctionStmts = HxParser.parseFunctionBodyText("function helper(v:Int):String { return Std.string(v); } eq(helper(3), \"3\");");
		assertTrue(localFunctionStmts.length == 2, "expected local function plus call statement");
		switch (localFunctionStmts[0]) {
			case SVar(name, _, ELambda(args, _), _):
				assertTrue(name == "helper", "expected local function to lower to helper binding");
				assertTrue(args.length == 1 && args[0] == "v", "expected local function arg to be preserved");
			case SExpr(EUnsupported(raw), _):
				fail("local function declaration parsed as unsupported: " + raw);
			case _:
				fail("expected local function declaration to lower to SVar lambda");
		}

		final contextualAsStmts = HxParser.parseFunctionBodyText('var as = new unit.MyAbstract.MyAbstractSetter(); as.value = "foo"; eq(as.value, "foo");');
		assertTrue(contextualAsStmts.length == 3, "expected contextual `as` local plus two statements");
		switch (contextualAsStmts[0]) {
			case SVar(name, _, ENew(path, _), _):
				assertTrue(name == "as", "expected `as` to parse as a local variable name");
				assertTrue(path == "unit.MyAbstract.MyAbstractSetter", "expected constructor path after `as` local to parse");
			case SExpr(EUnsupported(raw), _):
				fail("contextual `as` local parsed as unsupported: " + raw);
			case _:
				fail("expected contextual `as` local declaration to parse");
		}
		switch (contextualAsStmts[1]) {
			case SExpr(EBinop("=", EField(EIdent(name), field), EString(value)), _):
				assertTrue(name == "as", "expected `as.value` assignment receiver to parse as identifier");
				assertTrue(field == "value", "expected `as.value` assignment field to parse");
				assertTrue(value == "foo", "expected assignment value to parse");
			case SExpr(EUnsupported(raw), _):
				fail("contextual `as` assignment parsed as unsupported: " + raw);
			case _:
				fail("expected contextual `as` assignment to parse");
		}

		final regexStmts = HxParser.parseFunctionBodyText('var r = ~/a+(b)?(c*)a+/; t( ~/\n/.match("\\n") ); var g = ~/cat/g; eq( ~/a+/g.replace("aabbccaa", "x"), "xbbccx" );');
		assertTrue(regexStmts.length == 4, "expected regex literal declarations/calls to parse");
		switch (regexStmts[0]) {
			case SVar(name, _, ENew(path, args), _):
				assertTrue(name == "r", "expected regex local name to parse");
				assertTrue(path == "EReg", "expected regex literal to lower to EReg constructor");
				assertTrue(args.length == 2, "expected regex pattern and flags constructor args");
			case SExpr(EUnsupported(raw), _):
				fail("regex literal declaration parsed as unsupported: " + raw);
			case _:
				fail("expected regex literal declaration to parse");
		}

		final inlineConditionalStmts = HxParser.parseFunctionBodyText("t(r.matched(1) == null #if js || js.Browser.supported #end);");
		assertTrue(inlineConditionalStmts.length == 1, "expected inline JS conditional marker statement to parse");
		switch (inlineConditionalStmts[0]) {
			case SExpr(EUnsupported(raw), _):
				fail("inline JS conditional marker parsed as unsupported: " + raw);
			case _:
		}
	}
}
