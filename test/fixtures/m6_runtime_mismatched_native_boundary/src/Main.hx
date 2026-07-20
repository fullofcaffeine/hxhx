/** Exercises validation of a runtime capability against its resolved OCaml call. **/
class Main {
	static function main():Void {
		MismatchedNativeRuntimeBoundary.touch();
	}
}

/** An intentionally mismatched extern used to prove target validation fails. **/
@:native("OtherRuntime")
private extern class MismatchedNativeRuntimeBoundary {
	@:ocamlRuntime("haxe-standard-io")
	static function touch():Void;
}
