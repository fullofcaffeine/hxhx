import backend.js.JsExprEmitter;
import backend.js.JsFunctionScope;

/** Execute authored switches through shared lowering and retain the separate macro-quotation contracts. */
class M14JsExprEmitterSwitchExprIntegrationTest {
	/** Final syntax rendering must reject a throw that bypasses shared control lowering. */
	static function assertRawControlRejected():Void {
		final scope = new JsFunctionScope(new haxe.ds.StringMap<String>());
		try {
			JsExprEmitter.emit(HxParser.parseExprText("switch (value) { case _: throw 'failure'; }"), scope.exprScope());
		} catch (message:String) {
			if (message.indexOf("source control must be lowered before JavaScript emission") < 0)
				throw message;
			return;
		}
		throw "raw switch control bypassed shared lowering";
	}

	static function main():Void {
		M14JsSwitchExpressionRuntimeTest.run();
		M14JsGeneralExtractorRuntimeTest.assertCurrentBoundary();
		assertRawControlRejected();
	}
}
