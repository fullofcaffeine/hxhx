import backend.js.JsTargetCore;
import backend.js.JsWriter;

/** A Boolean class marker must not hide the native constructor name used by Boot. */
class M14JsBootTypeMarkerTest {
	static function main():Void {
		final writer = new JsWriter();
		@:privateAccess JsTargetCore.emitJsBootInstanceofBody(writer, "value", "type");
		// This is the emitted runtime boundary itself. The provider integration test
		// separately proves that real Std.string initialization supplies this marker.
		final script = "function check(value,type) {\n"
			+ writer.toString()
			+ "\n}\n"
			+ 'for (const marker of [true, false, "String", ["String"]]) {'
			+ 'String.__name__ = marker;'
			+ 'if (!check("word",String) || check(7,String) || check(null,String)) throw "String marker contract";'
			+ '}'
			+ 'Array.__name__ = true;'
			+ 'if (!check([],Array) || check({},Array) || check("word",Array)) throw "Array marker contract";';
		@:privateAccess M14JsStmtEmitterKeyValueForIntegrationTest.checkRuntime(script, "");
		Sys.println("JS_BOOT_TYPE_MARKER:PASS");
	}
}
