import backend.js.JsExprEmitter;
import backend.js.JsFunctionScope;

class M14JsExprEmitterRangeExprIntegrationTest {
	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack == null || haystack.indexOf(needle) < 0) {
			throw label + ": expected substring '" + needle + "' in '" + haystack + "'";
		}
	}

	static function assertNotContains(haystack:String, needle:String, label:String):Void {
		if (haystack != null && haystack.indexOf(needle) >= 0) {
			throw label + ": unexpected substring '" + needle + "' in '" + haystack + "'";
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

		final parenthesizedAssignJs = JsExprEmitter.emit(HxParser.parseExprText("(c = file.data.get(p++)) != 10"), exprScope);
		assertContains(parenthesizedAssignJs, "(c = file.data.get(", "parenthesized assignment should stay grouped for JS operator precedence");
		assertNotContains(parenthesizedAssignJs, "__hxhx_parenthesized", "parser-only parenthesized marker should not leak to JS runtime output");

		final nullEqJs = JsExprEmitter.emit(HxParser.parseExprText("pattern == null && globalPattern == null"), exprScope);
		assertContains(nullEqJs, "(pattern == null)", "null equality should treat omitted optional args as null-like");
		assertContains(nullEqJs, "(globalPattern == null)", "null equality should use loose null checks for both sides");

		final valueEqJs = JsExprEmitter.emit(HxParser.parseExprText("left == right"), exprScope);
		assertContains(valueEqJs, "(left === right)", "non-null equality should keep strict JS equality");

		final typeTestJs = JsExprEmitter.emit(HxParser.parseExprText("1f64 is Float"), exprScope);
		assertContains(typeTestJs, "function(__hx_is)", "type-test should evaluate the value once");
		assertContains(typeTestJs, 'typeof __hx_is === "number"', "Float type-test should lower to a JS number check");
	}
}
