/** Preserve the original JS oracle array-comprehension contract through normal driver preparation. */
class JsOracleArrayComprehensionMain {
	static function main() {
		var doubled = [for (i in 0...4) i * 2];
		var shifted = [for (value in doubled) value + 1];
		trace("JS_ORACLE|arr-comp:" + shifted.length + ":" + shifted[0] + ":" + shifted[3]);
	}
}
