import backend.js.JsExprEmitter;
import backend.js.JsFunctionScope;

/** Keep primitive emission checks and reject source constructs that require typed lowering.
	Positive function and Map behavior lives in the accompanying runtime fixtures. */
class M14JsExprEmitterFunctionLiteralIntegrationTest {
	static function assertRawRejected(expression:HxExpr, scope:backend.js.JsEmitScope, expected:String, label:String):Void {
		try {
			JsExprEmitter.emit(expression, scope);
		} catch (message:String) {
			assertContains(message, expected, label);
			return;
		}
		throw label + ": raw source unexpectedly bypassed typed lowering";
	}

	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack == null || haystack.indexOf(needle) < 0)
			throw label + ": expected substring '" + needle + "' in '" + haystack + "'";
	}

	static function assertNotContains(haystack:String, needle:String, label:String):Void {
		if (haystack != null && haystack.indexOf(needle) >= 0)
			throw label + ": unexpected substring '" + needle + "' in '" + haystack + "'";
	}

	static function assertEquals(actual:String, expected:String, label:String):Void {
		if (actual != expected)
			throw label + ": expected '" + expected + "', got '" + actual + "'";
	}

	static function main() {
		final scope = new JsFunctionScope(new haxe.ds.StringMap<String>());
		final exprScope = scope.exprScope();

		final unary = HxParser.parseExprText("function(x) return x + 1");
		assertRawRejected(unary, exprScope, "source control must be lowered before JavaScript emission", "unary");

		final typedArg = HxParser.parseExprText("function(value:Int) return value");
		assertRawRejected(typedArg, exprScope, "source control must be lowered before JavaScript emission", "typedArg");

		final reservedArg = HxParser.parseExprText("function(arguments) return arguments");
		assertRawRejected(reservedArg, exprScope, "source control must be lowered before JavaScript emission", "reservedArg");

		final evalArg = HxParser.parseExprText("function(eval) return eval");
		assertRawRejected(evalArg, exprScope, "source control must be lowered before JavaScript emission", "evalArg");

		final noArgs = HxParser.parseExprText("function() return 7");
		assertRawRejected(noArgs, exprScope, "source control must be lowered before JavaScript emission", "noArgs");

		final assignedArrow = HxParser.parseExprText("maybe = () -> Math.random() > 0.5");
		assertRawRejected(assignedArrow, exprScope, "source control must be lowered before JavaScript emission", "assignedArrow");

		final postfixArgJs = JsExprEmitter.emit(HxParser.parseExprText("file.data.get(p++)"), exprScope);
		assertContains(postfixArgJs, "file.data.get((function(){ var __hx_old = p;", "postfix increment should pass the old local value to calls");
		assertContains(postfixArgJs, "p = (__hx_old + 1)", "postfix increment should update the local after reading it");
		assertContains(postfixArgJs, "return __hx_old;", "postfix increment should return the captured old value");
		assertNotContains(postfixArgJs, "p += 1", "postfix increment should not collapse to pre-increment compound assignment");

		final postfixArrayIndexJs = JsExprEmitter.emit(HxParser.parseExprText("values[p++]"), exprScope);
		assertContains(postfixArrayIndexJs, "var __hx_old = p;", "postfix array index should capture the old index value");
		assertContains(postfixArrayIndexJs, "return __hx_old;", "postfix array index should read with the old index before incrementing");

		final postfixArraySlotJs = JsExprEmitter.emit(HxParser.parseExprText("values[p]++"), exprScope);
		assertContains(postfixArraySlotJs, "__hx_op_read", "postfix array slot increment should respect abstract read slots");
		assertContains(postfixArraySlotJs, "__hx_op_write", "postfix array slot increment should respect abstract write slots");
		assertContains(postfixArraySlotJs, "return __hx_old;", "postfix array slot increment should return the previous slot value");

		final postfixThisJs = JsExprEmitter.emit(HxParser.parseExprText("this++"), exprScope);
		assertContains(postfixThisJs, "__hx_self.__hx_value", "postfix this increment should update the abstract backing value");
		assertContains(postfixThisJs, "return __hx_old;", "postfix this increment should preserve expression-position old-value semantics");

		final stringCodeJs = JsExprEmitter.emit(HxParser.parseExprText('"\\n".code'), exprScope);
		assertContains(stringCodeJs, ".charCodeAt(0)", "single-character string .code should lower to JS charCodeAt");
		assertNotContains(stringCodeJs, ".code", "single-character string .code should not emit an undefined JS property read");

		final optionalArrow = HxParser.parseExprText("f = (?a:Int=1, b:String) -> a + b.length");
		assertRawRejected(optionalArrow, exprScope, "source control must be lowered before JavaScript emission", "optionalArrow");

		final ascribedArrow = HxParser.parseExprText("f0 = (() -> 1:()->Int)");
		assertRawRejected(ascribedArrow, exprScope, "source control must be lowered before JavaScript emission", "ascribedArrow");

		final mapArrow = HxParser.parseExprText("map = [1 => a -> a + a, 2 => b -> b + b]");
		assertRawRejected(mapArrow, exprScope, "Map syntax must select its typed provider before JavaScript emission", "mapArrow");

		final unicodeBlock = HxParser.parseExprText('{ var valid = valid.copy(); if (Sys.systemName() == "Windows") valid = valid.filter(f -> !f.match(Only([0x0001]))); valid = valid.filter(f -> !f.match(Only([0xD7FF])) && !f.match(Only([0x1FFFF]))); valid; }');
		assertRawRejected(unicodeBlock, exprScope, "source control must be lowered before JavaScript emission", "unicodeBlock");

		final mapComprehension = HxParser.parseExprText('map = [for (x in ["a", "b"]) x => x.toUpperCase()]');
		assertRawRejected(mapComprehension, exprScope, "source control must be lowered before JavaScript emission", "mapComprehension");

		final forExprFunction = HxParser.parseExprText("function() for (x in xml) null");
		assertRawRejected(forExprFunction, exprScope, "source control must be lowered before JavaScript emission", "forExprFunction");

		final switchArrow = HxParser.parseExprText("f7 = switch maybe() { case true: f -> f; case false: f -> g -> f(g); }");
		assertRawRejected(switchArrow, exprScope, "source control must be lowered before JavaScript emission", "switchArrow");

		final blockBody = HxParser.parseExprText("function(x) { var y = x + 1; return y; }");
		assertRawRejected(blockBody, exprScope, "source control must be lowered before JavaScript emission", "blockBody");

		final jsLibCtor = HxParser.parseExprText("new js.lib.DataView(new js.lib.ArrayBuffer(8))");
		final jsLibCtorJs = JsExprEmitter.emit(jsLibCtor, exprScope);
		assertContains(jsLibCtorJs, "new DataView(", "js.lib.DataView constructor lowers to native DataView");
		assertContains(jsLibCtorJs, "new ArrayBuffer(8)", "nested js.lib.ArrayBuffer constructor lowers to native ArrayBuffer");

		final spreadCallJs = JsExprEmitter.emit(HxParser.parseExprText("rest(...r)"), exprScope);
		assertContains(spreadCallJs, "rest(...r)", "call argument spread should lower to JS spread syntax");

		final spreadCtorJs = JsExprEmitter.emit(HxParser.parseExprText("new Array(...values)"), exprScope);
		assertContains(spreadCtorJs, "new Array(...values)", "constructor argument spread should lower to JS spread syntax");

		final whileBody = HxParser.parseExprText("function(xs) { var i = 0; while (i < xs.length) { i += 1; } return i; }");
		assertRawRejected(whileBody, exprScope, "source control must be lowered before JavaScript emission", "whileBody");

		final forInBody = HxParser.parseExprText("function(xs) { var out = []; for (x in xs) { out.push(x); } return out; }");
		assertRawRejected(forInBody, exprScope, "source control must be lowered before JavaScript emission", "forInBody");

		final switchBody = HxParser.parseExprText('function(kind) { var out = ""; switch (kind) { case "a": out = "A"; default: out = "X"; } return out; }');
		assertRawRejected(switchBody, exprScope, "source control must be lowered before JavaScript emission", "switchBody");

		assertRawRejected(HxParser.parseExprText('[1 => 2]'), exprScope, "Map syntax must select its typed provider before JavaScript emission",
			"raw Map literal");
		assertEquals(JsExprEmitter.emit(HxParser.parseExprText("__hxhx_map_comprehension(xs, callback)"), exprScope),
			"__hxhx_map_comprehension(xs, callback)", "old helper spelling is an ordinary user call");

		final castPostfixJs = JsExprEmitter.emit(HxParser.parseExprText("cast(c, Cov1).covariant()"), exprScope);
		assertContains(castPostfixJs, "c.covariant()", "cast expression should accept field/call postfix suffixes");

		final inlineExprJs = JsExprEmitter.emit(HxParser.parseExprText("inline helper(value, max - 1)"), exprScope);
		assertContains(inlineExprJs, "helper(value, (max - 1))", "expression-position inline should lower to the wrapped call");

		final intReceiverCallJs = JsExprEmitter.emit(ECall(EField(EInt(32), "ofInt"), []), exprScope);
		assertEquals(intReceiverCallJs, "(32).ofInt()", "integer literal receiver calls should be valid JavaScript");

		final floatReceiverCallJs = JsExprEmitter.emit(ECall(EField(EFloat(1.5), "toFixed"), [EInt(1)]), exprScope);
		assertEquals(floatReceiverCallJs, "(1.5).toFixed(1)", "float literal receiver calls should be valid JavaScript");
	}
}
