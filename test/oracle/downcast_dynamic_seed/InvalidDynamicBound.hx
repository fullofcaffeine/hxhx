/** Dynamic leaves `T` open; `S:T` then closes it to Int, which breaks `T:String`. */
class InvalidDynamicBound {
	static function pick<T:String, S:T>(value:T, fallback:S):S {
		return fallback;
	}

	static function main():Void {
		final value:Dynamic = "text";
		pick(value, 5);
	}
}
