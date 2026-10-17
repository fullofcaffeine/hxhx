/** Exercises module functions and classes through real native calls and initialization. */
class Main {
	static function main():Void {
		Sys.println("class first=" + CounterOps.total(4));
		Sys.println("function first=" + ReverseOps.total(5));
		Sys.println("mutual=" + MutualOps.count(4));
		Sys.println("static result=" + InitOps.total());
		Sys.println("initializers=" + Events.observed.join(","));
	}
}
