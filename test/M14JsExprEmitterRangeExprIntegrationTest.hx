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

		final coalesceJs = JsExprEmitter.emit(HxParser.parseExprText("left() ?? right()"), exprScope);
		assertContains(coalesceJs, "function(__hx_coalesce)", "null coalescing should capture left once");
		assertContains(coalesceJs, "__hx_coalesce != null", "null coalescing should check the captured left value");
		assertContains(coalesceJs, ": right();", "null coalescing fallback should emit right expression lazily");
		assertContains(coalesceJs, ")(left())", "null coalescing should evaluate the left expression as the IIFE argument");

		final coalesceAssignJs = JsExprEmitter.emit(HxParser.parseExprText("target ??= fallback"), exprScope);
		assertContains(coalesceAssignJs, "(target ??= fallback)", "null coalescing assignment should parse and emit as an assignment");
	}
}
