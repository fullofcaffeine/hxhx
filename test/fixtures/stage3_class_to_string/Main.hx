class Animal {
	public var name:String;

	public function new(name:String) {
		this.name = name;
	}

	public function toString():String {
		return "animal " + name;
	}
}

class Dog extends Animal {
	public function new(name:String) {
		super(name);
	}

	override public function toString():String {
		return "dog " + name;
	}
}

/** Inherits toString without overriding it. */
class Puppy extends Dog {
	public function new() {
		super("pup");
	}
}

/** A private toString with a block body and an inferred return type. */
class Point {
	var x:Int;
	var y:Int;

	public function new(x:Int, y:Int) {
		this.x = x;
		this.y = y;
	}

	function toString() {
		final label = "point";
		return label + "(" + x + "," + y + ")";
	}
}

/** An inline toString still answers the runtime conversion. */
class InlineLabel {
	public function new() {}

	public inline function toString():String {
		return "inline label";
	}
}

/** Eval calls toString with no arguments, so an optional-only argument is null. */
class OptionalArgument {
	public function new() {}

	public function toString(?suffix:Int):String {
		return "optional " + suffix;
	}
}

/** An omitted argument with a default value takes that default. */
class DefaultArgument {
	public function new() {}

	public function toString(count:Int = 3):String {
		return "default " + count;
	}
}

/** Eval converts whatever toString returns. */
class IntResult {
	public function new() {}

	public function toString():Int {
		return 7;
	}
}

/** A dynamic toString that is never reassigned answers with its declared body. */
class DynamicLabel {
	public function new() {}

	public dynamic function toString():String {
		return "dynamic";
	}
}

class PlainError extends haxe.Exception {
	public function new() {
		super("boom");
	}
}

class LoudError extends haxe.Exception {
	public function new() {
		super("loud");
	}

	override public function toString():String {
		return "LOUD";
	}
}

interface Named {
	function name():String;
}

class Person implements Named {
	public function new() {}

	public function name():String {
		return "ann";
	}

	public function toString():String {
		return "person";
	}
}

/** Shares its name with `pack.Same`. */
class Same {
	public function new() {}

	public function toString():String {
		return "root same";
	}
}

/** No toString: upstream eval prints the class name. */
class Plain {
	var v = 1;

	public function new() {}
}

class Main {
	static function main() {
		final animal = new Animal("cat");
		final dog:Animal = new Dog("rex");
		final puppy = new Puppy();
		final point = new Point(1, 2);
		Sys.println(Std.string(animal));
		Sys.println(Std.string(dog));
		Sys.println(Std.string((new Dog("fido") : Animal)));
		Sys.println(Std.string(puppy));
		Sys.println(Std.string(point));
		Sys.println("concat: " + dog + " / " + point);
		final puppyAnimal:Animal = puppy;
		final animals:Array<Animal> = [animal, dog, puppyAnimal];
		Sys.println(animals.join(", "));
		Sys.println(Std.string(animals));
		Sys.println(animals.toString());
		Sys.println([point, new Point(3, 4)].join(" "));
		final dynamicValue:Dynamic = dog;
		Sys.println(Std.string(dynamicValue));
		Sys.println("dynamic " + dynamicValue);
		final mixed:Array<Dynamic> = [1, point, "s"];
		Sys.println(Std.string(mixed));
		Sys.println(Std.string({pet: puppy}));
		Sys.println(Std.string(new InlineLabel()));
		Sys.println(Std.string(new OptionalArgument()));
		Sys.println(Std.string(new IntResult()) + " " + [new OptionalArgument()].join(","));
		Sys.println(Std.string(new DefaultArgument()) + " " + new DefaultArgument().toString());
		final label = new DynamicLabel();
		Sys.println(Std.string(label));
		Sys.println(label.toString());
		Sys.println(Std.string(new PlainError()));
		Sys.println(Std.string(new LoudError()));
		final named:Named = new Person();
		Sys.println(Std.string(named));
		Sys.println(Std.string(new Same()) + " / " + Std.string(new pack.Same()));
		Sys.println(Std.string(new Plain()));
		Sys.println([new Plain()].join(","));
		final missing:Animal = null;
		Sys.println(Std.string(missing));
	}
}
