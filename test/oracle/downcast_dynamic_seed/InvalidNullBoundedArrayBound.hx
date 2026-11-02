/** Skipping `T:String` for a null `T` must not also skip the shape check `S:Array<T>`. */
class InvalidNullBoundedArrayBound {
	static function pick<T:String, S:Array<T>>(value:T, fallback:S):S {
		return fallback;
	}

	static function main():Void {
		pick(null, 5);
	}
}
