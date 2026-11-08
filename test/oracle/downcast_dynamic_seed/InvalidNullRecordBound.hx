/** A null literal leaves `T` open, but `S:{x:T}` still needs a field `x` on `S`. */
class InvalidNullRecordBound {
	static function pick<T, S:{x:T}>(value:T, fallback:S):S {
		return fallback;
	}

	static function main():Void {
		pick(null, {y: 1});
	}
}
