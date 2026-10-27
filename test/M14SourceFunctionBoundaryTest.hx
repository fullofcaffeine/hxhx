import sys.io.File;

/** Keep a function's body distinct from later source entries, including calls that start with parentheses. */
class M14SourceFunctionBoundaryTest {
	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function expression(statement:HxStmt):HxExpr {
		return switch statement {
			case SExpr(value, _): value;
			case _: throw "expected an authored expression statement";
		};
	}

	/** The old parser put the following expression inside an ECall around the function's brace group. */
	static function checkDeclaration(prefix:String, suffix:String, generic:Bool = false, isInline:Bool = false):Void {
		final text = prefix + 'function pick' + (generic ? '<T>(value:T):T{return value;}' : '():Bool{return true;}') + suffix;
		final statements = HxParser.parseFunctionBodyText(text);
		require(statements.length == 2, "function swallowed the following source entry: " + text);
		switch expression(statements[0]) {
			case ESourceFunction(facts, ESourceGroup([EReturn(value)], _), defaults, _):
				require(facts.getPlacement() == Declaration && defaults.length == 0, "named declaration changed placement or defaults");
				switch facts.getKind() {
					case Named("pick", inlineFlag): require(inlineFlag == isInline, "inline fact changed");
					case _: throw "named function became an anonymous value";
				}
				require(facts.getGenerics().getParameters().length == (generic ? 1 : 0), "declaration lost its type parameter");
				switch value {
					case EIdent("value") if (generic):
					case EBool(true) if (!generic):
					case _: throw "function return no longer belongs to its original brace group";
				}
			case _:
				throw "following postfix operation changed the function body";
		}
		switch expression(statements[1]) {
			case EParenthesized(ECall(EIdent("pick"), arguments), _):
				require(arguments.length == (generic ? 1 : 0), "following call arguments changed");
			case EArrayDecl([ECall(EIdent("pick"), [])]) if (suffix.charAt(0) == "["):
			case _:
				throw "following call or array no longer has its own source entry";
		}
	}

	static function checkGroup():Void {
		final source = '{function pick():Bool{return true;}(pick()) ? 7 : 9;}';
		switch HxParser.parseCompleteExprText(source) {
			case ESourceGroup([
				ESourceFunction(facts, ESourceGroup([EReturn(EBool(true))], bodyPosition), [], functionPosition),
				ETernary(EParenthesized(ECall(EIdent("pick"), []), callPosition), EInt(7), EInt(9))
			], _):
				require(facts.getPlacement() == Declaration && facts.getDeclaredName() == "pick", "group lost declaration placement");
				require(functionPosition.getIndex() == source.indexOf("function")
					&& bodyPosition.getIndex() == source.indexOf("{return")
					&& callPosition.getIndex() == source.indexOf("(pick"),
					"source occurrences moved across the function boundary");
			case _:
				throw "ternary was absorbed into the preceding function body";
		}
	}

	/** A completed function value stops outer postfix parsing; its non-braced return still parses a full value. */
	static function checkValues():Void {
		for (name in ["", " named"])
			switch HxParser.parseCompleteExprText('function' + name + '():Int{return 7;}') {
				case ESourceFunction(facts, ESourceGroup([EReturn(EInt(7))], _), [], _):
					require(facts.getPlacement() == Value, "function value gained declaration placement");
				case _:
					throw "braced function value changed";
			}
		for (source in [
			'function():Int{return 7;}()',
			'function named():Int{return 7;}()',
			'function():Int{return 7;}.bind()'
		]) {
			var rejected = false;
			try {
				HxParser.parseCompleteExprText(source);
			} catch (_:HxParseError) {
				rejected = true;
			}
			require(rejected, "raw function value gained an unauthored postfix operation");
		}
		switch HxParser.parseCompleteExprText('(function():Int{return 7;})()') {
			case ECall(EParenthesized(ESourceFunction(facts, ESourceGroup([EReturn(EInt(7))], _), [], _), _), []):
				require(facts.getPlacement() == Value, "parenthesized function call changed placement");
			case _:
				throw "parenthesized function value lost its immediate call";
		}
		switch HxParser.parseCompleteExprText('({function():Int{return 7;};})()') {
			case ECall(EParenthesized(ESourceGroup([ESourceFunction(_, ESourceGroup([EReturn(EInt(7))], _), [], _)], _), _), []):
			case _:
				throw "parenthesized brace-group function value lost its immediate call";
		}
		for (name in ["", " named"])
			switch HxParser.parseCompleteExprText('function' + name + '():Int return other()') {
				case ESourceFunction(_, EReturn(ECall(EIdent("other"), [])), [], _):
				case _:
					throw "function body call was mistaken for an outer postfix call";
			}
		switch HxParser.parseCompleteExprText('function():Int return values()[0]()') {
			case ESourceFunction(_, EReturn(ECall(EArrayAccess(ECall(EIdent("values"), []), EInt(0)), [])), [], _):
			case _:
				throw "returned indexing/call lost its original operand ownership";
		}
		switch HxParser.parseCompleteExprText('function() return function():Int return other()') {
			case ESourceFunction(_, EReturn(ESourceFunction(_, EReturn(ECall(EIdent("other"), [])), [], _)), [], _):
			case _:
				throw "returned function value lost its internal call";
		}
	}

