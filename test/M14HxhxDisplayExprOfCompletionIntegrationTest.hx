class M14HxhxDisplayExprOfCompletionIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition) throw message;
	}

	static function assertContains(haystack:String, needle:String, message:String):Void {
		assertTrue(haystack.indexOf(needle) >= 0, message + "\nactual=" + haystack);
	}

	static function main():Void {
		final exprOfMarker = "__CURSOR_EXPROF__";
		final exprMarker = "__CURSOR_EXPR__";
		var source = [
			"typedef Patch = {",
			"  count:Int,",
			"  label:String,",
			"  ?enabled:Bool",
			"};",
			"",
			"class MacroApi {",
			"  macro static function mergeExprOf(p:haxe.macro.Expr.ExprOf<Patch>):haxe.macro.Expr {",
			"    return macro null;",
			"  }",
			"",
			"  macro static function mergeExpr(p:haxe.macro.Expr):haxe.macro.Expr {",
			"    return macro null;",
			"  }",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    MacroApi.mergeExprOf({ cou" + exprOfMarker + " });",
			"    MacroApi.mergeExpr({ cou" + exprMarker + " });",
			"  }",
			"}",
		].join("\n");

		final exprOfCursor = source.indexOf(exprOfMarker);
		assertTrue(exprOfCursor >= 0, "missing ExprOf cursor marker");
		source = StringTools.replace(source, exprOfMarker, "");

		final exprCursor = source.indexOf(exprMarker);
		assertTrue(exprCursor >= 0, "missing Expr cursor marker");
		source = StringTools.replace(source, exprMarker, "");

		final exprOfResponse = hxhx.DisplayResponseSynthesizer.synthesize("Main.hx@" + exprOfCursor, source);
		assertContains(exprOfResponse, 'n="count"', "ExprOf completion should include `count`");
		assertContains(exprOfResponse, 'n="label"', "ExprOf completion should include `label`");
		assertContains(exprOfResponse, 'n="enabled"', "ExprOf completion should include optional field `enabled`");

		final exprResponse = hxhx.DisplayResponseSynthesizer.synthesize("Main.hx@" + exprCursor, source);
		assertTrue(exprResponse == "<list></list>", "Plain Expr completion should remain the default empty list");

		final diagnosticsResponse = hxhx.DisplayResponseSynthesizer.synthesize("Main.hx@0@diagnostics", source);
		assertTrue(
			diagnosticsResponse == '[{"diagnostics":[]}]',
			"Diagnostics display mode should keep existing synthetic response"
		);
	}
}
