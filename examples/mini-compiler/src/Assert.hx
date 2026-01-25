class Assert {
	public static function eqInt(actual:Int, expected:Int, label:String):Void {
		if (actual != expected) {
			throw 'Assert failed (' + label + '): expected ' + expected + ', got ' + actual;
		}
	}

	public static function eqString(actual:String, expected:String, label:String):Void {
		if (actual != expected) {
			throw 'Assert failed (' + label + '): expected "' + expected + '", got "' + actual + '"';
		}
	}
}

