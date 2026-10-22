/** Header conversions preserve the String and take priority over executable conversions. */
abstract Key(String) from String to String {
	public function new(value:String)
		this = value;

	public function read():String
		return this;

	@:to public function wrong():String {
		throw "header conversion lost priority";
	}
}

/** A method conversion must also accept a value created through an input header. */
abstract Input(Int) from Int {
	@:to public function read():Int {
		Main.conversions++;
		return this + 100;
	}
}

/** A class-backed abstract keeps the identity of the supplied object. */
abstract Reference(Cell) from Cell to Cell {
	public function new(value:Cell)
		this = value;

	public function read():Int
		return this.value;
}

/** Owner parameters must not change how an abstract stores its value. */
abstract Generic<T>(T) from T to T {
	public function new(value:T)
		this = value;

	public function read():T
		return this;
}

/** Nested backing abstracts still have one public value. */
abstract Nested(Key) from Key to Key {
	public function new(value:Key)
		this = value;

	public function read():String
		return this.read();
}

/** A mutable reference lets the fixture observe class-backed abstract identity. */
class Cell {
	public var value:Int;

	public function new(value:Int)
		this.value = value;
}

/** A similarly named ordinary field never authorizes abstract unwrapping. */
class Ordinary {
	public var __hx_value:String = "ordinary";

	public function new() {}

	public function read():String
		return __hx_value;
}

/** Constructor exits must return the current value, including omitted arguments and early returns. */
abstract Early(String) to String {
	public function new(arguments:String = "default", stop:Bool = false) {
		this = arguments;
		if (stop)
			return;
		this = this + "!";
	}
}

/** Observe values, nulls, identities, method closures, and exactly-once effects. */
class Main {
	public static var conversions:Int = 0;
	static var initial:Key = new Key("static");

	var member:Key = new Key("field");

	public function new() {}

	static function produce():Key {
		Sys.println("produce");
		return new Key("returned");
	}

	static function returned():String
		return produce();

	static function take(value:String):Void
		Sys.println(value);

	static function main():Void {
		var first:Key = "value";
		var second:Key = "value";
		Sys.println(first == second);
		Sys.println(first.read());
		Sys.println(new Key("value") == first);
		var absent:Key = null;
		Sys.println(absent == null);
		Sys.println(absent.read() == null);
		// Dynamic is intentional here: the observer tests representation erasure
		// at an unchecked boundary, then compares only the known String value.
		var erased:Dynamic = first;
		Sys.println(erased == "value");
		var left = first.read;
		var right = first.read;
		Sys.println(left == right);
		Sys.println(left());
		final cell = new Cell(9);
		var reference:Reference = cell;
		var constructed = new Reference(cell);
		Sys.println(reference == constructed);
		var recovered:Cell = constructed;
		Sys.println(recovered == cell);
		Sys.println(reference.read());
		var input:Input = 7;
		var result:Int = input;
		Sys.println(result);
		Sys.println(conversions);
		Sys.println(returned());
		take(produce());
		Sys.println(initial.read());
		Sys.println(new Main().member.read());
		Sys.println(new Generic<String>("generic").read());
		Sys.println(new Nested(first).read());
		final closure = function():String return first.read();
		Sys.println(closure());
		// This exact unchecked cast must retain the ordinary object, including
		// its independently authored field whose spelling resembles helper storage.
		var ordinary:Dynamic = new Ordinary();
		var untouched:Ordinary = cast ordinary;
		Sys.println(untouched == ordinary);
		Sys.println(untouched.read());
		var early:String = new Early("early", true);
		var normal:String = new Early();
		Sys.println(early);
		Sys.println(normal);
	}
}
