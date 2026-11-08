/** An unchecked cast leaves `T` open; `S:T` then closes it to String, which breaks `T:Int`. */
class InvalidCastBound {
	static function pick<T:Int, S:T>(value:T, fallback:S):S {
		return fallback;
	}

	static function main():Void {
		pick(cast null, "text");
	}
}
