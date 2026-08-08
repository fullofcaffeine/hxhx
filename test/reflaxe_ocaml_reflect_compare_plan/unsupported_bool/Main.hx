/** A resolved Bool comparator must fail before OCaml syntax is generated. */
class Main {
	static function main():Void
		Sys.println(Reflect.compare(false, true));
}
