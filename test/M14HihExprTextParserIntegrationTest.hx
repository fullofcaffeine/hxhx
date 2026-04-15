class M14HihExprTextParserIntegrationTest {
	static function fail(msg:String):Void {
		throw msg;
	}

	static function assertTrue(ok:Bool, msg:String):Void {
		if (!ok)
			fail(msg);
	}

	static function assertPushTryCatchRaw(stmts:Array<HxStmt>, msg:String):Void {
		assertTrue(stmts.length == 1, msg + ": expected one push statement");
		switch (stmts[0]) {
			case SExpr(ECall(EField(EIdent(receiver), field), [ETryCatchRaw(raw)]), _):
				assertTrue(receiver == "result", msg + ": expected result.push receiver");
				assertTrue(field == "push", msg + ": expected push call");
				assertTrue(raw.indexOf("try{") == 0, msg + ": expected canonical try raw, got " + raw);
				assertTrue(raw.indexOf("catch(e:Exception)") >= 0, msg + ": expected typed catch signature, got " + raw);
			case SExpr(EUnsupported(raw), _):
				fail(msg + ": try/catch expression parsed as unsupported: " + raw);
			case _:
				fail(msg + ": expected push call with raw try/catch expression");
		}
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

		final bitwiseNotStmts = HxParser.parseFunctionBodyText("int64eq(~a, Int64.make(0xF0000000, 0xFFFFFFFE));");
		assertTrue(bitwiseNotStmts.length == 1, "expected unary bitwise-not call to parse as one statement");
		switch (bitwiseNotStmts[0]) {
			case SExpr(ECall(EIdent("int64eq"), [EUnop("~", EIdent("a")), ECall(EField(EIdent("Int64"), "make"), _)]), _):
			case SExpr(EUnsupported(raw), _):
				fail("unary bitwise-not statement parsed as unsupported: " + raw);
			case _:
				fail("expected unary bitwise-not call expression");
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

		final localReturnFunctionStmts = HxParser.parseFunctionBodyText("function capture() return Int64.compare(a, Int64.make(1, 2)); eq(capture(), 0);");
		assertTrue(localReturnFunctionStmts.length == 2, "expected local return function plus call statement");
		switch (localReturnFunctionStmts[0]) {
			case SVar(name, _, ELambda(args, ECall(EField(EIdent("Int64"), "compare"), [EIdent("a"), ECall(EField(EIdent("Int64"), "make"), _)])), _):
				assertTrue(name == "capture", "expected local return function name to parse");
				assertTrue(args.length == 0, "expected zero-arg local return function");
			case SVar(_, _, ELambda(_, EUnsupported(raw)), _):
				fail("local return function body parsed as unsupported: " + raw);
			case _:
				fail("expected local return function to lower to lambda call body");
		}

		final inlineLocalFunctionStmts = HxParser.parseFunctionBodyText("inline function check(a:haxe.Int64, str:String) { eq(toHex(a), str); } check(x, \"0x21\");");
		assertTrue(inlineLocalFunctionStmts.length == 2, "expected inline local function plus call statement");
		switch (inlineLocalFunctionStmts[0]) {
			case SVar(name, _, ELambda(args, _), _):
				assertTrue(name == "check", "expected inline local function name to parse");
				assertTrue(args.length == 2 && args[0] == "a" && args[1] == "str", "expected inline local function args");
			case SExpr(EUnsupported(raw), _):
				fail("inline local function declaration parsed as unsupported: " + raw);
			case _:
				fail("expected inline local function to lower to SVar lambda");
		}

		final macroDecl = new HxParser("package unit; class TestIssues { macro static public function addIssueClasses(dir:String, pack:String) { return null; } }")
			.parseModule("TestIssues");
		final macroFuncs = HxClassDecl.getFunctions(HxModuleDecl.getMainClass(macroDecl));
		assertTrue(macroFuncs.length == 1, "expected macro static function to parse");
		assertTrue(HxFunctionDecl.getName(macroFuncs[0]) == "addIssueClasses", "expected macro function name to parse");
		assertTrue(HxFunctionDecl.getIsStatic(macroFuncs[0]), "expected macro static modifier to parse");
		assertTrue(HxFunctionDecl.getMetadata(macroFuncs[0]).indexOf("macro") >= 0, "expected macro modifier metadata");

		final localIfThrowStmts = HxParser.parseFunctionBodyText("function negativeOnly(i:Int) { if(i >= 0) throw new ArgumentException('i'); } negativeOnly(10);");
		assertTrue(localIfThrowStmts.length == 2, "expected local if/throw function plus call statement");
		switch (localIfThrowStmts[0]) {
			case SVar(name, _, ELambda(args, ETernary(_, ECall(EIdent(throwName), [_]), ENull)), _):
				assertTrue(name == "negativeOnly", "expected local function name to parse");
				assertTrue(args.length == 1 && args[0] == "i", "expected local function arg to parse");
				assertTrue(throwName == "__hxhx_throw", "expected throw statement to lower to throw sentinel");
			case SVar(_, _, ELambda(_, EUnsupported(raw)), _):
				fail("local if/throw function body parsed as unsupported: " + raw);
			case _:
				fail("expected local if/throw function to lower to lambda ternary");
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

		final keyValueForStmts = HxParser.parseFunctionBodyText("var data = ['left' => [1], 'right' => [2]]; for(label => stacks in data) { t(stacks.length > 0, label); }");
		assertTrue(keyValueForStmts.length == 2, "expected map literal plus key/value for statement");
		switch (keyValueForStmts[1]) {
			case SForKeyValue(keyName, valueName, EIdent(iterable), SBlock(_, _), _):
				assertTrue(keyName == "label", "expected key binding to parse");
				assertTrue(valueName == "stacks", "expected value binding to parse");
				assertTrue(iterable == "data", "expected iterable identifier to parse");
			case SExpr(EUnsupported(raw), _):
				fail("key/value for parsed as unsupported: " + raw);
			case _:
				fail("expected key/value for statement");
		}

		final privateAccessStmts = HxParser.parseFunctionBodyText("result.push(@:privateAccess (Exception.thrown(''):Exception).stack);");
		assertTrue(privateAccessStmts.length == 1, "expected privateAccess push statement");
		switch (privateAccessStmts[0]) {
			case SExpr(ECall(EField(EIdent(receiver), field), [EField(_, stackField)]), _):
				assertTrue(receiver == "result", "expected result.push receiver");
				assertTrue(field == "push", "expected push call");
				assertTrue(stackField == "stack", "expected privateAccess expression field");
			case SExpr(EUnsupported(raw), _):
				fail("privateAccess expression parsed as unsupported: " + raw);
			case _:
				fail("expected privateAccess expression statement to parse");
		}

		assertPushTryCatchRaw(HxParser.parseFunctionBodyText("result.push(try throw new Exception('') catch(e:Exception) e.stack);"),
			"single-expression try throw");
		assertPushTryCatchRaw(HxParser.parseFunctionBodyText("result.push(try throw @:privateAccess (Exception.thrown(''):Exception) catch(e:Exception) e.stack);"),
			"single-expression try throw privateAccess cast");

		final switchThrowExpr = HxParser.parseExprText("switch s { case v: throw 'unknown value $v'; }");
		switch (switchThrowExpr) {
			case ESwitch(_, patterns, exprs):
				assertTrue(patterns.length == 1, "expected one switch throw pattern");
				switch (exprs[0]) {
					case ECall(EIdent(throwName), [_]):
						assertTrue(throwName == "__hxhx_throw", "expected switch throw branch to lower to throw sentinel");
					case EUnsupported(raw):
						fail("switch throw expression parsed as unsupported: " + raw);
					case _:
						fail("expected switch throw branch to lower to sentinel call");
				}
			case EUnsupported(raw):
				fail("switch throw expression parsed as unsupported: " + raw);
			case _:
				fail("expected switch expression with throw branch");
		}

		final enumExtractStmts = HxParser.parseFunctionBodyText("var result = {}; switch item { case FilePos(s, f, l, _): result.file = f; result.line = l; switch s { case Method(_, m): result.method = m; case _: } case _: } return result;");
		assertTrue(enumExtractStmts.length == 3, "expected result local, switch, return");
		switch (enumExtractStmts[1]) {
			case SSwitch(EIdent(scrutinee), patterns, bodies, _):
				assertTrue(scrutinee == "item", "expected switch scrutinee to parse");
				assertTrue(patterns.length == 2, "expected enum extractor plus wildcard case");
				switch (patterns[0]) {
					case PEnumExtract(name, args):
						assertTrue(name == "FilePos", "expected FilePos extractor pattern");
						assertTrue(args.length == 4, "expected FilePos extractor args");
						switch (args[0]) {
							case PBind(bindName):
								assertTrue(bindName == "s", "expected first extractor arg binder");
							case _:
								fail("expected first extractor arg to bind s");
						}
						switch (args[3]) {
							case PWildcard:
							case _:
								fail("expected fourth extractor arg to be wildcard");
						}
					case _:
						fail("expected enum extractor switch pattern");
				}
				switch (bodies[0]) {
					case SBlock(branchStmts, _):
						assertTrue(branchStmts.length == 3, "expected FilePos case statements");
						switch (branchStmts[2]) {
							case SSwitch(EIdent(nestedScrutinee), nestedPatterns, _, _):
								assertTrue(nestedScrutinee == "s", "expected nested switch over extracted binder");
								switch (nestedPatterns[0]) {
									case PEnumExtract(nestedName, nestedArgs):
										assertTrue(nestedName == "Method", "expected nested Method extractor");
										assertTrue(nestedArgs.length == 2, "expected Method extractor args");
									case _:
										fail("expected nested enum extractor pattern");
								}
							case _:
								fail("expected nested switch in FilePos branch");
						}
					case _:
						fail("expected FilePos case body block");
				}
			case SExpr(EUnsupported(raw), _):
				fail("enum extractor switch parsed as unsupported: " + raw);
			case _:
				fail("expected enum extractor switch statement");
		}
	}
}
