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
		assertTrue(ParserStageScanHelpers.hasUnsupportedStmtList([SExpr(ECall(EIdent("f"), [EUnsupported("<eof-stmt>")]), HxPos.unknown())]),
			"unsupported scanner must inspect call arguments");

		final malformedBodyStmts = HxParser.parseFunctionBodyText("foo.; after();");
		assertTrue(malformedBodyStmts.length >= 1, "expected malformed body to produce a recovery statement");
		switch (malformedBodyStmts[0]) {
			case SExpr(EUnsupported(raw), _):
				assertTrue(raw.indexOf("body_parse_error") == 0, "expected detailed body parse marker");
				assertTrue(raw.indexOf("tok=") >= 0, "expected detailed body parse marker to include token");
				assertTrue(raw.indexOf("err=") >= 0, "expected detailed body parse marker to include error");
			case _:
				fail("expected malformed body to recover as unsupported parse marker");
		}

		final unsupportedKeywordExpr = HxParser.parseExprText("case value");
		switch (unsupportedKeywordExpr) {
			case EUnsupported(raw):
				assertTrue(raw.indexOf("case@idx=") == 0, "expected unsupported keyword detail to include keyword and index");
				assertTrue(raw.indexOf("@near=case value") >= 0, "expected unsupported keyword detail to include source context");
			case _:
				fail("expected unsupported keyword expression diagnostic");
		}

		final recoveredCaseFragment = HxParser.parseFunctionBodyText('case OpIncrement: "++";\n\t\t\tcase OpDecrement: "--";');
		assertTrue(recoveredCaseFragment.length == 2, "expected top-level case fragments to recover as neutral statements");
		for (stmt in recoveredCaseFragment) {
			switch (stmt) {
				case SExpr(ENull, _):
				case SExpr(EUnsupported(raw), _):
					fail("top-level recovered case fragment should not stay unsupported: " + raw);
				case _:
					fail("top-level recovered case fragment should decode as neutral expression statement");
			}
		}

		final anonymousFunctionStmt = HxParser.parseFunctionBodyText("function() { return 1; }; after();");
		assertTrue(anonymousFunctionStmt.length == 2, "expected anonymous function statement plus following statement");
		switch (anonymousFunctionStmt[0]) {
			case SExpr(ELambda([], EInt(1)), _):
			case SExpr(EUnsupported(raw), _):
				fail("anonymous function statement parsed as unsupported: " + raw);
			case _:
				fail("expected anonymous function statement to parse as lambda expression");
		}

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
				assertTrue(raw.indexOf("opaque_block_expr:") == 0, "expected opaque block marker");
			case EUnsupported(raw):
				fail("dense block payload parsed as unsupported: " + raw);
			case _:
				// Parseable block expressions may now lower structurally instead of staying opaque.
		}

		final typedBlockExpr = HxParser.parseExprText('{ var b:{v:Int} = {v:1.2}; }');
		switch (typedBlockExpr) {
			case ETryCatchRaw(raw):
				assertTrue(raw.indexOf("opaque_block_expr:") == 0, "expected block marker with preserved source");
				assertTrue(raw.indexOf("var b") >= 0, "expected block source to include declaration");
				assertTrue(raw.indexOf("v:Int") >= 0, "expected block source to include type hint");
			case EUnsupported(raw):
				fail("typed block expression parsed as unsupported: " + raw);
			case _:
				// Parseable block expressions may now lower structurally instead of staying opaque.
		}

		final typedBlockCallStmts = HxParser.parseFunctionBodyText("check(typeError({ var b: { v:Int } = { v: 1.2 }; })); after();");
		assertTrue(typedBlockCallStmts.length == 2, "expected typed block call plus following statement");
		switch (typedBlockCallStmts[0]) {
			case SExpr(ECall(EIdent("check"), [ECall(EIdent("typeError"), [arg])]), _):
				switch (arg) {
					case EUnsupported(raw):
						fail("nested typed block expression parsed as unsupported: " + raw);
					case _:
				}
			case SExpr(EUnsupported(raw), _):
				fail("typed block call statement parsed as unsupported: " + raw);
			case _:
				fail("expected typed block expression to stay inside typeError call");
		}

		final semicolonlessAnonStmts = HxParser.parseFunctionBodyText("final equiv:Equivclass = { hash: h, length: length }\nequivIndex = ctx.addEquiv(equiv);\na.push(equivIndex);");
		assertTrue(semicolonlessAnonStmts.length == 3, "semicolonless anonymous object initializer should not consume following assignment");
		switch (semicolonlessAnonStmts[1]) {
			case SExpr(EBinop("=", EIdent("equivIndex"), ECall(EField(EIdent("ctx"), "addEquiv"), [EIdent("equiv")])), _):
			case _:
				fail("expected assignment after semicolonless anonymous object initializer to parse as its own statement");
		}

		final mutableMapBlockExpr = HxParser.parseExprText('{ var h = new haxe.ds.StringMap(); h.set("lt", "<"); h; }');
		switch (mutableMapBlockExpr) {
			case ETryCatchRaw(raw):
				assertTrue(raw.indexOf("opaque_block_expr:") == 0, "expected mutable map block to stay opaque");
			case EUnsupported(raw):
				fail("mutable map block parsed as unsupported: " + raw);
			case _:
				fail("mutable map block should stay opaque for Stage3 poison/stub compatibility");
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

		final nestedQuoteInterpolationStmts = HxParser.parseFunctionBodyText("if (exit == 124) { println('No response in ${Config.read('limit')} seconds.'); }");
		assertTrue(nestedQuoteInterpolationStmts.length == 1, "expected nested-quote interpolation if statement to parse");
		switch (nestedQuoteInterpolationStmts[0]) {
			case SIf(_, SBlock([
				SExpr(ECall(EIdent("println"), [
					EBinop("+", EBinop("+", EString(_), EBinop("+", EString(_), ECall(EField(EIdent("Config"), "read"), [EString(arg)]))), EString(_))
				]), _)
			], _), null, _):
				assertTrue(arg == "limit", "expected interpolation payload call to preserve nested quoted argument");
			case SIf(_, SBlock([SExpr(ECall(EIdent("println"), [EBinop("+", EString(_), EString(message))]), _)], _), null, _):
				assertTrue(message.indexOf("Config.read('limit')") >= 0, "expected interpolation payload to preserve nested quoted argument");
			case SExpr(EUnsupported(raw), _):
				fail("nested-quote interpolation parsed as unsupported: " + raw);
			case _:
				fail("expected nested-quote interpolation in if statement");
		}

		final doubleQuotedDollarExpr = HxParser.parseExprText("\"a $HOME b\"");
		switch (doubleQuotedDollarExpr) {
			case EString(value):
				assertTrue(value == "a $HOME b", "expected double-quoted dollar text to stay literal");
			case EBinop(_, _, _):
				fail("double-quoted dollar text should not become interpolation");
			case _:
				fail("expected double-quoted dollar text to parse as EString");
		}

		final singleQuotedDollarExpr = HxParser.parseExprText("'a $value b'");
		switch (singleQuotedDollarExpr) {
			case EBinop(_, _, _):
			case EString(_):
				fail("single-quoted dollar text should keep interpolation behavior");
			case _:
				fail("expected single-quoted dollar text to parse as interpolation concat");
		}

		final thisFieldInterpolationExpr = HxParser.parseExprText("'[IV +${this.index}]'");
		switch (thisFieldInterpolationExpr) {
			case EBinop("+", EBinop("+", EString(prefix), EBinop("+", EString(emptyPrefix), EField(EThis, field))), EString(suffix)):
				assertTrue(prefix == "[IV +", "expected this-field interpolation prefix");
				assertTrue(emptyPrefix == "", "expected this-field interpolation to force string concat");
				assertTrue(field == "index", "expected this-field interpolation to preserve field name");
				assertTrue(suffix == "]", "expected this-field interpolation suffix");
			case _:
				fail("expected this-field interpolation to parse as EField(EThis, index)");
		}

		final literalInterpolationExpr = HxParser.parseExprText("'${5}'");
		switch (literalInterpolationExpr) {
			case EBinop("+", EString(emptyPrefix), EInt(value)):
				assertTrue(emptyPrefix == "", "expected literal interpolation to force string concat");
				assertTrue(value == 5, "expected literal interpolation to preserve integer payload");
			case EString(value):
				fail("literal interpolation should not stay literal: " + value);
			case _:
				fail("expected literal interpolation to parse as an integer payload");
		}

		final switchCaseSequenceStmts = HxParser.parseFunctionBodyText("var result = switch [ok, expected] { case [true, false]: true; case [false, false]: var detail = proc.stderr.readAll().toString(); Sys.print(detail); false; case _: false; };");
		assertTrue(switchCaseSequenceStmts.length == 1, "expected switch expression case bodies to stay inside one var statement");
		switch (switchCaseSequenceStmts[0]) {
			case SVar("result", _, ESwitch(EArrayDecl(_), patterns, exprs), _):
				assertTrue(patterns.length == 3, "expected all switch expression cases to parse");
				assertTrue(exprs.length == 3, "expected all switch expression branch values to parse");
				switch (exprs[1]) {
					case EUnsupported(raw):
						fail("switch expression statement-sequence branch parsed as unsupported: " + raw);
					case _:
				}
			case SVar(_, _, EUnsupported(raw), _):
				fail("switch expression case sequence parsed as unsupported: " + raw);
			case _:
				fail("expected switch expression with case statement sequences");
		}

		final charCodeSwitchModule = "class CharCodeSwitch {\n" + "  static function postProcess(s:String) {\n" + "    switch (s.charAt(0)) {\n"
			+ "      case '+'.code:\n" + "        return 1;\n" + "      case '%'.code if (s.length > 1):\n" + "        switch [s.charAt(1), s.charAt(2)] {\n"
			+ "          case ['2'.code, '1'.code]: return 2;\n" + "          case _: return 3;\n" + "        }\n" + "      case _: return 0;\n" + "    }\n"
			+ "  }\n" + "}\n";
		final charCodeDecl = new HxParser(charCodeSwitchModule).parseModule("CharCodeSwitch");
		final charCodeFn = HxClassDecl.getFunctions(HxModuleDecl.getMainClass(charCodeDecl))[0];
		switch (HxFunctionDecl.getBody(charCodeFn)[0]) {
			case SSwitch(_, patterns, bodies, _):
				assertTrue(patterns.length == 3, "expected char-code switch patterns");
				switch (patterns[0]) {
					case PInt(code):
						assertTrue(code == "+".code, "expected '+'.code switch pattern");
					case _:
						fail("expected first char-code case to parse as PInt");
				}
				switch (patterns[1]) {
					case PUnsupportedGuard(PInt(code)):
						assertTrue(code == "%".code, "expected guarded '%'.code switch pattern");
					case _:
						fail("expected guarded char-code case to stay structured");
				}
				switch (bodies[1]) {
					case SBlock([SSwitch(_, nestedPatterns, _, _)], _):
						switch (nestedPatterns[0]) {
							case PArray([PInt(left), PInt(right)]):
								assertTrue(left == "2".code && right == "1".code, "expected array char-code switch pattern");
							case _:
								fail("expected nested array char-code case to parse structurally");
						}
					case _:
						fail("expected guarded char-code case body to contain nested switch");
				}
			case SExpr(EUnsupported(raw), _):
				fail("char-code switch parsed as unsupported: " + raw);
			case _:
				fail("expected char-code switch statement");
		}

		final importInAliasDecl = new HxParser("package python.internal;\nimport python.Syntax.code in py;\nclass ImportInAlias {}\n")
			.parseModule("ImportInAlias");
		final importInAliasImports = HxModuleDecl.getImports(importInAliasDecl);
		assertTrue(importInAliasImports.length == 1, "expected import-in alias to preserve one import");
		assertTrue(importInAliasImports[0] == "python.Syntax.code", "expected import-in alias path without alias");

		final switchNoSemicolonThenElseIfStmts = HxParser.parseFunctionBodyText("var result = switch [ok, expected] { case [true, false]: true; case _: false; }\nif (result && expected != null) { result = check(); } else if (stdout.length > 0) { println(stdout.toString()); }");
		assertTrue(switchNoSemicolonThenElseIfStmts.length == 2, "expected no-semicolon switch initializer before if/else-if to parse as two statements");
		switch (switchNoSemicolonThenElseIfStmts[0]) {
			case SVar("result", _, ESwitch(_, _, _), _):
			case SExpr(EUnsupported(raw), _):
				fail("no-semicolon switch initializer parsed as unsupported: " + raw);
			case _:
				fail("expected first statement to remain switch initializer var");
		}
		switch (switchNoSemicolonThenElseIfStmts[1]) {
			case SIf(_, SBlock(_), SIf(_, SBlock(_), null, _), _):
			case SExpr(EUnsupported(raw), _):
				fail("else-if after no-semicolon switch initializer parsed as unsupported: " + raw);
			case _:
				fail("expected second statement to parse as if/else-if");
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

		final localRestFunctionStmts = HxParser.parseFunctionBodyText("function pick(first:Int, second:Int, ...rest:Int) { return rest[2]; } eq(123, pick(1, 2, 0, 0, 123, 0));");
		assertTrue(localRestFunctionStmts.length == 2, "expected local rest function plus call statement");
		switch (localRestFunctionStmts[0]) {
			case SVar(name, _, ECall(EIdent("__hxhx_rest_lambda"), [ELambda(args, EArrayAccess(EIdent("rest"), EInt(2))), EInt(restIndex)]), _):
				assertTrue(name == "pick", "expected local rest function to lower to pick binding");
				assertTrue(args.length == 3 && args[2] == "rest", "expected local rest arg to parse as runtime arg name");
				assertTrue(restIndex == 2, "expected local rest arg index metadata");
			case SVar(_, _, ELambda(_, EUnsupported(raw)), _):
				fail("local rest function body parsed as unsupported: " + raw);
			case SExpr(EUnsupported(raw), _):
				fail("local rest function parsed as unsupported statement: " + raw);
			case _:
				fail("expected local rest function declaration to lower to SVar lambda");
		}

		final localKeyValueFunctionStmts = HxParser.parseFunctionBodyText("function collect(r:Array<Int>) { var keys = []; var values = []; for (k => v in r) { keys.push(k); values.push(v); } return {keys: keys, values: values}; } var got = collect([3, 2]);");
		assertTrue(localKeyValueFunctionStmts.length == 2, "expected local key/value function plus call statement");
		switch (localKeyValueFunctionStmts[0]) {
			case SVar(name, _, ELambda(args, body), _):
				assertTrue(name == "collect", "expected local key/value function name to parse");
				assertTrue(args.length == 1 && args[0] == "r", "expected local key/value function arg");
				switch (body) {
					case EUnsupported(raw):
						fail("local key/value function body parsed as unsupported: " + raw);
					case _:
				}
			case SExpr(EUnsupported(raw), _):
				fail("local key/value function parsed as unsupported statement: " + raw);
			case _:
				fail("expected local key/value function declaration to lower to SVar lambda");
		}

		final localForInFunctionStmts = HxParser.parseFunctionBodyText("function values(xs:Array<String>) { var out = []; for (x in xs) { out.push(x); } return out; } var got = values([\"a\"]);");
		assertTrue(localForInFunctionStmts.length == 2, "expected local for-in function plus call statement");
		switch (localForInFunctionStmts[0]) {
			case SVar(name, _, ELambda(args, body), _):
				assertTrue(name == "values", "expected local for-in function name to parse");
				assertTrue(args.length == 1 && args[0] == "xs", "expected local for-in function arg");
				switch (body) {
					case EUnsupported(raw):
						fail("local for-in function body parsed as unsupported: " + raw);
					case _:
				}
			case SExpr(EUnsupported(raw), _):
				fail("local for-in function parsed as unsupported statement: " + raw);
			case _:
				fail("expected local for-in function declaration to lower to SVar lambda");
		}

		final localSwitchFunctionStmts = HxParser.parseFunctionBodyText("function label(kind:String) { var out = \"\"; switch (kind) { case \"a\": out = \"A\"; default: out = \"X\"; } return out; } var got = label(\"a\");");
		assertTrue(localSwitchFunctionStmts.length == 2, "expected local switch function plus call statement");
		switch (localSwitchFunctionStmts[0]) {
			case SVar(name, _, ELambda(args, body), _):
				assertTrue(name == "label", "expected local switch function name to parse");
				assertTrue(args.length == 1 && args[0] == "kind", "expected local switch function arg");
				switch (body) {
					case EUnsupported(raw):
						fail("local switch function body parsed as unsupported: " + raw);
					case _:
				}
			case SExpr(EUnsupported(raw), _):
				fail("local switch function parsed as unsupported statement: " + raw);
			case _:
				fail("expected local switch function declaration to lower to SVar lambda");
		}

		final spreadCallStmts = HxParser.parseFunctionBodyText("function spreadRest(r:Array<Int>) { return rest(...r); } var a = rest(...[1, 2, 3]); var b = new Parent(...[1, 2, 3]);");
		assertTrue(spreadCallStmts.length == 3, "expected local spread function plus spread call and constructor");
		switch (spreadCallStmts[0]) {
			case SVar(name, _, ELambda(args, ECall(EIdent("rest"), [ECall(EIdent("__hxhx_spread"), [EIdent("r")])])), _):
				assertTrue(name == "spreadRest", "expected local spread function name to parse");
				assertTrue(args.length == 1 && args[0] == "r", "expected local spread function arg");
			case SVar(_, _, ELambda(_, EUnsupported(raw)), _):
				fail("local spread function body parsed as unsupported: " + raw);
			case SExpr(EUnsupported(raw), _):
				fail("local spread function parsed as unsupported statement: " + raw);
			case _:
				fail("expected local spread function declaration to lower to SVar lambda");
		}
		switch (spreadCallStmts[1]) {
			case SVar("a", _, ECall(EIdent("rest"), [ECall(EIdent("__hxhx_spread"), [EArrayDecl(values)])]), _):
				assertTrue(values.length == 3, "expected spread array literal to parse");
			case SVar(_, _, EUnsupported(raw), _):
				fail("spread call initializer parsed as unsupported: " + raw);
			case _:
				fail("expected spread call initializer");
		}

		final localWhileFunctionStmts = HxParser.parseFunctionBodyText("function count(xs:Array<Int>) { var i = 0; while (i < xs.length) { i += 1; } return i; } var n = count([1, 2, 3]);");
		assertTrue(localWhileFunctionStmts.length == 2, "expected local while function plus call statement");
		switch (localWhileFunctionStmts[0]) {
			case SVar(name, _, ELambda(args, body), _):
				assertTrue(name == "count", "expected local while function name to parse");
				assertTrue(args.length == 1 && args[0] == "xs", "expected local while function arg");
				switch (body) {
					case EUnsupported(raw):
						fail("local while function body parsed as unsupported: " + raw);
					case _:
				}
			case SExpr(EUnsupported(raw), _):
				fail("local while function parsed as unsupported statement: " + raw);
			case _:
				fail("expected local while function declaration to lower to SVar lambda");
		}

		final inlineExprStmts = HxParser.parseFunctionBodyText("function stringify(value:Dynamic, max:Int) { return inline helper(value, max - 1); } var s = stringify(v, 10);");
		assertTrue(inlineExprStmts.length == 2, "expected inline expression function plus call statement");
		switch (inlineExprStmts[0]) {
			case SVar(name, _, ELambda(_, ECall(EIdent("helper"), [EIdent("value"), EBinop("-", EIdent("max"), EInt(1))])), _):
				assertTrue(name == "stringify", "expected inline expression function name to parse");
			case SVar(_, _, ELambda(_, EUnsupported(raw)), _):
				fail("inline expression function body parsed as unsupported: " + raw);
			case SExpr(EUnsupported(raw), _):
				fail("inline expression function parsed as unsupported statement: " + raw);
			case _:
				fail("expected inline expression return to lower to helper call");
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

		final localGenericReturnFunctionStmts = HxParser.parseFunctionBodyText("function box<T>(value:T):Box<T> return { get: function() return value; }; box(1);");
		assertTrue(localGenericReturnFunctionStmts.length == 2, "expected local generic return function plus call statement");
		switch (localGenericReturnFunctionStmts[0]) {
			case SVar(name, _, ELambda(args, EAnon(names, _)), _):
				assertTrue(name == "box", "expected local generic function name to parse");
				assertTrue(args.length == 1 && args[0] == "value", "expected local generic function arg to parse");
				assertTrue(names.length == 1 && names[0] == "get", "expected expression-bodied return object to parse");
			case SVar(_, _, ELambda(_, EUnsupported(raw)), _):
				fail("local generic return function body parsed as unsupported: " + raw);
			case SExpr(EUnsupported(raw), _):
				fail("local generic return function declaration parsed as unsupported: " + raw);
			case _:
				fail("expected local generic return function to lower to lambda object body");
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

		final macroSource = "package unit; class TestIssues { macro static public function addIssueClasses(dir:String, pack:String) { return null; } }";
		final macroDecl = new HxParser(macroSource).parseModule("TestIssues");
		final macroFuncs = HxClassDecl.getFunctions(HxModuleDecl.getMainClass(macroDecl));
		assertTrue(macroFuncs.length == 1, "expected macro static function to parse");
		assertTrue(HxFunctionDecl.getName(macroFuncs[0]) == "addIssueClasses", "expected macro function name to parse");
		assertTrue(HxFunctionDecl.getIsStatic(macroFuncs[0]), "expected macro static modifier to parse");
		assertTrue(HxFunctionDecl.getMetadata(macroFuncs[0]).indexOf("macro") >= 0, "expected macro modifier metadata");
		final scannedMacroClasses = ParserStageScanHelpers.scanModuleLocalHelperClasses(macroSource, null);
		assertTrue(scannedMacroClasses.length == 1, "expected scanner to find macro helper class");
		final scannedMacroFuncs = HxClassDecl.getFunctions(scannedMacroClasses[0]);
		assertTrue(scannedMacroFuncs.length == 1, "expected scanner to find macro helper function");
		assertTrue(HxFunctionDecl.getMetadata(scannedMacroFuncs[0]).indexOf("macro") >= 0, "expected scanner macro modifier metadata");

		final staticAccessorSource = [
			"class MyDynamicClass {",
			"  static var Z = 10;",
			"  public dynamic static function staticDynamic(x, y) {",
			"    return Z + x + y;",
			"  }",
			"  @:isVar public static var W(get, set):Int = 55;",
			"  static function get_W() return W + 2;",
			"  static function set_W(v) { W = v; return v; }",
			"}",
		].join("\n");
		final staticAccessorClasses = ParserStageScanHelpers.scanModuleLocalHelperClasses(staticAccessorSource, null);
		assertTrue(staticAccessorClasses.length == 1, "expected scanner to find static accessor helper class");
		final staticAccessorFuncs = HxClassDecl.getFunctions(staticAccessorClasses[0]);
		final bodyLengths = new Map<String, Int>();
		for (fn in staticAccessorFuncs)
			bodyLengths.set(HxFunctionDecl.getName(fn), HxFunctionDecl.getBody(fn).length);
		assertTrue(bodyLengths.get("get_W") == 1, "scanner should preserve expression-bodied static getters");
		assertTrue(bodyLengths.get("set_W") == 2, "scanner should preserve assignment-plus-return static setters");

		final constrainedHelperSource = [
			"class Base {",
			"  public function new() {}",
			"}",
			"class ConstraintHelper {",
			"  static public function staticSingle<A:Base>(a:A):A {",
			"    return a;",
			"  }",
			"  public function memberAnon<A:{ x : Int } & { y : Float }>(v:A) {",
			"    return v.x + v.y;",
			"  }",
			"}",
		].join("\n");
		final constrainedHelperClasses = ParserStageScanHelpers.scanModuleLocalHelperClasses(constrainedHelperSource, null);
		var staticSingle:Null<HxFunctionDecl> = null;
		var memberAnon:Null<HxFunctionDecl> = null;
		for (cls in constrainedHelperClasses) {
			if (HxClassDecl.getName(cls) != "ConstraintHelper")
				continue;
			for (fn in HxClassDecl.getFunctions(cls)) {
				switch (HxFunctionDecl.getName(fn)) {
					case "staticSingle":
						staticSingle = fn;
					case "memberAnon":
						memberAnon = fn;
					case _:
				}
			}
		}
		assertTrue(staticSingle != null, "scanner should find constrained static helper");
		assertTrue(HxFunctionDecl.getArgs(staticSingle).length == 1, "scanner should preserve constrained static helper arg");
		switch (HxFunctionDecl.getBody(staticSingle)) {
			case [SReturn(EIdent(name), _)]:
				assertTrue(name == "a", "scanner should preserve simple constrained static return body");
			case _:
				fail("scanner should keep constrained static return body");
		}
		assertTrue(memberAnon != null, "scanner should find structural constrained member helper");
		final memberAnonArgs = HxFunctionDecl.getArgs(memberAnon);
		assertTrue(memberAnonArgs.length == 1 && HxFunctionArg.getName(memberAnonArgs[0]) == "v",
			"scanner should skip structural constraints before reading member args");
		switch (HxFunctionDecl.getBody(memberAnon)) {
			case [SReturn(EBinop("+", EField(EIdent(left), "x"), EField(EIdent(right), "y")), _)]:
				assertTrue(left == "v" && right == "v", "scanner should parse structural constrained member body");
			case _:
				fail("scanner should preserve structural constrained member return body");
		}

		final semicolonlessSwitchFieldSource = [
			"class TestFileSystem {",
			'  var tailingSlashes = switch (Sys.systemName()) {',
			'    case "Windows": ["", "/", "\\\\"];',
			'    case _: ["", "/"];',
			"  }",
			"  public function setup() {}",
			"}"
		].join("\n");
		final semicolonlessSwitchFieldDecl = new HxParser(semicolonlessSwitchFieldSource).parseModule("TestFileSystem");
		final semicolonlessSwitchFields = HxClassDecl.getFields(HxModuleDecl.getMainClass(semicolonlessSwitchFieldDecl));
		assertTrue(semicolonlessSwitchFields.length == 1, "expected semicolonless switch field initializer to parse as one field");
		switch (HxFieldDecl.getInit(semicolonlessSwitchFields[0])) {
			case ESwitch(_, patterns, exprs):
				assertTrue(patterns.length == 2, "expected switch field initializer cases");
				assertTrue(exprs.length == 2, "expected switch field initializer branch expressions");
			case EUnsupported(raw):
				fail("semicolonless switch field initializer parsed as unsupported: " + raw);
			case _:
				fail("expected switch field initializer to parse structurally");
		}

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

		final localBlockThrowFunctionStmts = HxParser.parseFunctionBodyText('function failBlock():String { throw "never"; }; var s = try failBlock() catch(e:String) e; eq(s, "never");');
		assertTrue(localBlockThrowFunctionStmts.length == 3, "expected local block throw function, var, and assertion");
		switch (localBlockThrowFunctionStmts[0]) {
			case SVar("failBlock", _, ELambda([], ECall(EIdent("__hxhx_throw"), [EString("never")])), _):
			case SExpr(EUnsupported(raw), _):
				fail("local block throw function parsed as unsupported: " + raw);
			case _:
				fail("expected local block throw function to lower to throwing lambda");
		}

		final localTryFunctionStmts = HxParser.parseFunctionBodyText('function next() { try { var read = file.readBytes(buf, 0, len); return Std.string(read); } catch(e:haxe.io.Eof) { return Std.string("eof"); } catch(e:Dynamic) { return Std.string(e); } } eq("24", next());');
		assertTrue(localTryFunctionStmts.length == 2, "expected local try function plus assertion");
		switch (localTryFunctionStmts[0]) {
			case SVar("next", _, ELambda([], ECall(EIdent("__hxhx_try"), args)), _):
				assertTrue(args.length == 3, "expected try sentinel, catch table, and continuation");
			case SVar(_, _, ELambda(_, EUnsupported(raw)), _):
				fail("local try function body parsed as unsupported: " + raw);
			case SExpr(EUnsupported(raw), _):
				fail("local try function parsed as unsupported statement: " + raw);
			case _:
				fail("expected local try function to lower to try sentinel lambda");
		}

		final inlineNekoElseThrowStmts = HxParser.parseFunctionBodyText('try { read(); } catch(e:haxe.io.Eof) { if (s.length == 0) #if neko neko.Lib.rethrow #else throw #end (e); }');
		assertTrue(inlineNekoElseThrowStmts.length == 1, "expected inline neko/else throw try statement");
		switch (inlineNekoElseThrowStmts[0]) {
			case STry(_, catches, _):
				assertTrue(catches.length == 1, "expected one inline neko/else throw catch");
				switch (catches[0].body) {
					case SBlock([SIf(_, SThrow(EIdent("e"), _), null, _)], _):
					case SBlock([SIf(_, SBlock([SThrow(EIdent("e"), _)], _), null, _)], _):
					case SBlock([SIf(_, SExpr(EUnsupported(raw), _), null, _)], _):
						fail("inline neko/else throw parsed as unsupported expression: " + raw);
					case SBlock([SIf(_, SThrow(EUnsupported(raw), _), null, _)], _):
						fail("inline neko/else throw payload parsed as unsupported: " + raw);
					case SBlock([SIf(_, SBlock([SThrow(EUnsupported(raw), _)], _), null, _)], _):
						fail("inline neko/else throw payload parsed as unsupported: " + raw);
					case SBlock([SExpr(EUnsupported(raw), _)], _):
						fail("inline neko/else throw catch parsed as unsupported: " + raw);
					case _:
						fail("expected inline neko/else throw to normalize to if/throw catch body: " + Std.string(catches[0].body));
				}
			case SExpr(EUnsupported(raw), _):
				fail("inline neko/else throw try parsed as unsupported statement: " + raw);
			case _:
				fail("expected inline neko/else throw to parse as try statement");
		}

		final inlineNekoElseModule = [
			"class InputLike {",
			"  public function readLine():String {",
			"    var s = \"\";",
			"    try {",
			"      read();",
			"    } catch (e:Eof) {",
			"      if (s.length == 0)",
			"        #if neko neko.Lib.rethrow #else throw #end (e);",
			"    }",
			"    return s;",
			"  }",
			"}"
		].join("\n");
		final inlineNekoElseDecl = new HxParser(inlineNekoElseModule).parseModule("InputLike");
		final inlineNekoElseFns = HxClassDecl.getFunctions(HxModuleDecl.getMainClass(inlineNekoElseDecl));
		assertTrue(inlineNekoElseFns.length == 1, "expected inline neko/else module function");
		switch (HxFunctionDecl.getBody(inlineNekoElseFns[0])) {
			case [SVar("s", _, _, _), STry(_, catches, _), SReturn(EIdent("s"), _)]:
				assertTrue(catches.length == 1, "expected module inline neko/else catch");
				switch (catches[0].body) {
					case SBlock([SIf(_, SThrow(EIdent("e"), _), null, _)], _):
					case SBlock([SIf(_, SBlock([SThrow(EIdent("e"), _)], _), null, _)], _):
					case SBlock([SIf(_, SExpr(EUnsupported(raw), _), _, _)], _):
						fail("module inline neko/else throw parsed as unsupported expression: " + raw);
					case SBlock([SIf(_, SThrow(EUnsupported(raw), _), _, _)], _):
						fail("module inline neko/else throw payload parsed as unsupported: " + raw);
					case _:
						fail("expected module inline neko/else throw catch body: " + Std.string(catches[0].body));
				}
			case [_, STry(_, catches, _), _] if (catches.length > 0):
				fail("expected module inline neko/else function body without parser drift: " + Std.string(catches[0].body));
			case body:
				fail("expected module inline neko/else function body shape: " + Std.string(body));
		}
		switch (localBlockThrowFunctionStmts[1]) {
			case SVar("s", _, ETryCatchRaw(_), _):
			case SExpr(EUnsupported(raw), _):
				fail("try/catch after local block throw function parsed as unsupported: " + raw);
			case _:
				fail("expected statement after local block throw function to remain aligned");
		}

		final localExprThrowFunctionStmts = HxParser.parseFunctionBodyText('function failExpr():String throw "never"; var s = try failExpr() catch(e:String) e; eq(s, "never");');
		assertTrue(localExprThrowFunctionStmts.length == 3, "expected local expression throw function, var, and assertion");
		switch (localExprThrowFunctionStmts[0]) {
			case SVar("failExpr", _, ELambda([], ECall(EIdent("__hxhx_throw"), [EString("never")])), _):
			case SVar(_, _, ELambda(_, EUnsupported(raw)), _):
				fail("local expression throw function body parsed as unsupported: " + raw);
			case SExpr(EUnsupported(raw), _):
				fail("local expression throw function parsed as unsupported: " + raw);
			case _:
				fail("expected local expression throw function to lower to throwing lambda");
		}

		final nullCoalescingStmts = HxParser.parseFunctionBodyText('var value = left ?? right; left ??= fallback; final notNull = (one : Null<Float>) ?? throw "";');
		assertTrue(nullCoalescingStmts.length == 3, "expected null coalescing statements");
		switch (nullCoalescingStmts[0]) {
			case SVar("value", _, EBinop("??", EIdent("left"), EIdent("right")), _):
			case SVar(_, _, EUnsupported(raw), _):
				fail("null coalescing value parsed as unsupported: " + raw);
			case _:
				fail("expected null coalescing value expression");
		}
		switch (nullCoalescingStmts[1]) {
			case SExpr(EBinop("??=", EIdent("left"), EIdent("fallback")), _):
			case SExpr(EUnsupported(raw), _):
				fail("null coalescing assignment parsed as unsupported: " + raw);
			case _:
				fail("expected null coalescing assignment expression");
		}
		switch (nullCoalescingStmts[2]) {
			case SVar("notNull", _, EBinop("??", ECast(EIdent("one"), "Null<Float>"), ECall(EIdent("__hxhx_throw"), [EString("")])), _):
			case SVar(_, _, EUnsupported(raw), _):
				fail("null coalescing throw fallback parsed as unsupported: " + raw);
			case _:
				fail("expected null coalescing throw fallback expression");
		}

		final blockTerminatorStmts = HxParser.parseFunctionBodyText('{ deq(0, numericCast(0)); };');
		assertTrue(blockTerminatorStmts.length == 1, "expected trailing semicolon after block to be skipped");
		switch (blockTerminatorStmts[0]) {
			case SBlock([
				SExpr(ECall(EIdent("deq"), [EInt(0), ECall(EIdent("numericCast"), [EInt(0)])]), _)
			], _):
			case SExpr(EUnsupported(raw), _):
				fail("block terminator parsed as unsupported: " + raw);
			case _:
				fail("expected numeric-cast-style block body to remain a single block");
		}

		final numericSeparatorStmts = HxParser.parseFunctionBodyText('eq(12_0, 120); eq(0x12_0, 0x120); feq(.3_4, .34); feq(1_2e3_4, 12e34); feq(1_2f64, 12f64); eq(12_0_i32, 120i32);');
		assertTrue(numericSeparatorStmts.length == 6, "expected numeric separator statements to parse");
		for (stmt in numericSeparatorStmts) {
			switch (stmt) {
				case SExpr(EUnsupported(raw), _):
					fail("numeric separator statement parsed as unsupported: " + raw);
				case SExpr(ECall(_, args), _):
					assertTrue(args.length == 2, "expected numeric separator call to keep two args");
				case _:
					fail("expected numeric separator call statement");
			}
		}

		final numericSuffixStmts = HxParser.parseFunctionBodyText('eq(7i32, 7); eq(-1u32, (-1 : UInt)); eq(3000000000000i64 + "", "3000000000000"); eq(0xFFFFFFFFu32, (0xFFFFFFFF : UInt));');
		assertTrue(numericSuffixStmts.length == 4, "expected numeric suffix statements to parse");
		for (stmt in numericSuffixStmts) {
			switch (stmt) {
				case SExpr(EUnsupported(raw), _):
					fail("numeric suffix statement parsed as unsupported: " + raw);
				case SExpr(ECall(_, args), _):
					assertTrue(args.length == 2, "expected numeric suffix call to keep two args");
				case _:
					fail("expected numeric suffix call statement");
			}
		}
		switch (numericSuffixStmts[2]) {
			case SExpr(ECall(EIdent("eq"), [
				EBinop("+", ECall(EIdent("__hxhx_int_literal"), [EString("3000000000000"), EString("i64")]), EString("")),
				_
			]), _):
			case _:
				fail("expected i64 decimal suffix to preserve raw literal text");
		}
		switch (numericSuffixStmts[0]) {
			case SExpr(ECall(EIdent("eq"), [ECall(EIdent("__hxhx_int_literal"), [EString("7"), EString("i32")]), EInt(7)]), _):
			case _:
				fail("expected i32 suffix to preserve raw literal text");
		}
		switch (numericSuffixStmts[3]) {
			case SExpr(ECall(EIdent("eq"), [
				ECall(EIdent("__hxhx_int_literal"), [EString("0xFFFFFFFF"), EString("u32")]),
				ECast(EInt(-1), "UInt")
			]), _):
			case _:
				fail("expected u32 hex suffix and UInt cast to preserve numeric intent");
		}

		final floatSuffixTypeTestStmts = HxParser.parseFunctionBodyText('eq(1f64 is Float, true); eq(.0f64, 0.0); eq(7e+0f64, 7e+0);');
		assertTrue(floatSuffixTypeTestStmts.length == 3, "expected float suffix type-test statements to parse");
		switch (floatSuffixTypeTestStmts[0]) {
			case SExpr(ECall(EIdent("eq"), [EBinop("is", EFloat(_), EEnumValue("Float")), EBool(true)]), _):
			case SExpr(EUnsupported(raw), _):
				fail("float suffix type-test statement parsed as unsupported: " + raw);
			case _:
				fail("expected float suffix type-test call statement");
		}

		final arrowComprehensionStmts = HxParser.parseFunctionBodyText("arr = [for (i in 0...5) value -> value * i];");
		assertTrue(arrowComprehensionStmts.length == 1, "expected range comprehension arrow assignment");
		switch (arrowComprehensionStmts[0]) {
			case SExpr(EBinop("=", EIdent("arr"),
				EArrayComprehension("i", ERange(EInt(0), EInt(5)), null, ELambda(args, EBinop("*", EIdent("value"), EIdent("i"))))),
				_):
				assertTrue(args.length == 1 && args[0] == "value", "expected arrow comprehension arg name");
			case SExpr(EUnsupported(raw), _):
				fail("range comprehension arrow parsed as unsupported: " + raw);
			case _:
				fail("expected range comprehension arrow assignment to parse");
		}

		final guardComprehensionStmts = HxParser.parseFunctionBodyText("arr = [for (x in values) if (keep(x)) x];");
		assertTrue(guardComprehensionStmts.length == 1, "expected guarded comprehension assignment");
		switch (guardComprehensionStmts[0]) {
			case SExpr(EBinop("=", EIdent("arr"), EArrayComprehension("x", EIdent("values"), ECall(EIdent("keep"), [EIdent("x")]), EIdent("x"))), _):
			case SExpr(EUnsupported(raw), _):
				fail("guarded comprehension parsed as unsupported: " + raw);
			case _:
				fail("expected guarded comprehension assignment to parse");
		}

		final mapComprehensionStmts = HxParser.parseFunctionBodyText('var map = [for (x in ["a", "b"]) x => x.toUpperCase()];');
		assertTrue(mapComprehensionStmts.length == 1, "expected map comprehension declaration");
		switch (mapComprehensionStmts[0]) {
			case SVar("map", _, ECall(EIdent("__hxhx_map_comprehension"), [
				EArrayDecl([EString("a"), EString("b")]),
				ELambda(args, EArrayDecl([EIdent("x"), ECall(EField(EIdent("x"), "toUpperCase"), [])]))
			]), _):
				assertTrue(args.length == 1 && args[0] == "x", "expected map comprehension loop variable");
			case SExpr(EUnsupported(raw), _) | SVar(_, _, EUnsupported(raw), _):
				fail("map comprehension parsed as unsupported: " + raw);
			case _:
				fail("expected map comprehension to parse as helper call");
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

		final typeErrorForStmts = HxParser.parseFunctionBodyText("var s = HelperMacros.typeErrorText(for (key => value in 1) { }); eq(\"Int has no field keyValueIterator\", s);");
		assertTrue(typeErrorForStmts.length == 2, "expected typeErrorText key/value for body plus assertion");
		switch (typeErrorForStmts[0]) {
			case SVar("s", _, ECall(EField(EIdent("HelperMacros"), "typeErrorText"), [EUnsupported(raw)]), _):
				assertTrue(raw.indexOf("for_expr:") == 0, "expected expression-position for placeholder, got " + raw);
				assertTrue(raw.indexOf("key => value") >= 0, "expected key/value bindings in raw for placeholder, got " + raw);
			case SExpr(EUnsupported(raw), _):
				fail("typeErrorText key/value for parsed as unsupported statement: " + raw);
			case _:
				fail("expected typeErrorText key/value for expression initializer");
		}

		final valueForExprStmts = HxParser.parseFunctionBodyText("exc(function() for (x in xml) null);");
		assertTrue(valueForExprStmts.length == 1, "expected expression-position for-in callback");
		switch (valueForExprStmts[0]) {
			case SExpr(ECall(EIdent("exc"), [
				ELambda(fnArgs, ECall(EIdent("__hxhx_for_in"), [EIdent("xml"), ELambda(loopArgs, _), ENull]))
			]), _):
				assertTrue(fnArgs.length == 0, "expected zero-arg callback");
				assertTrue(loopArgs.length == 1 && loopArgs[0] == "x", "expected expression for-in loop binding");
			case SExpr(EUnsupported(raw), _):
				fail("expression-position for-in parsed as unsupported: " + raw);
			case _:
				fail("expected expression-position for-in to lower to helper");
		}

		final switchBreakCallback = HxParser.parseFunctionBodyText("run(async, () -> { for (i in 0...items.length) { switch [src.get(i), items.get(i)] { case [a, b] if (a != b): assert('bad'); break; case _: } } noAssert(); async.done(); });");
		assertTrue(switchBreakCallback.length == 1, "expected callback with switch/break body");
		switch (switchBreakCallback[0]) {
			case SExpr(ECall(EIdent("run"), [_, ELambda(_, body)]), _):
				switch (body) {
					case ETryCatchRaw(raw):
						fail("callback switch/break body should lower structurally instead of opaque raw block: " + raw);
					case EUnsupported(raw):
						fail("callback switch/break body parsed as unsupported: " + raw);
					case _:
				}
			case SExpr(EUnsupported(raw), _):
				fail("callback switch/break statement parsed as unsupported: " + raw);
			case _:
				fail("expected run call with callback lambda");
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

		final castPostfixStmts = HxParser.parseFunctionBodyText("t(Std.isOfType(cast(c, Cov1).covariant(), Child1));");
		assertTrue(castPostfixStmts.length == 1, "expected cast-postfix statement");
		switch (castPostfixStmts[0]) {
			case SExpr(ECall(EIdent("t"), [
				ECall(EField(EIdent("Std"), "isOfType"), [ECall(EField(ECast(EIdent("c"), "Cov1"), "covariant"), []), EEnumValue("Child1")])
			]), _):
			case SExpr(EUnsupported(raw), _):
				fail("cast-postfix statement parsed as unsupported: " + raw);
			case _:
				fail("expected cast-postfix call to parse");
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

		final objectPatternStmts = HxParser.parseFunctionBodyText("var out = null; switch payload { case EParenthesis({ expr : EConst(CString(s)) }) | EUntyped({ expr : EConst(CString(s)) }): out = s; case EArray(_, { expr : EConst(CInt(i) | CFloat(i)) }): out = Std.string(i); case _: out = \"none\"; } return out;");
		assertTrue(objectPatternStmts.length == 3, "expected object-pattern switch statement");
		switch (objectPatternStmts[1]) {
			case SSwitch(EIdent(scrutinee), patterns, _, _):
				assertTrue(scrutinee == "payload", "expected object-pattern switch scrutinee");
				assertTrue(patterns.length == 3, "expected object-pattern switch cases");
				switch (patterns[0]) {
					case POr(alternatives):
						assertTrue(alternatives.length == 2, "expected parenthesis/untyped OR alternatives");
						switch (alternatives[0]) {
							case PEnumExtract("EParenthesis", [PObject(fieldNames, fieldPatterns)]):
								assertTrue(fieldNames.length == 1 && fieldNames[0] == "expr", "expected expr object field in first OR branch");
								switch (fieldPatterns[0]) {
									case PEnumExtract("EConst", [PEnumExtract("CString", [PBind("s")])]):
									case _:
										fail("expected nested CString binder in object pattern");
								}
							case _:
								fail("expected first OR branch to be EParenthesis object pattern");
						}
					case _:
						fail("expected first object-pattern case to parse as OR");
				}
				switch (patterns[1]) {
					case PEnumExtract("EArray", [PWildcard, PObject(fieldNames, fieldPatterns)]):
						assertTrue(fieldNames.length == 1 && fieldNames[0] == "expr", "expected EArray index expr object field");
						switch (fieldPatterns[0]) {
							case PEnumExtract("EConst", [POr(numberPatterns)]):
								assertTrue(numberPatterns.length == 2, "expected numeric constant OR pattern");
							case _:
								fail("expected nested numeric constant OR pattern");
						}
					case _:
						fail("expected second object-pattern case to parse as EArray extractor");
				}
			case SExpr(EUnsupported(raw), _):
				fail("object-pattern switch parsed as unsupported: " + raw);
			case _:
				fail("expected object-pattern switch statement");
		}

		final objectPatternReturnStmts = HxParser.parseFunctionBodyText("return switch (payload.expr) { case Wrap(Text(s)): s; case Group({ value : Wrap(Text(s)) }) | Raw({ value : Wrap(Text(s)) }): s; case Pick(_, name): name; case At(_, { value : Wrap(IntText(i) | FloatText(i)) }): Std.string(i); case InOp(In, _, { value : inner, pos : _ }): Std.string(inner); case _: \"none\"; };");
		assertTrue(objectPatternReturnStmts.length == 1, "expected object-pattern switch return statement");
		switch (objectPatternReturnStmts[0]) {
			case SReturn(ESwitch(EField(EIdent(receiver), field), patterns, exprs), _):
				assertTrue(receiver == "payload" && field == "expr", "expected expression switch scrutinee field access");
				assertTrue(patterns.length == 6, "expected expression switch cases");
				assertTrue(exprs.length == 6, "expected expression switch branch expressions");
			case SExpr(EUnsupported(raw), _):
				fail("object-pattern return switch parsed as unsupported: " + raw);
			case SReturn(EUnsupported(raw), _):
				fail("object-pattern return switch expression parsed as unsupported: " + raw);
			case _:
				fail("expected return switch expression with object patterns");
		}

		final capturePatternExpr = HxParser.parseExprText('switch payload { case Wrap(captured = (Text("hello") | IntText("9"))): Std.string(captured); case _: "none"; }');
		switch (capturePatternExpr) {
			case ESwitch(EIdent("payload"), patterns, _):
				assertTrue(patterns.length == 2, "expected capture switch cases");
				switch (patterns[0]) {
					case PEnumExtract("Wrap", [PCapture(name, POr(alternatives))]):
						assertTrue(name == "captured", "expected capture pattern name");
						assertTrue(alternatives.length == 2, "expected capture inner OR alternatives");
					case _:
						fail("expected enum extractor argument capture pattern");
				}
			case EUnsupported(raw):
				fail("capture switch expression parsed as unsupported: " + raw);
			case _:
				fail("expected capture switch expression");
		}

		final arrayPatternExpr = HxParser.parseExprText('switch values { case []: "empty"; case [one]: one; case [left, right]: left + right; case _: "many"; }');
		switch (arrayPatternExpr) {
			case ESwitch(EIdent("values"), patterns, _):
				assertTrue(patterns.length == 4, "expected array switch cases");
				switch (patterns[0]) {
					case PArray(items):
						assertTrue(items.length == 0, "expected empty array pattern");
					case _:
						fail("expected empty array pattern");
				}
				switch (patterns[2]) {
					case PArray([PBind("left"), PBind("right")]):
					case _:
						fail("expected two-item array pattern with binders");
				}
			case EUnsupported(raw):
				fail("array switch expression parsed as unsupported: " + raw);
			case _:
				fail("expected array switch expression");
		}

		final guardedPatternExpr = HxParser.parseExprText('switch values { case var rest if (rest.length == 3): Std.string(rest.length); case _: "other"; }');
		switch (guardedPatternExpr) {
			case ESwitch(EIdent("values"), patterns, _):
				assertTrue(patterns.length == 2, "expected guarded switch cases");
				switch (patterns[0]) {
					case PLengthGuard(PBind("rest"), "rest", 3):
					case _:
						fail("expected guarded bind pattern with length comparison");
				}
			case EUnsupported(raw):
				fail("guarded switch expression parsed as unsupported: " + raw);
			case _:
				fail("expected guarded switch expression");
		}

		final groupedPatternExpr = HxParser.parseExprText('switch v { case 1, 2, 3: "small"; case val = (4 | 5 | 6) if (val == 5): "middle"; case var x: "_"; }');
		switch (groupedPatternExpr) {
			case ESwitch(EIdent("v"), patterns, _):
				assertTrue(patterns.length == 3, "expected grouped switch cases");
				switch (patterns[0]) {
					case POr([PInt(1), PInt(2), PInt(3)]):
					case _:
						fail("expected comma-separated case group to parse as OR pattern");
				}
				switch (patterns[1]) {
					case PIntEqualsGuard(PCapture("val", POr([PInt(4), PInt(5), PInt(6)])), "val", 5):
					case _:
						fail("expected captured OR pattern with integer equality guard");
				}
				final comparePatternExpr = HxParser.parseExprText('switch v { case One(x) if (x <= 1): "<=1"; case One(x) if (x > 1): ">1"; case _: "_"; }');
				switch (comparePatternExpr) {
					case ESwitch(EIdent("v"), comparePatterns, _):
						assertTrue(comparePatterns.length == 3, "expected integer comparison guard cases");
						switch (comparePatterns[0]) {
							case PIntCompareGuard(PEnumExtract("One", [PBind("x")]), "x", "<=", 1):
							case _:
								fail("expected enum extractor pattern with integer <= guard");
						}
						switch (comparePatterns[1]) {
							case PIntCompareGuard(PEnumExtract("One", [PBind("x")]), "x", ">", 1):
							case _:
								fail("expected enum extractor pattern with integer > guard");
						}
					case EUnsupported(raw):
						fail("integer comparison guard switch parsed as unsupported: " + raw);
					case _:
						fail("expected integer comparison guard switch expression");
				}
			case EUnsupported(raw):
				fail("grouped switch expression parsed as unsupported: " + raw);
			case _:
				fail("expected grouped switch expression");
		}

		final extractorPatternExpr = HxParser.parseExprText('switch i { case _.isEven() => true: "even"; case pick(_) => Some(v): v; case _: "other"; }');
		switch (extractorPatternExpr) {
			case ESwitch(EIdent("i"), patterns, _):
				switch (patterns[0]) {
					case PExtractor("_.isEven()", PBool(true)):
					case _:
						fail("expected wildcard method extractor pattern");
				}
				switch (patterns[1]) {
					case PExtractor("pick(_)", PEnumExtract("Some", [PBind("v")])):
					case _:
						fail("expected function-call extractor pattern with result binding");
				}
			case EUnsupported(raw):
				fail("extractor switch parsed as unsupported: " + raw);
			case _:
				fail("expected switch expression with extractor patterns");
		}

		final arrayExtractorPatternExpr = HxParser.parseExprText('switch args { case ["exitCode", Std.parseInt(_) => code]: code; case _: 0; }');
		switch (arrayExtractorPatternExpr) {
			case ESwitch(EIdent("args"), patterns, _):
				switch (patterns[0]) {
					case PArray([PString("exitCode"), PExtractor("Std.parseInt(_)", PBind("code"))]):
					case _:
						fail("expected array pattern with qualified static extractor");
				}
			case EUnsupported(raw):
				fail("array extractor switch parsed as unsupported: " + raw);
			case _:
				fail("expected switch expression with array extractor pattern");
		}

		final switchIfElseSemicolonExpr = HxParser.parseExprText('switch v { case A(x): if (x == null) "null"; else "not null"; }');
		switch (switchIfElseSemicolonExpr) {
			case ESwitch(EIdent("v"), patterns, exprs):
				assertTrue(patterns.length == 1, "expected single enum extractor case");
				switch (patterns[0]) {
					case PEnumExtract("A", [PBind("x")]):
					case _:
						fail("expected enum extractor with binder");
				}
				switch (exprs[0]) {
					case ETernary(_, EString("null"), EString("not null")):
					case EUnsupported(raw):
						fail("switch if/else semicolon branch parsed as unsupported: " + raw);
					case _:
						fail("expected switch branch to parse as ternary expression");
				}
			case EUnsupported(raw):
				fail("switch if/else semicolon expression parsed as unsupported: " + raw);
			case _:
				fail("expected switch expression with if/else branch");
		}

		final binaryIfExpr = HxParser.parseExprText('1 + if (flag) 2 else 3');
		switch (binaryIfExpr) {
			case EBinop("+", EInt(1), ETernary(EIdent("flag"), EInt(2), EInt(3))):
			case EBinop("+", _, EUnsupported(raw)):
				fail("binary RHS if expression parsed as unsupported: " + raw);
			case EUnsupported(raw):
				fail("binary if expression parsed as unsupported: " + raw);
			case _:
				fail("expected binary RHS if expression to parse as ternary");
		}

		final emptyCaseSwitchExpr = HxParser.parseExprText('switch true { case true: case false: }');
		switch (emptyCaseSwitchExpr) {
			case ESwitch(EBool(true), patterns, exprs):
				assertTrue(patterns.length == 2, "expected empty switch cases to preserve two patterns");
				assertTrue(exprs.length == 2, "expected empty switch cases to synthesize two branch expressions");
				switch (patterns[0]) {
					case PBool(true):
					case _:
						fail("expected true literal switch pattern");
				}
				switch (exprs[0]) {
					case ENull:
					case _:
						fail("expected empty switch case body to lower to null expression");
				}
			case EUnsupported(raw):
				fail("empty switch case expression parsed as unsupported: " + raw);
			case _:
				fail("expected switch expression with empty case bodies");
		}

		final macroQuoteCalls = HxParser.parseFunctionBodyText('eq("bar", switchNormal(macro "bar")); eq("bar", switchNormal(macro ("bar"))); eq("bar", switchNormal(macro untyped "bar")); eq("foo", switchNormal(macro null.foo)); eq("22", switchNormal(macro null[22])); eq("in", switchNormal(macro 1 in 0));');
		assertTrue(macroQuoteCalls.length == 6, "expected macro quote call statements to parse");
		for (stmt in macroQuoteCalls) {
			switch (stmt) {
				case SExpr(EUnsupported(raw), _):
					fail("macro quote call parsed as unsupported: " + raw);
				case _:
			}
		}

		final macroIfVars = HxParser.parseFunctionBodyText('var withoutElse = macro if (1) 2; var withElse = macro if (1) 2 else 3;');
		assertTrue(macroIfVars.length == 2, "expected macro if quote vars to parse");
		switch (macroIfVars[0]) {
			case SVar("withoutElse", _, EMacroExpr(ECall(EIdent("__hxhx_macro_if"), [EInt(1), EInt(2), EIdent("__hxhx_macro_missing_else")]), _), _):
			case SVar(_, _, EUnsupported(raw), _):
				fail("macro if without else parsed as unsupported: " + raw);
			case _:
				fail("expected macro if without else to preserve missing else marker");
		}
		switch (macroIfVars[1]) {
			case SVar("withElse", _, EMacroExpr(ECall(EIdent("__hxhx_macro_if"), [EInt(1), EInt(2), EInt(3)]), _), _):
			case SVar(_, _, EUnsupported(raw), _):
				fail("macro if with else parsed as unsupported: " + raw);
			case _:
				fail("expected macro if with else to preserve else expression");
		}

		final macroClassVars = HxParser.parseFunctionBodyText('var td = macro class Generated extends Base { static function build():Int return 1; }; td.fields.push(field); (macro class Helper { public function run() {} }).fields;');
		assertTrue(macroClassVars.length == 3, "expected macro class quote body to parse");
		switch (macroClassVars[0]) {
			case SVar("td", _, EAnon(names, values), _):
				assertTrue(names.indexOf("name") >= 0, "expected macro class placeholder to expose a name field");
				assertTrue(names.indexOf("fields") >= 0, "expected macro class placeholder to expose fields");
				switch (values[names.indexOf("name")]) {
					case EString("Generated"):
					case _:
						fail("expected macro class placeholder name to match the quoted class");
				}
			case SVar(_, _, EUnsupported(raw), _):
				fail("macro class quote parsed as unsupported: " + raw);
			case _:
				fail("expected macro class quote to parse as a type-definition placeholder");
		}
		switch (macroClassVars[1]) {
			case SExpr(ECall(EField(EField(EIdent("td"), "fields"), "push"), [EIdent("field")]), _):
			case SExpr(EUnsupported(raw), _):
				fail("macro class follow-up field push parsed as unsupported: " + raw);
			case _:
				fail("expected macro class follow-up field push to parse");
		}
		switch (macroClassVars[2]) {
			case SExpr(EField(EAnon(names, _), "fields"), _):
				assertTrue(names.indexOf("fields") >= 0, "expected parenthesized macro class quote to expose fields");
			case SExpr(EUnsupported(raw), _):
				fail("parenthesized macro class field access parsed as unsupported: " + raw);
			case _:
				fail("expected parenthesized macro class field access to parse");
		}

		final macroTypePatternStmts = HxParser.parseFunctionBodyText('var info = switch (ct) { case macro:Sample<Int>: { name: "sample" }; case _: throw false; };');
		assertTrue(macroTypePatternStmts.length == 1, "expected macro type pattern switch var to parse");
		switch (macroTypePatternStmts[0]) {
			case SVar("info", _, ESwitch(_, [PEnumValue("macro:Sample<Int>"), PWildcard], [EAnon(names, _), ECall(EIdent("__hxhx_throw"), [EBool(false)])]), _):
				assertTrue(names.indexOf("name") >= 0, "expected macro type pattern switch body to parse anon object");
			case SVar(_, _, EUnsupported(raw), _):
				fail("macro type pattern switch parsed as unsupported: " + raw);
			case _:
				fail("expected macro type pattern switch expression");
		}

		final macroIdentSpliceStmts = HxParser.parseFunctionBodyText('tests.push(macro deq(0, $$i{name}(0)));');
		assertTrue(macroIdentSpliceStmts.length == 1, "expected macro identifier splice push to parse");
		switch (macroIdentSpliceStmts[0]) {
			case SExpr(ECall(EField(EIdent("tests"), "push"), [
				EMacroExpr(ECall(EIdent("deq"), [
					EInt(0),
					ECall(ECall(EIdent("__hxhx_macro_ident_splice"), [EIdent("name")]), [EInt(0)])
				]), _)
			]), _):
			case SExpr(EUnsupported(raw), _):
				fail("macro identifier splice push parsed as unsupported: " + raw);
			case _:
				fail("expected macro identifier splice push expression");
		}

		final exprMetaCalls = HxParser.parseFunctionBodyText('eq(readMeta(@tag ("value")).name, "tag"); eq(readMeta(@tag("arg") "value").args.length, 1);');
		assertTrue(exprMetaCalls.length == 2, "expected expression metadata calls to parse");
		switch (exprMetaCalls[0]) {
			case SExpr(ECall(EIdent("eq"), [
				EField(ECall(EIdent("readMeta"), [
					ECall(EIdent("__hxhx_expr_meta"), [EString("tag"), EString(""), EString("value")])
				]), "name"),
				EString("tag")
			]), _):
			case SExpr(EUnsupported(raw), _):
				fail("spaced expression metadata call parsed as unsupported: " + raw);
			case _:
				fail("expected spaced expression metadata to preserve metadata marker");
		}
		switch (exprMetaCalls[1]) {
			case SExpr(ECall(EIdent("eq"), [
				EField(EField(ECall(EIdent("readMeta"), [
					ECall(EIdent("__hxhx_expr_meta"), [EString("tag"), EString('"arg"'), EString("value")])
				]), "args"), "length"),
				EInt(1)
			]), _):
			case SExpr(EUnsupported(raw), _):
				fail("attached expression metadata args call parsed as unsupported: " + raw);
			case _:
				fail("expected attached expression metadata args to preserve metadata marker");
		}

		final macroTypeCalls = HxParser.parseFunctionBodyText('eq(p.printComplexType(macro :X -> Y), "X -> Y"); eq(p.printComplexType(TFunction([TOptional(TNamed("a", macro :Int))], macro :Int)), "(?a:Int) -> Int"); eq(p.printField({ name: "x", pos: null, kind: FVar(macro :Any, null), access: [AFinal, AStatic] }), "static final x : Any");');
		assertTrue(macroTypeCalls.length == 3, "expected macro complex type printer calls to parse");
		for (stmt in macroTypeCalls) {
			switch (stmt) {
				case SExpr(EUnsupported(raw), _):
					fail("macro complex type call parsed as unsupported: " + raw);
				case _:
			}
		}
	}
}
