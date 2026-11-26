class Wrong {
	static function apply<T>(f:Int->T):T
		return f(1);

	static function main() {
		final n:Int = apply(value -> trace(value));
	}
}
