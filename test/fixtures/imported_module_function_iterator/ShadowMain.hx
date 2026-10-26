import Functions;

/** A local callable keeps precedence over the same imported function name. */
class ShadowMain {
	static function main():Void {
		final record = function(value:Bool):Bool return value;
		for (value in [record(true)])
			if (!value)
				throw "local function did not shadow the imported function";
		Sys.println("IMPORTED_MODULE_FUNCTION_SHADOW:PASS");
	}
}