	/** Keep the separate returned-block terminator rule: no new separator is needed before a following declaration. */
	static function checkReturnedBlockNeighbor():Void {
		switch HxParser.parseCompleteExprText('{function pick():Int return {7;} var next=pick();next;}') {
			case ESourceGroup([
				ESourceFunction(_, EReturn(ESourceGroup([EInt(7)], _)), [], _),
				EVars(declarations),
				EIdent("next")
			], _):
				require(declarations.length == 1
					&& HxExprVarDecl.getName(declarations[0]) == "next", "returned block consumed the next declaration");
			case _:
				throw "returned-block declaration termination changed";
		}
	}

	/** Observe separate declaration entries, helper returns and function-value calls in generated JavaScript. */
	static function checkRuntime():Void {
		final root = JsRuntimeFixture.reserveOutput();
		final path = root + "/Main.hx";
		final source = 'class Main{static var events:String="";'
			+ 'static function choose():Int{return {'
			+ 'function pick():Bool{events+="p";return true;}(pick()) ? 7 : 9;};}'
			+ 'static function other():Int{events+="o";return 5;}'
			+ 'static function values():Array<()->Int>{return [other];}'
			+ 'static function main():Void{trace(choose());'
			+ 'function direct():Int{events+="d";return 3;}[direct()];'
			+ 'trace((function():Int{return 11;})());'
			+ 'trace(({function():Int{return 13;};})());'
			+ 'var indexed=function():Int return values()[0]();trace(indexed());'
			+ 'var nested=function() return function():Int return other();trace(nested()());'
			+ 'var neighbor={function pick():Int return {17;} var next=pick();next;};trace(neighbor);trace(events);}}';
		final expected = "7\n11\n13\n5\n5\n17\npdoo\n";
		File.saveContent(path, source);
		command("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "--js", root + "/upstream.js"], "");
		final upstreamExpected = expected.split("\n")
			.filter(line -> line != "")
			.map(line -> path + ":1: " + line + "\n")
			.join("");
		command("node", [root + "/upstream.js"], upstreamExpected);
		final typed = M14Stage3RuntimeFixture.typeMain({source: source, path: path, root: root});
		JsRuntimeFixture.assertRuntime(typed, "Main", expected);
		Sys.println("SOURCE_FUNCTION_BOUNDARY:PASS generated_runtime");
	}

	static function command(executable:String, arguments:Array<String>, expected:String):Void {
		final child = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", executable].concat(arguments));
		final stdout = child.stdout.readAll().toString();
		final stderr = child.stderr.readAll().toString();
		final code = child.exitCode();
		child.close();
		require(code == 0 && stdout == expected && stderr == "", "function boundary observer failed: " + stdout + stderr);
	}

	static function main():Void {
		checkDeclaration("", "(pick());");
		checkDeclaration("", "[pick()];");
		checkDeclaration("inline ", "(pick());", false, true);
		checkDeclaration("@:keep ", "(pick());");
		checkDeclaration("", "(pick(7));", true);
		checkGroup();
		checkValues();
		checkReturnedBlockNeighbor();
		Sys.println("SOURCE_FUNCTION_BOUNDARY:PASS source");
		checkRuntime();
	}
}
