/** A Dynamic comparator must not fall back to OCaml structural comparison. */
class Main {
	static function main():Void {
		final compareDynamic:(Dynamic, Dynamic) -> Int = Reflect.compare;
		Sys.println(compareDynamic("left", "right"));
	}
}
