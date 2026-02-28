import backend.js.JsExprEmitter;
import backend.js.JsFunctionScope;

class M14JsExprEmitterFunctionLiteralIntegrationTest {
	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack == null || haystack.indexOf(needle) < 0)
			throw label + ": expected substring '" + needle + "' in '" + haystack + "'";
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

		final noArgs = HxParser.parseExprText("function() return 7");
		final noArgsJs = JsExprEmitter.emit(noArgs, exprScope);
		assertContains(noArgsJs, "function()", "no-arg function literal keeps empty parameter list");
		assertContains(noArgsJs, "return 7", "no-arg function literal body preserved");

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
	}
}
