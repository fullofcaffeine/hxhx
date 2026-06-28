import backend.js.JsExprEmitter;
import backend.js.JsFunctionScope;

class M14JsExprEmitterNewArrayIntegrationTest {
	static function assertEquals(actual:String, expected:String, label:String):Void {
		if (actual != expected)
			throw label + ": expected '" + expected + "' but got '" + actual + "'";
	}

	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack == null || haystack.indexOf(needle) < 0) {
			throw label + ": expected substring '" + needle + "' in '" + haystack + "'";
		}
	}

	static function main() {
		final scope = new JsFunctionScope(new haxe.ds.StringMap<String>());
		final exprScope = scope.exprScope();

		final emptyArray = HxParser.parseExprText("new Array<Int>()");
		assertEquals(JsExprEmitter.emit(emptyArray, exprScope), "[]", "new Array() lowers to []");

		final genericArray = HxParser.parseExprText("new Array<A>()");
		assertEquals(JsExprEmitter.emit(genericArray, exprScope), "[]", "new Array<A>() lowers to []");

		final sizedArray = HxParser.parseExprText("new Array<Int>(3)");
		assertEquals(JsExprEmitter.emit(sizedArray, exprScope), "new Array(3)", "new Array(size) lowers to constructor call");

		final bytesCtor = HxParser.parseExprText("new Bytes(3, null)");
		assertEquals(JsExprEmitter.emit(bytesCtor, exprScope), "new Bytes(3, null)", "new Bytes(length,data) lowers to constructor call");

		var unsupportedError = "";
		try {
			final unsupportedCtor = HxParser.parseExprText("new MissingType()");
			JsExprEmitter.emit(unsupportedCtor, exprScope);
			throw "expected unsupported constructor failure";
		} catch (e:Dynamic) {
			unsupportedError = Std.string(e);
		}
		assertContains(unsupportedError, "[js-native:unsupported_expr]", "unsupported constructor prefix");
		assertContains(unsupportedError, "kind=ENew", "unsupported constructor kind");
		assertContains(unsupportedError, "detail=MissingType", "unsupported constructor detail");
	}
}
