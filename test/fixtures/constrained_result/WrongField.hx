class WrongField {
	static function merge<A:{}, B:{}, C:A & B>(a:A, b:B):C
		return cast {foo: (cast a).foo, bar: (cast b).bar};

	static function main() {
		final merged = merge({foo: 5}, {bar: "bar"});
		trace(merged.oh);
	}
}
