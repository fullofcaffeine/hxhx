import backend.js.JsBackend;
import backend.js.JsTargetCore;

class M14JsTargetCoreWiringIntegrationTest {
	static function assertTrue(cond:Bool, message:String):Void {
		if (!cond) throw message;
	}

	static function main():Void {
		final core = new JsTargetCore();
		assertTrue(core.coreId() == JsTargetCore.CORE_ID, "unexpected JS target core id");

		final backend = new JsBackend();
		assertTrue(backend.id() == "js-native", "unexpected JS backend id");
		assertTrue(JsBackend.targetCore().coreId() == core.coreId(), "js backend is not wired to JS target core");
	}
}

