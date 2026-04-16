import backend.js.JsExprEmitter;
import backend.js.JsFunctionScope;

class M14JsExprEmitterFunctionLiteralIntegrationTest {
	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack == null || haystack.indexOf(needle) < 0)
			throw label + ": expected substring '" + needle + "' in '" + haystack + "'";
	}

	static function assertEquals(actual:String, expected:String, label:String):Void {
		if (actual != expected)
			throw label + ": expected '" + expected + "', got '" + actual + "'";
	}

	static function main() {
		final scope = new JsFunctionScope(new haxe.ds.StringMap<String>());
		final exprScope = scope.exprScope();

		final unary = HxParser.parseExprText("function(x) return x + 1");
		final unaryJs = JsExprEmitter.emit(unary, exprScope);
		assertContains(unaryJs, "function(", "function literal lowers to JS function expression");
		assertContains(unaryJs, "return (", "function literal emits return statement");
		assertContains(unaryJs, "+ 1", "function literal preserves expression body");

		final typedArg = HxParser.parseExprText("function(value:Int) return value");
		final typedArgJs = JsExprEmitter.emit(typedArg, exprScope);
		assertContains(typedArgJs, "function(", "typed-arg function literal parses");
		assertContains(typedArgJs, "return ", "typed-arg function literal emits return");

		final reservedArg = HxParser.parseExprText("function(arguments) return arguments");
		final reservedArgJs = JsExprEmitter.emit(reservedArg, exprScope);
		assertContains(reservedArgJs, "function(arguments_)", "strict-mode reserved lambda arg should be renamed");
		assertContains(reservedArgJs, "return arguments_", "strict-mode reserved lambda body reference should use the renamed arg");

		final evalArg = HxParser.parseExprText("function(eval) return eval");
		final evalArgJs = JsExprEmitter.emit(evalArg, exprScope);
		assertContains(evalArgJs, "function(eval_)", "strict-mode eval lambda arg should be renamed");
		assertContains(evalArgJs, "return eval_", "strict-mode eval lambda body reference should use the renamed arg");

		final noArgs = HxParser.parseExprText("function() return 7");
		final noArgsJs = JsExprEmitter.emit(noArgs, exprScope);
		assertContains(noArgsJs, "function()", "no-arg function literal keeps empty parameter list");
		assertContains(noArgsJs, "return 7", "no-arg function literal body preserved");

		final assignedArrow = HxParser.parseExprText("maybe = () -> Math.random() > 0.5");
		final assignedArrowJs = JsExprEmitter.emit(assignedArrow, exprScope);
		assertContains(assignedArrowJs, "maybe = function()", "assignment RHS arrow literal parses as a lambda");
		assertContains(assignedArrowJs, "Math.random() > 0.5", "assignment RHS arrow keeps comparison body");

		final optionalArrow = HxParser.parseExprText("f = (?a:Int=1, b:String) -> a + b.length");
		final optionalArrowJs = JsExprEmitter.emit(optionalArrow, exprScope);
		assertContains(optionalArrowJs, "f = function(a, b)", "optional/typed/default arrow args keep runtime arg names");
		assertContains(optionalArrowJs, "a + b.length", "optional/typed/default arrow body is preserved");

		final ascribedArrow = HxParser.parseExprText("f0 = (() -> 1:()->Int)");
		final ascribedArrowJs = JsExprEmitter.emit(ascribedArrow, exprScope);
		assertContains(ascribedArrowJs, "f0 = function()", "ascribed arrow expression parses as a lambda");
		assertContains(ascribedArrowJs, "return 1", "ascribed arrow expression keeps body and consumes type hint");

		final mapArrow = HxParser.parseExprText("map = [1 => a -> a + a, 2 => b -> b + b]");
		final mapArrowJs = JsExprEmitter.emit(mapArrow, exprScope);
		assertContains(mapArrowJs, "map = {\"1\": function(a)", "map-literal arrow value parses without a stray fat-arrow token");
		assertContains(mapArrowJs, "\"2\": function(b)", "map-literal keeps each arrow value");

		final mapComprehension = HxParser.parseExprText('map = [for (x in ["a", "b"]) x => x.toUpperCase()]');
		final mapComprehensionJs = JsExprEmitter.emit(mapComprehension, exprScope);
		assertContains(mapComprehensionJs, "__hxhx_map_out", "map comprehension should allocate an object result");
		assertContains(mapComprehensionJs, "__hxhx_pair[0]", "map comprehension should use the yielded key");
		assertContains(mapComprehensionJs, "x.toUpperCase()", "map comprehension should emit the yielded value expression");

		final forExprFunction = HxParser.parseExprText("function() for (x in xml) null");
		final forExprFunctionJs = JsExprEmitter.emit(forExprFunction, exprScope);
		assertContains(forExprFunctionJs, "function()", "expression-position for-in should stay inside the callback");
		assertContains(forExprFunctionJs, "for (var __i = 0; __i < __iter.length; __i++)", "expression-position for-in should emit an iteration IIFE");
		assertContains(forExprFunctionJs, "return null", "expression-position for-in should preserve the null continuation");

		final switchArrow = HxParser.parseExprText("f7 = switch maybe() { case true: f -> f; case false: f -> g -> f(g); }");
		final switchArrowJs = JsExprEmitter.emit(switchArrow, exprScope);
		assertContains(switchArrowJs, "f7 = (function () {", "assignment RHS switch expression parses structurally");
		assertContains(switchArrowJs, "return function(f)", "switch cases can return arrow functions");
		assertContains(switchArrowJs, "return function(g)", "nested arrow function inside switch case parses");

		final blockBody = HxParser.parseExprText("function(x) { var y = x + 1; return y; }");
		final blockBodyJs = JsExprEmitter.emit(blockBody, exprScope);
		assertContains(blockBodyJs, "function(", "block-body function literal parses");
		assertContains(blockBodyJs, "return ", "block-body function literal emits return");
		assertContains(blockBodyJs, "function(y)", "block-body function literal lowers var binding");
		assertContains(blockBodyJs, "(x + 1)", "block-body function literal keeps initializer expression");

		final jsLibCtor = HxParser.parseExprText("new js.lib.DataView(new js.lib.ArrayBuffer(8))");
		final jsLibCtorJs = JsExprEmitter.emit(jsLibCtor, exprScope);
		assertContains(jsLibCtorJs, "new DataView(", "js.lib.DataView constructor lowers to native DataView");
		assertContains(jsLibCtorJs, "new ArrayBuffer(8)", "nested js.lib.ArrayBuffer constructor lowers to native ArrayBuffer");

		final spreadCallJs = JsExprEmitter.emit(HxParser.parseExprText("rest(...r)"), exprScope);
		assertContains(spreadCallJs, "rest(...r)", "call argument spread should lower to JS spread syntax");

		final spreadCtorJs = JsExprEmitter.emit(HxParser.parseExprText("new Array(...values)"), exprScope);
		assertContains(spreadCtorJs, "new Array(...values)", "constructor argument spread should lower to JS spread syntax");

		final whileBody = HxParser.parseExprText("function(xs) { var i = 0; while (i < xs.length) { i += 1; } return i; }");
		final whileBodyJs = JsExprEmitter.emit(whileBody, exprScope);
		assertContains(whileBodyJs, "while (__cond())", "block-body function while loop should lower to expression helper");
		assertContains(whileBodyJs, "i += 1", "block-body function while helper should preserve body side effect");
		assertContains(whileBodyJs, "return i;", "block-body function while helper should run the continuation after the loop");

		final forInBody = HxParser.parseExprText("function(xs) { var out = []; for (x in xs) { out.push(x); } return out; }");
		final forInBodyJs = JsExprEmitter.emit(forInBody, exprScope);
		assertContains(forInBodyJs, "for (var __i = 0; __i < __iter.length; __i++)", "block-body function for-in should lower to expression helper");
		assertContains(forInBodyJs, "__body(__iter[__i])", "block-body function for-in helper should pass each value");
		assertContains(forInBodyJs, "return out;", "block-body function for-in helper should run the continuation after the loop");

		final switchBody = HxParser.parseExprText('function(kind) { var out = ""; switch (kind) { case "a": out = "A"; default: out = "X"; } return out; }');
		final switchBodyJs = JsExprEmitter.emit(switchBody, exprScope);
		assertContains(switchBodyJs, "var __sw = kind", "block-body function switch should lower to expression switch");
		assertContains(switchBodyJs, 'if (__sw === "a")', "block-body function switch should preserve string case");
		assertContains(switchBodyJs, 'out = "A"', "block-body function switch should preserve case body side effect");
		assertContains(switchBodyJs, "return out;", "block-body function switch should run the continuation after the switch");

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
