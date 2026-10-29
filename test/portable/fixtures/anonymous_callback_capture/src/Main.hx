/** An object whose identity must survive a callback result. */
class Item {
	public function new() {}
}

/** A typed callback stored in an ordinary anonymous record. */
typedef Owner = {final find:Void->Null<Item>;}

/** Exercises callback capture without replacing the stored function. */
class Main {
	static var reads:Int = 0;

	static function nextItem(item:Item):Item {
		reads++;
		return item;
	}

	static function validate(owners:haxe.ds.ObjectMap<Item, Owner>, item:Item):Void->Bool {
		final find = owners.get(nextItem(item)).find;
		return () -> find() == item;
	}

	static function main() {
		final item = new Item();
		final owners = new haxe.ds.ObjectMap<Item, Owner>();
		final callback:Void->Null<Item> = () -> item;
		owners.set(item, {find: callback});
		final check = validate(owners, item);
		Sys.println(check());
		Sys.println('reads=$reads');
		Sys.println('same=${owners.get(item).find == callback}');
	}
}
