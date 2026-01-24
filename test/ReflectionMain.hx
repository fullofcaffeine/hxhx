class ReflectionMain {
	static function main() {
		final obj:Dynamic = { a: 1 };
		final key = "a";
		final value = Reflect.field(obj, key);
	}
}
