/** Distinct instances must remain distinct Map keys, even without visible fields. */
class MapKey {
	public function new() {}
}

/** A freshly constructed equal enum value must find an existing Map entry. */
enum MapItem {
	Value(value:Int);
}

/** Conversion effects distinguish saving a key from saving its converted value. */
abstract MapConvertedKey(String) {
	public function new(value:String) {
		this = value;
	}

	@:to public function toText():String {
		Main.recordKeyConversion();
		return this;
	}
}

/** Field initialization exercises the same collection allocation outside a named function body. */
class MapHolder {
	public var values:Map<String, Int> = ["field" => 6];

	public function new() {}
}

/** Observe which declared value operator Haxe selects for an indexed update. */
class MapOperatorEvents {
	public static var text:String = "";
}

/** Distinct increments and compound operators expose accidental primitive rewrites. */
abstract MapCounter(Int) from Int to Int {
	@:op(A++) public inline function post():MapCounter {
		MapOperatorEvents.text += "post;";
		var old = this;
		this += 10;
		return old;
	}

	@:op(++A) public inline function pre():MapCounter {
		MapOperatorEvents.text += "pre;";
		this += 20;
		return this;
	}

	@:op(A + B) public static function plus(a:MapCounter, b:Int):MapCounter {
		MapOperatorEvents.text += "plus;";
		var value:Int = a;
		return value + b + 100;
	}

	@:op(A += B) public static function compound(a:MapCounter, b:Int):MapCounter {
		MapOperatorEvents.text += "compound;";
		var value:Int = a;
		return value + b + 1000;
	}
}

/** Compare collection syntax with ordinary Map methods using real target providers. */
class Main {
	static var order:String = "";
	static var current:Map<String, Int> = ["x" => 3];
	static var other:Map<String, Int> = ["x" => 20];
	static var alternating:Bool = false;
	static var receiverCalls:Int = 0;

	static function receiver():Map<String, Int> {
		order += "receiver;";
		receiverCalls++;
		return alternating && receiverCalls == 2 ? other : current;
	}

	static function key():String {
		order += "key;";
		return "x";
	}

	public static function recordKeyConversion():Void {
		order += "convert;";
	}

	static function convertedKey():MapConvertedKey {
		order += "key;";
		return new MapConvertedKey("x");
	}

	static function value():Int {
		order += "value;";
		current.set("x", 100);
		return 4;
	}

	static function main():Void {
		var literal:Map<String, Int> = ["a" => 1];
		if (literal["a"] != 1)
			throw "literal index";
		literal.set("b", 2);
		if (literal.get("a") != 1 || literal.get("b") != 2 || !literal.exists("a") || literal.exists("absent"))
			throw "methods";
		if (!literal.remove("a") || literal.exists("a"))
			throw "remove";
		var reserved:Map<String, Int> = ["__proto__" => 1, "constructor" => 2, "get" => 3, "length" => 4];
		if (reserved["__proto__"] != 1 || reserved["constructor"] != 2 || reserved["get"] != 3 || reserved["length"] != 4)
			throw "reserved keys";
		var a = new MapKey();
		var b = new MapKey();
		var objects:Map<MapKey, Int> = [a => 1, b => 2];
		if (objects[a] != 1 || objects[b] != 2)
			throw "object identity";
		var enums:Map<MapItem, Int> = [Value(1) => 1, Value(2) => 2];
		if (enums[Value(1)] != 1 || enums[Value(2)] != 2)
			throw "enum equality";
		var comprehension:Map<String, String> = [for (x in ["a", "b"]) x => x.toUpperCase()];
		if (comprehension["a"] != "A" || comprehension["b"] != "B")
			throw "comprehension";
		var functions:Map<Int, Int->Int> = [1 => x -> x + x, 2 => x -> x + 1];
		if (functions[1](3) != 6 || functions[2](8) != 9)
			throw "function values";
		literal["c"] = 5;
		if (literal["c"]++ != 5 || ++literal["c"] != 7 || (literal["c"] += 3) != 10)
			throw "indexed updates";
		var nullable:Map<String, Null<Int>> = ["x" => 4];
		if (nullable["x"]++ != 4 || ++nullable["x"] != 6 || nullable["x"] != 6)
			throw "present nullable indexed updates";
		(literal)["c"] = 11;
		if ((literal)["c"]++ != 11 || ++(literal)["c"] != 13 || ((literal)["c"] += 2) != 15)
			throw "grouped indexed updates";
		if (receiver()[key()] != 3 || order != "receiver;key;")
			throw "read operand order";
		order = "";
		if ((receiver()[key()] = value()) != 4 || current["x"] != 4 || order != "receiver;key;value;")
			throw "assignment operand order";
		current["x"] = 3;
		order = "";
		if ((receiver()[key()] += value()) != 7 || current["x"] != 7 || order != "key;receiver;value;")
			throw "update order or repeated operands";
		current["x"] = 3;
		order = "";
		receiverCalls = 0;
		alternating = true;
		if (receiver()[key()]++ != 3 || current["x"] != 3 || other["x"] != 4 || order != "key;receiver;receiver;")
			throw "postfix read and write destinations";
		other["x"] = 20;
		order = "";
		receiverCalls = 0;
		if (++receiver()[key()] != 4 || current["x"] != 3 || other["x"] != 4 || order != "key;receiver;receiver;")
			throw "prefix read and write destinations";
		alternating = false;
		current["x"] = 3;
		order = "";
		if (receiver()[convertedKey()]++ != 3 || current["x"] != 4 || order != "key;receiver;convert;receiver;convert;")
			throw "postfix key conversion order";
		current["x"] = 3;
		order = "";
		if ((receiver()[convertedKey()] += 2) != 5 || current["x"] != 5 || order != "key;convert;receiver;")
			throw "compound key conversion order";
		order = "";
		var ordered:Map<String, Int> = [key() => value()];
		if (ordered["x"] != 4 || order != "key;value;")
			throw "literal operand order";
		var nested:Map<Int, Int> = [
			for (outer in [1, 2])
				for (inner in [1, 2])
					if (inner == 2)
						outer * 10 + inner => outer
		];
		if (nested[12] != 1 || nested[22] != 2 || nested.exists(11) || nested.exists(21))
			throw "nested guarded comprehension";
		var make = function():Map<String, Int> return ["callback" => 8];
		if (make()["callback"] != 8 || new MapHolder().values["field"] != 6)
			throw "callback or field allocation";
		var plain:MapCounter = 1;
		var plainBefore:Int = plain++;
		var plainAfter:Int = plain;
		if (plainBefore != 1 || plainAfter != 11 || MapOperatorEvents.text != "post;")
			throw "ordinary value operator control";
		MapOperatorEvents.text = "";
		var counters:Map<String, MapCounter> = ["x" => 1];
		var counterBefore:Int = counters["x"]++;
		var counterAfter:Int = counters["x"];
		if (counterBefore != 1 || counterAfter != 2 || MapOperatorEvents.text != "")
			throw "indexed postfix uses numeric storage";
		counters["x"] = 1;
		var counterPrefix:Int = ++counters["x"];
		counterAfter = counters["x"];
		if (counterPrefix != 2 || counterAfter != 2 || MapOperatorEvents.text != "")
			throw "indexed prefix uses numeric storage";
		counters["x"] = 1;
		var combined:Int = (counters["x"] += 2);
		counterAfter = counters["x"];
		if (combined != 1003 || counterAfter != 1003 || MapOperatorEvents.text != "compound;")
			throw "indexed compound keeps the selected operator";
	}
}
