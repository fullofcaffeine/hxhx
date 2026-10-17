/** Observe omitted callbacks, returned closures, null results, and constructor callbacks. */
class Main {
	static function main():Void {
		final left = new Left();
		Sys.println(left.apply(3));
		Sys.println(left.apply(3, value -> value + 1));
		final callback = Left.factory(true);
		if (callback != null)
			Sys.println(callback(2));
		if (Left.factory(false) == null)
			Sys.println("absent");
		new Left(() -> Sys.println("constructed"));
	}
}
