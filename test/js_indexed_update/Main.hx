/** Observe which declared operator a declared-index update selects. */
class Events {
	public static var text:String = "";
}

/** Distinct increments and compound operators expose accidental primitive rewrites. */
abstract Counter(Int) from Int to Int {
	@:op(A++) public inline function post():Counter {
		Events.text += "post;";
		var old = this;
		this += 10;
		return old;
	}

	@:op(++A) public inline function pre():Counter {
		Events.text += "pre;";
		this += 20;
		return this;
	}

	@:op(A + B) public static function plus(a:Counter, b:Int):Counter {
		Events.text += "plus;";
		var value:Int = a;
		return value + b + 100;
	}

	@:op(A += B) public static function compound(a:Counter, b:Int):Counter {
		Events.text += "compound;";
		var value:Int = a;
		return value + b + 1000;
	}
}

/** The setter result type differs from the getter type; postfix still returns the old getter value. */
abstract Cells(Array<Int>) {
	public inline function new() {
		this = [5];
	}

	@:op([]) public inline function read(index:Int):Int {
		Events.text += "G";
		return this[index];
	}

	@:op([]) public inline function write(index:Int, value:Float):String {
		Events.text += "S";
		this[index] = Std.int(value);
		return "stored" + value;
	}
}

/** Compare declared-index updates with upstream JavaScript: values, stored results, events and operand order. */
class Main {
	static var order:String = "";
	static var current:Map<String, Int> = ["x" => 3];
	static var other:Map<String, Int> = ["x" => 20];
	static var alternate:Bool = false;
	static var calls:Int = 0;

	static function receiver():Map<String, Int> {
		order += "receiver;";
		calls++;
		return alternate && calls == 2 ? other : current;
	}

	static function key():String {
		order += "key;";
		return "x";
	}

	static function value():Int {
		order += "value;";
		current.set("x", 100);
		return 4;
	}

	static function log(text:String):Void {
		js.Syntax.code("console.log({0})", text);
	}

	static function show(value:Null<Counter>):String {
		return value == null ? "null" : Std.string(value);
	}

	static function report(state:String, operation:String, observed:Counter, values:Map<String, Counter>):Void {
		log(state + ":" + operation + ":value=" + show(observed) + ":stored=" + show(values.get("x")) + ":events=" + Events.text);
	}

	static function counters(state:String):Map<String, Counter> {
		var values:Map<String, Counter> = [];
		if (state == "present")
			values.set("x", 1);
		if (state == "null") {
			var explicitNull:Null<Counter> = null;
			values.set("x", explicitNull);
		}
		Events.text = "";
		return values;
	}

	static function postfix(state:String):Void {
		var values = counters(state);
		var observed = values["x"]++;
		report(state, "postfix", observed, values);
	}

	static function prefix(state:String):Void {
		var values = counters(state);
		var observed = ++values["x"];
		report(state, "prefix", observed, values);
	}

	static function compound(state:String):Void {
		var values = counters(state);
		var observed = (values["x"] += 2);
		report(state, "compound", observed, values);
	}

	static function main():Void {
		for (state in ["present", "null", "absent"]) {
			postfix(state);
			prefix(state);
			compound(state);
		}
		var ints:Map<String, Int> = ["c" => 5];
		var intPostfix = ints["c"]++;
		var intPrefix = ++ints["c"];
		var intCompound = (ints["c"] += 3);
		log("int:" + intPostfix + ":" + intPrefix + ":" + intCompound + ":" + ints["c"]);
		var nullable:Map<String, Null<Int>> = ["x" => 4];
		var nullablePostfix = nullable["x"]++;
		var nullablePrefix = ++nullable["x"];
		log("nullable:" + nullablePostfix + ":" + nullablePrefix + ":" + nullable["x"]);
		order = "";
		var compoundResult = (receiver()[key()] += value());
		log("compound-order:" + compoundResult + ":" + current["x"] + ":" + order);
		current["x"] = 3;
		order = "";
		calls = 0;
		alternate = true;
		var postfixResult = receiver()[key()]++;
		log("postfix-order:" + postfixResult + ":" + current["x"] + ":" + other["x"] + ":" + order);
		other["x"] = 20;
		order = "";
		calls = 0;
		var prefixResult = ++receiver()[key()];
		log("prefix-order:" + prefixResult + ":" + current["x"] + ":" + other["x"] + ":" + order);
		alternate = false;
		var cells = new Cells();
		Events.text = "";
		var cellPostfix:String = cells[0]++;
		var cellPrefix:String = ++cells[0];
		var cellCompound:String = (cells[0] += 2);
		log("cells:" + cellPostfix + ":" + cellPrefix + ":" + cellCompound + ":" + cells[0] + ":" + Events.text);
	}
}
