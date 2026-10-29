/** The selected entry class retains ordinary static and instance storage. */
class EntryStateMain {
	public static var count:Int = 1;
	static var initial:Int = seed();

	public var value:Int;

	public function new() {
		value = 9;
	}

	static function seed():Int {
		count++;
		return count + 10;
	}

	static function bump():Int {
		count++;
		return count;
	}

	static function main():Void {
		Sys.println(initial);
		Sys.println(count);
		var count = 40;
		Sys.println(count);
		EntryStateMain.count += 3;
		Sys.println(EntryStateMain.count++);
		Sys.println(++EntryStateMain.count);
		Sys.println(bump());
		Sys.println(new EntryStateMain().value);
		Sys.println(EntryStateReader.read());
	}
}

/** A different class must select the same entry-class storage. */
class EntryStateReader {
	public static function read():Int {
		return EntryStateMain.count;
	}
}
