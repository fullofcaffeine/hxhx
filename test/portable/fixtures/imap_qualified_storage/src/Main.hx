import haxe.Constraints.IMap;

/** A nominal value keeps this regression independent of compiler internals. */
class Item {
	public final value:Int;

	public function new(value:Int)
		this.value = value;
}

/** Inferred fields expose haxe.ds.Map while written global annotations expose Map. */
class Catalog {
	final inferred = new Map<String, Item>();
	final written:Map<String, Item> = new Map();
	final qualified:haxe.ds.Map<String, Item> = new haxe.ds.Map();

	public function new() {
		inferred.set("a", new Item(3));
		written.set("a", new Item(4));
		qualified.set("a", new Item(5));
	}

	public function check():Void {
		Sys.println(inferred.iterator().hasNext());
		Sys.println(written.iterator().hasNext());
		Sys.println(qualified.iterator().hasNext());
		Sys.println(read(inferred));
		Sys.println(read(written));
		Sys.println(read(qualified));
	}

	static function read(items:IMap<String, Item>):Int
		return items.get("a").value;
}

/** Both standard type forms preserve iteration and ordinary interface conversion. */
class Main {
	static function main():Void
		new Catalog().check();
}
