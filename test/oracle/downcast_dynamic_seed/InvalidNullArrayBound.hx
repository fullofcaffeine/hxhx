/** A null literal leaves `T` open, but `S:Array<T>` still needs an array for `S`. */
class InvalidNullArrayBound {
	static function pick<T, S:Array<T>>(value:T, fallback:S):S {
		return fallback;
	}

	static function main():Void {
		pick(null, 5);
	}
}
