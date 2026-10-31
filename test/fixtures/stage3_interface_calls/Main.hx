import shapes.Shape;

interface Named {
	function name():String;
}

interface Greeter extends Named {
	function greet(other:String):String;
}

interface Box<T> {
	function get():T;
	function put(value:T):Void;
}

interface Store<T> extends Box<T> {
	function size():Int;
}

interface Check {
	function test(value:Int, strict:Bool):Bool;
}

class Person implements Named {
	final first:String;

	public function new(first:String)
		this.first = first;

	public function name():String
		return first;
}

// Overrides the implementation it inherits from Person.
class Teacher extends Person {
	public function new(first:String)
		super(first);

	override public function name():String
		return "teacher " + first;
}

// Inherits Person's implementation without overriding it.
class Student extends Person {
	public function new(first:String)
		super(first);
}

class Base {
	public function new() {}

	public function name():String
		return "base";
}

// Implements Named only through a method inherited from Base.
class Child extends Base implements Named {
	public function new()
		super();
}

class Host implements Greeter {
	public function new() {}

	public function name():String
		return "host";

	public function greet(other:String):String
		return "hi " + other + " from " + introduce(this);

	// An interface call inside an implementing class, on its own instance.
	static function introduce(self:Named):String
		return self.name();
}

class IntCell implements Box<Int> {
	var value = 0;

	public function new() {}

	public function get():Int
		return value;

	public function put(value:Int):Void
		this.value = value;
}

class FloatCell implements Box<Float> {
	var value = 0.5;

	public function new() {}

	public function get():Float
		return value;

	public function put(value:Float):Void
		this.value = value;
}

class ListStore<T> implements Store<T> {
	final items:Array<T> = [];

	public function new() {}

	public function get():T
		return items[items.length - 1];

	public function put(value:T):Void
		items.push(value);

	public function size():Int
		return items.length;
}

class Pair {
	public var left:Named;
	public final right:Named;

	public function new(left:Named, right:Named) {
		this.left = left;
		this.right = right;
	}
}

class Range implements Check {
	public function new() {}

	public function test(value:Int, strict:Bool):Bool {
		if (strict)
			return value > 0 && value < 10;
		return value >= 0 && value <= 10;
	}
}

class Log {
	public final buffer = new StringBuf();

	public function new() {}

	public function write(text:String):Void
		buffer.add(text);
}

class Main {
	static final everyone:Array<Named> = people();
	static final current:Named = new Person("dee");

	static function people():Array<Named> {
		final result = new Array<Named>();
		result.push(new Person("ann"));
		result.push(new Teacher("bob"));
		result.push(new Student("cy"));
		result.push(new Child());
		result.push(new Host());
		return result;
	}

	static function spelled(text:String):StringBuf {
		final result = new StringBuf();
		result.add(text);
		return result;
	}

	static function describe(named:Named):String
		return "<" + named.name() + ">";

	// A generic interface reached through a parameter with a concrete type argument.
	static function fillInt(box:Box<Int>, value:Int):Int {
		box.put(value);
		return box.get();
	}

	static function fillString(box:Box<String>, value:String):String {
		box.put(value);
		return box.get();
	}

	static function main() {
		final p:Named = new Person("ann");
		Sys.println("raw " + p.name());
		Sys.println(p.name().toUpperCase());
		Sys.println(p.name().length);

		for (named in everyone)
			Sys.println(describe(named));
		Sys.println("static " + current.name());
		final pair = new Pair(new Teacher("eve"), new Student("fay"));
		Sys.println("field " + pair.left.name() + " " + pair.right.name());
		pair.left = new Child();
		Sys.println("field " + pair.left.name());
		Sys.println("index " + everyone[1].name().toUpperCase());

		final g:Greeter = new Host();
		Sys.println(g.name() + " / " + g.greet("bob"));
		final asNamed:Named = g;
		Sys.println(asNamed.name());

		final ints:Box<Int> = new IntCell();
		ints.put(41);
		Sys.println(ints.get() + 1);
		Sys.println(fillInt(ints, 7) * 3);
		final floats:Box<Float> = new FloatCell();
		Sys.println(Std.string(floats.get()));
		floats.put(1.25);
		Sys.println(Std.string(floats.get()));

		final store:Store<String> = new ListStore<String>();
		store.put("x");
		store.put("y");
		Sys.println(store.get().toUpperCase());
		Sys.println(store.size());
		final asBox:Box<String> = store;
		Sys.println(fillString(asBox, "z"));
		Sys.println(store.size());

		final check:Check = new Range();
		Sys.println(check.test(5, true) + " " + check.test(10, true) + " " + check.test(10, false));

		final shape:Shape = new Square(3);
		Sys.println(shape.label());
		Sys.println(Std.string(shape.area(1.5)));

		final read = p.name;
		final readGreeting = g.greet;
		Sys.println(read() + " " + readGreeting("cat"));

		// StringBuf.toString on a local, a field, and a call result.
		final buffer = new StringBuf();
		buffer.add("abc");
		Sys.println(buffer.toString().toUpperCase());
		final log = new Log();
		log.write("def");
		Sys.println(log.buffer.toString().toUpperCase());
		Sys.println(spelled("ghi").toString().toUpperCase());
	}
}
