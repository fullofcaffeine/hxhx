import haxe.ds.IntMap;
import haxe.ds.ObjectMap;
import haxe.ds.StringMap;

class Key {
	public final name:String;

	public function new(name:String) {
		this.name = name;
	}
}

class Holder {
	public final scores:Map<String, Int>;

	public function new() {
		scores = new Map();
	}
}

/**
	Uses String-, Int-, and object-keyed maps through the `Map` abstract and
	through the `StringMap`, `IntMap`, and `ObjectMap` classes, then prints what
	each operation returned. Upstream Haxe does not define a Map iteration
	order, so every listing with more than one entry is sorted before printing.
	Each `remove` result is saved before printing, so the output does not
	depend on the order in which one concatenation evaluates its operands
	(haxe_ocaml-5of2v). Float values are not whole numbers, because native
	whole-number Float text is tracked separately (haxe_ocaml-iffj5).
**/
class Main {
	static var shared:StringMap<String> = new StringMap();
	static var colors:Map<String, Int> = ["red" => 1];

	static function sorted(items:Array<String>):String {
		items.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		return items.join(",");
	}

	static function stringMap():Void {
		final s = new StringMap<Int>();
		s.set("a", 1);
		s.set("b", 2);
		s.set("a", 3);
		Sys.println("string get=" + s.get("a") + "," + s.get("b") + " missing=" + s.get("zz"));
		Sys.println("string exists=" + s.exists("a") + "," + s.exists("zz"));
		Sys.println("string keys=" + sorted([for (k in s.keys()) k]));
		Sys.println("string values=" + sorted([for (v in s.iterator()) Std.string(v)]));
		Sys.println("string pairs=" + sorted([for (k => v in s.keyValueIterator()) k + ":" + v]));
		final copy = s.copy();
		copy.set("c", 9);
		Sys.println("string copy=" + copy.exists("c") + " original=" + s.exists("c"));
		final removed = s.remove("a");
		final again = s.remove("a");
		Sys.println("string remove=" + removed + "," + again + " left=" + sorted([for (k in s.keys()) k]));
		Sys.println("string text=" + s.toString());
		s.clear();
		Sys.println("string cleared=" + [for (k in s.keys()) k].length + " text=" + s.toString());
		shared.set("x", "y");
		Sys.println("string static=" + shared.get("x") + "," + shared.exists("y"));
	}

	static function intMap():Void {
		final i = new IntMap<String>();
		i.set(3, "c");
		i.set(-1, "m");
		i.set(0, "z");
		Sys.println("int get=" + i.get(3) + "," + i.get(0) + " missing=" + i.get(7));
		Sys.println("int exists=" + i.exists(-1) + "," + i.exists(7));
		Sys.println("int keys=" + sorted([for (k in i.keys()) Std.string(k)]));
		Sys.println("int values=" + sorted([for (v in i) v]));
		Sys.println("int pairs=" + sorted([for (k => v in i) k + ":" + v]));
		final removed = i.remove(3);
		final again = i.remove(3);
		Sys.println("int remove=" + removed + "," + again + " left=" + sorted([for (k in i.keys()) Std.string(k)]));
		i.remove(-1);
		Sys.println("int text=" + i.toString() + " copy=" + i.copy().get(0));
		i.clear();
		Sys.println("int cleared=" + i.exists(0));
	}

	static function objectMap():Void {
		final first = new Key("same");
		final second = new Key("same");
		final o = new ObjectMap<Key, Int>();
		o.set(first, 1);
		o.set(second, 2);
		o.set(first, 3);
		Sys.println("object get=" + o.get(first) + "," + o.get(second) + " missing=" + o.get(new Key("same")));
		Sys.println("object exists=" + o.exists(second) + " keys=" + [for (k in o.keys()) k.name].length);
		Sys.println("object values=" + sorted([for (v in o) Std.string(v)]));
		Sys.println("object pairs=" + sorted([for (k => v in o) k.name + ":" + v]));
		final removed = o.remove(first);
		final again = o.remove(first);
		Sys.println("object remove=" + removed + "," + again + " copy=" + o.copy().exists(second));
		o.clear();
		Sys.println("object cleared=" + o.exists(second));
	}

	static function count(map:Map<String, Int>):Int {
		var total = 0;
		for (value in map)
			total += value;
		return total;
	}

	static function abstractMap():Void {
		final m = new Map<String, Int>();
		m.set("b", 1);
		for (name in m.keys())
			Sys.println("map key=" + name);
		final literal = ["one" => 1, "two" => 2, "three" => 3];
		literal["four"] = 4;
		literal["one"] = 10;
		Sys.println("map index=" + literal["one"] + "," + literal["four"] + " missing=" + literal["none"]);
		Sys.println("map exists=" + literal.exists("two") + "," + literal.exists("none"));
		Sys.println("map keys=" + sorted([for (k in literal.keys()) k]));
		Sys.println("map pairs=" + sorted([for (k => v in literal) k + ":" + v]));
		Sys.println("map sum=" + count(literal));
		final copy = literal.copy();
		copy.remove("two");
		final removed = literal.remove("three");
		final again = literal.remove("three");
		Sys.println("map remove=" + removed + "," + again + " copy=" + copy.exists("two") + "," + literal.exists("two"));
		final single = ["only" => 7];
		Sys.println("map text=" + single.toString() + " empty=" + new Map<String, Int>().toString());
		literal.clear();
		Sys.println("map cleared=" + [for (k in literal.keys()) k].length);

		final numbers = [2 => "two", 1 => "one"];
		numbers[3] = "three";
		Sys.println("map int=" + numbers[1] + "," + numbers[3] + " missing=" + numbers[9]);
		Sys.println("map int pairs=" + sorted([for (k => v in numbers) k + ":" + v]));

		final weights:Map<String, Float> = ["half" => 0.5];
		weights.set("more", 2.25);
		Sys.println("map float=" + weights.get("half") + "," + weights["more"] + " missing=" + weights.get("none"));

		final holder = new Holder();
		holder.scores["ann"] = 4;
		holder.scores.set("bob", 5);
		Sys.println("map field=" + holder.scores.get("ann") + "," + holder.scores["bob"] + " sum=" + count(holder.scores));

		// A stored Array is read back as Null<Array<Int>> and then used as an Array.
		final lists = new Map<String, Array<Int>>();
		lists.set("a", [1]);
		lists.get("a").push(2);
		lists["a"].push(3);
		Sys.println("map initializer=" + colors["red"] + "," + colors.exists("blue"));
		Sys.println("map array=" + lists["a"].join(",") + " length=" + lists.get("a").length + "," + lists["a"].length);
	}

	static function main():Void {
		stringMap();
		intMap();
		objectMap();
		abstractMap();
	}
}
