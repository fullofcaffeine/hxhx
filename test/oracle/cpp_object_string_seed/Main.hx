/** Observe standard conversion effects and returned null independently of the candidate. */
class Main {
	public static var calls:Int = 0;

	static function show(label:String, value:Dynamic):Void {
		final text = Std.string(value);
		Sys.println(label + ":" + (text == null ? "<null>" : text));
	}

	static function make():Custom {
		calls++;
		return new Custom("factory");
	}

	static function main():Void {
		show("null", null);
		show("plain", new Plain());
		show("custom", new Custom("direct"));
		show("inherited", new Inherited("inherited"));
		final base:Custom = new Overridden("override");
		show("override", base);
		show("factory", make());
		show("null-result", new NullResult());
		try {
			show("throw-result", new ThrowResult());
		} catch (value:String) {
			Sys.println("caught:" + value);
		}
		show("record", {b: "text", a: 1});
		show("record-method", {toString: () -> "record result", other: 1});
		show("array", ["a", null, "b"]);
		show("generic-int", new Generic(3));
		show("generic-string", new Generic("text"));
		show("exception", new haxe.ValueException("wrapped"));
		show("nested-exception", new haxe.ValueException(new haxe.ValueException("nested")));
		Sys.println("calls:" + calls);
	}
}

class Plain {
	public function new() {}
}

class Custom {
	final label:String;

	public function new(label:String) {
		this.label = label;
	}

	public function toString():String {
		Main.calls++;
		return label;
	}
}

class Inherited extends Custom {
	public function new(label:String) {
		super(label);
	}
}

class Overridden extends Custom {
	public function new(label:String) {
		super(label);
	}

	override public function toString():String {
		Main.calls++;
		return "child:" + super.toString();
	}
}

class NullResult {
	public function new() {}

	public function toString():String {
		Main.calls++;
		return null;
	}
}

class ThrowResult {
	public function new() {}

	public function toString():String {
		Main.calls++;
		throw "conversion failed";
	}
}

class Generic<T> {
	final value:T;

	public function new(value:T) {
		this.value = value;
	}

	public function toString():String {
		return "[" + Std.string(value) + "]";
	}
}
