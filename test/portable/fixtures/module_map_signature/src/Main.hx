import haxe.ds.StringMap;
import haxe.ds.IntMap;
import haxe.ds.ObjectMap;

/** Runtime equality and mutation prove that module signatures preserve storage. */
class Main {
	static function main():Void {
		final original = new StringMap<String>();
		original.set("key", "before");
		final returned = First.roundtrip(original);
		Sys.println(returned == original);
		Sys.println(returned.get("key"));
		returned.set("key", "after");
		Sys.println(original.get("key"));
		Sys.println(First.roundtrip(null) == null);
		Sys.println(First.optional().exists("key"));
		Sys.println(First.optional(null).exists("key"));
		Sys.println(First.optional(original) == original);

		final integers = new IntMap<Array<String>>();
		integers.set(7, ["one"]);
		final returnedIntegers = First.integers(integers);
		Sys.println(returnedIntegers == integers);
		returnedIntegers.get(7).push("two");
		Sys.println(integers.get(7).join(","));

		final key = new Key(1);
		final otherKey = new Key(1);
		final objects = new ObjectMap<Key, String>();
		objects.set(key, "first");
		objects.set(otherKey, "second");
		final returnedObjects = First.objects(objects);
		Sys.println(returnedObjects == objects);
		returnedObjects.set(key, "changed");
		Sys.println(objects.get(key) + "," + objects.get(otherKey));

		final nested:Map<String, Map<Int, String>> = ["outer" => [3 => "start"]];
		final returnedNested = First.nested(nested);
		Sys.println(returnedNested == nested);
		final replacement:Map<Int, String> = [4 => "finish"];
		returnedNested.set("outer", replacement);
		Sys.println(nested.get("outer") == replacement);
		Sys.println(First.nullable(null) == null);
		final maybe:Null<Map<Int, String>> = replacement;
		Sys.println(First.nullable(maybe) == maybe);
	}
}
