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

		final tryRawError = captureUnsupported(ETryCatchRaw("opaque_block_expr"));
		assertContains(tryRawError, "[js-native:unsupported_expr]", "try raw prefix");
		assertContains(tryRawError, "kind=ETryCatchRaw", "try raw kind");
		assertContains(tryRawError, "detail=opaque_block_expr", "try raw detail");

		final opaqueError = captureUnsupported(EUnsupported("opaque_payload"));
		assertContains(opaqueError, "[js-native:unsupported_expr]", "unsupported payload prefix");
		assertContains(opaqueError, "kind=EUnsupported", "unsupported payload kind");
		assertContains(opaqueError, "detail=opaque_payload", "unsupported payload detail");

		final returnError = captureUnsupported(EReturn(ECast(ENull, "Null<String>")));
		assertContains(returnError, "[js-native:unsupported_expr]", "unexpanded return prefix");
		assertContains(returnError, "kind=EReturn", "unexpanded return kind");
		assertContains(returnError, "macro expansion", "unexpanded return guidance");

		final declarationError = captureUnsupported(EVars([HxExprVarDecl.make("value", "String", ENull, new HxPos(0, 1, 1))]));
		assertContains(declarationError, "[js-native:unsupported_expr]", "unexpanded variable declaration prefix");
		assertContains(declarationError, "kind=EVars", "unexpanded variable declaration kind");
		assertContains(declarationError, "macro expansion", "unexpanded variable declaration guidance");
	}
}
