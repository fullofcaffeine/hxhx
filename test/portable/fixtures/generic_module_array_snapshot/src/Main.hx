/** Observes generic snapshot equality for independent element specializations. */
class Main {
	static var reads:Int = 0;

	static function main():Void {
		final ints = [1, 2];
		final intsSame = Snapshot.unchanged(() -> {
			reads++;
			return ints;
		});
		Sys.println("ints:" + intsSame() + ":" + reads);
		ints[1] = 3;
		Sys.println("ints-changed:" + intsSame() + ":" + reads);

		final floats = [1.5, 2.25];
		final floatsSame = Snapshot.unchanged(() -> floats);
		Sys.println("floats:" + floatsSame());
		floats[0] = 1.75;
		Sys.println("floats-changed:" + floatsSame());

		final flags = [true, false];
		final flagsSame = Snapshot.unchanged(() -> flags);
		Sys.println("flags:" + flagsSame());
		flags[1] = true;
		Sys.println("flags-changed:" + flagsSame());

		final words = ["first", "second"];
		final wordsSame = Snapshot.unchanged(() -> words);
		Sys.println("words:" + wordsSame());
		words[0] = ("x" + words[0]).substr(1);
		Sys.println("words-equal-copy:" + wordsSame());
		words.push("third");
		Sys.println("words-grown:" + wordsSame());

		final nullable:Array<Null<Int>> = [null, 4];
		final nullableSame = Snapshot.unchanged(() -> nullable);
		Sys.println("nullable:" + nullableSame());
		nullable[0] = 0;
		Sys.println("nullable-changed:" + nullableSame());

		final box = new Box(4);
		final boxes = [box];
		final boxesSame = Snapshot.unchanged(() -> boxes);
		Sys.println("boxes:" + boxesSame());
		boxes[0] = new Box(4);
		Sys.println("boxes-replaced:" + boxesSame());
		boxes[0] = box;
		Sys.println("boxes-restored:" + boxesSame());
	}
}
