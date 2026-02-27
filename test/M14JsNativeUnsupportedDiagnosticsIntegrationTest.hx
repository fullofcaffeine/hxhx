import backend.js.JsExprEmitter;
import backend.js.JsFunctionScope;

class M14JsNativeUnsupportedDiagnosticsIntegrationTest {
	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack == null || haystack.indexOf(needle) < 0)
			throw label + ": expected substring '" + needle + "' in '" + haystack + "'";
	}

	static function captureUnsupported(expr:HxExpr):String {
		final scope = new JsFunctionScope(new haxe.ds.StringMap<String>());
		final exprScope = scope.exprScope();
		try {
			JsExprEmitter.emit(expr, exprScope);
			throw "expected unsupported diagnostic";
		} catch (e:Dynamic) {
			return Std.string(e);
		}
	}

	static function main() {
		final ctorError = captureUnsupported(ENew("MissingType", []));
		assertContains(ctorError, "[js-native:unsupported_expr]", "ctor prefix");
		assertContains(ctorError, "kind=ENew", "ctor kind");
		assertContains(ctorError, "detail=MissingType", "ctor detail");

		final switchRawError = captureUnsupported(ESwitchRaw("opaque_switch"));
		assertContains(switchRawError, "[js-native:unsupported_expr]", "switch raw prefix");
		assertContains(switchRawError, "kind=ESwitchRaw", "switch raw kind");

		final tryRawError = captureUnsupported(ETryCatchRaw("opaque_try"));
		assertContains(tryRawError, "[js-native:unsupported_expr]", "try raw prefix");
		assertContains(tryRawError, "kind=ETryCatchRaw", "try raw kind");

		final opaqueError = captureUnsupported(EUnsupported("opaque_payload"));
		assertContains(opaqueError, "[js-native:unsupported_expr]", "unsupported payload prefix");
		assertContains(opaqueError, "kind=EUnsupported", "unsupported payload kind");
		assertContains(opaqueError, "detail=opaque_payload", "unsupported payload detail");
	}
}
