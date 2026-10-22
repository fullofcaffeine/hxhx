import backend.js.JsBackend;
import backend.js.JsExprEmitter;
import backend.js.JsTargetCore;

/** Backend wiring and quotation use the same retained enum declarations as complete programs. */
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

		final scope = JsMacroQuotationFixture.scope();
		final nullSafeCopy = JsExprEmitter.emit(ECall(ENullSafeField(EIdent("unexpectedStrings"), "copy"), []), scope);
		assertTrue(nullSafeCopy == "(unexpectedStrings)?.copy()", "JS null-safe call did not use optional chaining: " + nullSafeCopy);
		final nullSafeMacro = JsExprEmitter.emit(EMacroExpr(ENullSafeField(EIdent("value"), "field"), []), scope);
		final safeConstructor = scope.enumDeclarations("haxe.macro.Expr.EFieldKind").reference + ".Safe";
		assertTrue(nullSafeMacro.indexOf(safeConstructor) >= 0, "JS macro quote did not preserve null-safe field access: " + nullSafeMacro);
	}
}
