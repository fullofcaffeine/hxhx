/** Every constructor is parameterless, so the exact enum and index identify its value. */
enum Key {
	First;
	Second;
	Third;
}

/** Replace equal enum keys while preserving missing values and source Map families. */
class Main {
	static var initialized:Null<Int> = [Key.Third => 30].get(Key.Third);

	static function main():Void {
		final values = [Key.First => 10, Key.First => 11, Key.Second => 20];
		Sys.println(values is haxe.ds.EnumValueMap);
		Sys.println(values is haxe.ds.IntMap);
		Sys.println(values is haxe.ds.ObjectMap);
		Sys.println(values.get(Key.First));
		Sys.println(values.get(Key.Second));
		Sys.println(values.get(Key.Third));
		Sys.println(initialized);
		final keys = [Key.First, Key.Second];
		final copied = [for (key in keys) key => 7];
		Sys.println(copied.get(Key.First));
		Sys.println(copied.get(Key.Second));
	}
}
