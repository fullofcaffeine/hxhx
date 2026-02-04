class Main {
	static function main() {
		// Labelled + optional labelled arguments are supported only via metadata
		// (Haxe doesn't have syntax for them).
		Foo.f(1, 2, 3);
		Foo.f(1, 2, null);
		Foo.f(1, 2);
	}
}
