/** Missing entries return null; receiver and key effects happen once in source order. */
class Main {
	static var initialized:Null<Bool> = ["init" => true].get("init");

	/** An unrelated same-named method must never select the Map binding. */
	static function unrelated(value:Other):String {
		return value.get(1);
	}

	static function map():Map<Int, String> {
		Sys.println('receiver');
		return [1 => 'one'];
	}

	static function key():Int {
		Sys.println('key');
		return 1;
	}

	static function main():Void {
		Sys.println(map().get(key()));
		map().get(key());
		final integers = ['present' => 7];
		Sys.println(integers.get('present'));
		Sys.println(integers.get('missing'));
		final flags = ['present' => true];
		Sys.println(flags.get('present'));
		Sys.println(flags.get('missing'));
		final first = {id: 1};
		final objects = [first => 'stored'];
		Sys.println(objects.get(first));
		Sys.println(objects.get({id: 1}));
		Sys.println(initialized);
		final read = function():Null<Int> {
			return integers.get("present");
		};
		Sys.println(read());
		final namedFirst = new Key(1);
		final namedSecond = new Key(1);
		final named = [namedFirst => 'old', namedFirst => 'updated', namedSecond => 'second'];
		Sys.println(named is haxe.ds.ObjectMap);
		Sys.println(named is haxe.ds.IntMap);
		Sys.println(namedFirst is haxe.ds.ObjectMap);
		Sys.println(named.get(namedFirst));
		Sys.println(named.get(namedSecond));
		Sys.println(named.get(new Key(1)));
		final keys = [namedFirst, namedSecond];
		final built = [for (selected in keys) selected => selected.id];
		Sys.println(built.get(namedFirst));
	}
}

/** Equal field contents do not make distinct instances the same Map key. */
class Key {
	public final id:Int;

	public function new(id:Int) {
		this.id = id;
	}
}

/** Same method spelling, separate declaration identity. */
class Other {
	public function get(key:Int):String {
		return "other";
	}
}
