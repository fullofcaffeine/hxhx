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
		classRefs.set("StringMap", "__hx_cls_haxe_ds_StringMap");
		classRefs.set("List", "__hx_cls_List");
		final scope = new JsFunctionScope(classRefs);
		final exprScope = scope.exprScope();

		final qualifiedCtor = HxParser.parseExprText("new utest.ui.text.HtmlReport(null)");
		assertEquals(JsExprEmitter.emit(qualifiedCtor, exprScope), "new __hx_cls_utest_ui_text_HtmlReport(null)",
			"qualified ctor should resolve via simple class ref fallback");

		final genericSimpleCtor = HxParser.parseExprText("new StringMap<V>()");
		assertEquals(JsExprEmitter.emit(genericSimpleCtor, exprScope), "new __hx_cls_haxe_ds_StringMap()",
			"generic constructor lookup should ignore compile-time type parameters");

		final genericQualifiedCtor = HxParser.parseExprText("new haxe.ds.StringMap<V>()");
		assertEquals(JsExprEmitter.emit(genericQualifiedCtor, exprScope), "new __hx_cls_haxe_ds_StringMap()",
			"qualified generic constructor should resolve via its runtime class name");

		final genericListCtor = HxParser.parseExprText("new List<A>()");
		assertEquals(JsExprEmitter.emit(genericListCtor, exprScope), "new __hx_cls_List()",
			"generic List constructor should resolve via its runtime class name");
	}
}
