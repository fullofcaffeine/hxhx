import backend.js.JsExprEmitter;
import backend.js.JsFunctionScope;

class M14JsExprEmitterRangeExprIntegrationTest {
	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack == null || haystack.indexOf(needle) < 0) {
			throw label + ": expected substring '" + needle + "' in '" + haystack + "'";
		}
	}

	static function main() {
		final scope = new JsFunctionScope(new haxe.ds.StringMap<String>());
		final exprScope = scope.exprScope();

		final expr = HxParser.parseExprText("1...5");
		final js = JsExprEmitter.emit(expr, exprScope);
		assertContains(js, "(function () {", "range expression lowers to IIFE");
		assertContains(js, "var __range_start = 1;", "range expression captures start once");
		assertContains(js, "var __range_end = 5;", "range expression captures end once");
		assertContains(js, "for (var __range_i = __range_start; __range_i < __range_end; __range_i++) {", "range expression lowers to deterministic for loop");
		assertContains(js, "__range_out.push(__range_i);", "range expression appends current loop value");
	}
}
