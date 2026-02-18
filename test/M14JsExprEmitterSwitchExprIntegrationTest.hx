import backend.js.JsExprEmitter;
import backend.js.JsFunctionScope;

class M14JsExprEmitterSwitchExprIntegrationTest {
	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack == null || haystack.indexOf(needle) < 0) {
			throw label + ": expected substring '" + needle + "' in '" + haystack + "'";
		}
	}

	static function main() {
		final scope = new JsFunctionScope(new haxe.ds.StringMap<String>());
		final exprScope = scope.exprScope();

		final simple = HxParser.parseExprText('switch (mode) { case "a": 1; case "b" | "c": 2; default: 9; }');
		final simpleJs = JsExprEmitter.emit(simple, exprScope);
		assertContains(simpleJs, "(function () {", "switch expression should lower via IIFE");
		assertContains(simpleJs, "if (__sw === \"a\")", "first case should lower to condition");
		assertContains(simpleJs, "else if ((__sw === \"b\") || (__sw === \"c\"))", "OR pattern should lower to disjunction");
		assertContains(simpleJs, "return 9;", "default branch should return fallback value");

		final bind = HxParser.parseExprText("switch (mode) { case value: value + 1; }");
		final bindJs = JsExprEmitter.emit(bind, exprScope);
		assertContains(bindJs, "var __sw_bind_value = __sw;", "bind pattern should define branch-local alias");
		assertContains(bindJs, "return (__sw_bind_value + 1);", "bind alias should be used in emitted expression");
	}
}
