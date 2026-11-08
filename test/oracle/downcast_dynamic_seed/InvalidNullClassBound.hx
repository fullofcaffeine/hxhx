/** A null literal leaves `T` open, but `S:Class<T>` still needs a class value for `S`. */
class InvalidNullClassBound {
	static function pick<T, S:Class<T>>(value:T, fallback:S):S {
		return fallback;
	}

	static function main():Void {
		pick(null, 5);
	}
}
