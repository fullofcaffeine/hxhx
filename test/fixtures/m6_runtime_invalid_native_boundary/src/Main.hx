/** Exercises validation of an explicitly declared native runtime capability. **/
class Main {
	static function main():Void {
		InvalidNativeRuntimeBoundary.touch();
	}
}

/** An intentionally invalid extern used to prove unknown capabilities fail. **/
@:native("HxStdio")
private extern class InvalidNativeRuntimeBoundary {
	@:ocamlRuntime("not-a-runtime-capability")
	static function touch():Void;
}
