import backend.js.JsExprEmitter;
import backend.js.JsFunctionScope;

class M14JsExprEmitterArrayComprehensionIntegrationTest {
	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack == null || haystack.indexOf(needle) < 0) {
			throw label + ": expected substring '" + needle + "' in '" + haystack + "'";
		}
	}

	static function main() {
		final scope = new JsFunctionScope(new haxe.ds.StringMap<String>());
		final exprScope = scope.exprScope();

		final rangeExpr = HxParser.parseExprText("[for (i in 0...3) i * 2]");
		final rangeJs = JsExprEmitter.emit(rangeExpr, exprScope);
		assertContains(rangeJs, "(function () {", "range comprehension lowers to IIFE");
		assertContains(rangeJs, "var __arr_comp_start = 0;", "range comprehension captures start once");
		assertContains(rangeJs, "var __arr_comp_end = 3;", "range comprehension captures end once");
		assertContains(
			rangeJs,
			"for (var __arr_comp_i = __arr_comp_start; __arr_comp_i < __arr_comp_end; __arr_comp_i++) {",
			"range comprehension lowers to for loop"
		);
		assertContains(rangeJs, "__arr_comp_out.push((__arr_comp_i * 2));", "range comprehension uses bound iterator variable");

		final iterExpr = HxParser.parseExprText("[for (value in values) value + 1]");
		final iterJs = JsExprEmitter.emit(iterExpr, exprScope);
		assertContains(iterJs, "var __arr_comp_iter = values;", "array comprehension captures iterable once");
		assertContains(
			iterJs,
			"var __arr_comp_value = __arr_comp_iter[__arr_comp_i];",
			"array comprehension binds loop value each iteration"
		);
		assertContains(iterJs, "__arr_comp_out.push((__arr_comp_value + 1));", "array comprehension yield uses bound value");
	}
}
