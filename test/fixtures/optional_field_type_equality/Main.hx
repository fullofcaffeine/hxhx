/**
	Haxe 4.3.7 compares invariant type arguments with `type_eq`, which follows `Null` and does not
	compare field optionality. An array built from object literals with a `Null<T>` field therefore
	matches an expected array whose element type declares that field optional (`?tag:Int`) or
	required (`tag:Int`).
	`haxe.macro.ExprTools.map` relies on the first case:
	`var ret = []; ret.push({field: ..., expr: ..., quotes: field.quotes}); EObjectDecl(ret);`.
**/
typedef Entry = {name:String, ?tag:Int};
typedef Pair = {name:String, tag:Int};

class Entries {
	public static function count(entries:Array<Entry>):Int
		return entries.length;

	public static function tagged(entries:Array<Entry>):Int {
		var total = 0;
		for (entry in entries)
			if (entry.tag != null)
				total++;
		return total;
	}

	public static function pairs(entries:Array<Pair>):Int
		return entries.length;

	/** The `ExprTools.map` shape: copy each field, including the optional one, into a new array. **/
	public static function copy(source:Array<Entry>):Int {
		var ret = [];
		for (entry in source)
			ret.push({name: entry.name, tag: entry.tag});
		return tagged(ret);
	}
}

/** The observed operations take simple inputs; `Entries` holds the expected types. **/
class Ops {
	public static function optional(name:String, tag:Null<Int>) {
		var ret = [];
		ret.push({name: name, tag: tag});
		return Entries.tagged(ret);
	}

	public static function required(name:String, tag:Null<Int>) {
		var ret = [];
		ret.push({name: name, tag: tag});
		return Entries.pairs(ret);
	}
}

class Main {
	static function main() {
		Sys.println(Entries.copy([{name: "a", tag: 1}, {name: "b"}]));
		Sys.println(Ops.optional("x", 2));
		Sys.println(Ops.optional("y", null));
		Sys.println(Ops.required("z", 3));
	}
}
