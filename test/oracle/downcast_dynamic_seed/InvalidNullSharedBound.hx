/** Two bounds share one null-open `T`: `[5]` reads it as Int, so `["a"]` cannot read it as String. */
class InvalidNullSharedBound {
	static function pick<T, S:Array<T>, U:Array<T>>(value:T, first:S, second:U):S {
		return first;
	}

	static function main():Void {
		pick(null, [5], ["a"]);
	}
}
