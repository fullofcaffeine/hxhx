class Main {
	static function main() {
		// These calls exist to ensure the compiler emits extern static access paths
		// according to @:native mapping rules.
		NativeMod.hello();
		NativeMod.goodbye();
	}
}
