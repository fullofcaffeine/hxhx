import backend.js.JsExprEmitter;
import backend.js.JsFunctionScope;

class M14JsExprEmitterQualifiedCtorIntegrationTest {
	static function assertEquals(actual:String, expected:String, label:String):Void {
		if (actual != expected)
			throw label + ": expected '" + expected + "' but got '" + actual + "'";
	}

	static function main() {
		final classRefs = new haxe.ds.StringMap<String>();
		classRefs.set("HtmlReport", "__hx_cls_utest_ui_text_HtmlReport");
		final scope = new JsFunctionScope(classRefs);
		final exprScope = scope.exprScope();

		final qualifiedCtor = HxParser.parseExprText("new utest.ui.text.HtmlReport(null)");
		assertEquals(JsExprEmitter.emit(qualifiedCtor, exprScope), "new __hx_cls_utest_ui_text_HtmlReport(null)",
			"qualified ctor should resolve via simple class ref fallback");
	}
}
