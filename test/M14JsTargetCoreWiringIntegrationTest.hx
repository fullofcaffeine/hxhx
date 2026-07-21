import backend.js.JsBackend;
import backend.js.JsExprEmitter;
import backend.js.JsTargetCore;

class M14JsTargetCoreWiringIntegrationTest {
	static function assertTrue(cond:Bool, message:String):Void {
		if (!cond)
			throw message;
	}

	static function main():Void {
		final core = new JsTargetCore();
		assertTrue(core.coreId() == JsTargetCore.CORE_ID, "unexpected JS target core id");

		final backend = new JsBackend();
		assertTrue(backend.id() == "js-native", "unexpected JS backend id");
		assertTrue(JsBackend.targetCore().coreId() == core.coreId(), "js backend is not wired to JS target core");

		final scope:backend.js.JsEmitScope = {
			resolveLocal: function(_):Null<String> return null,
			resolveClassRef: function(_):Null<String> return null,
			resolveSuperClassRef: function():Null<String> return null,
		};
		final nullSafeCopy = JsExprEmitter.emit(ECall(ENullSafeField(EIdent("unexpectedStrings"), "copy"), []), scope);
		assertTrue(nullSafeCopy == "(unexpectedStrings)?.copy()", "JS null-safe call did not use optional chaining: " + nullSafeCopy);
		final nullSafeMacro = JsExprEmitter.emit(EMacroExpr(ENullSafeField(EIdent("value"), "field"), []), scope);
		assertTrue(nullSafeMacro.indexOf('__hx_ctor: "Safe"') >= 0, "JS macro quote did not preserve null-safe field access: " + nullSafeMacro);
	}
}
