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
		Sys.println(Std.string(new Plain()));
		Sys.println([new Plain()].join(","));
		final missing:Animal = null;
		Sys.println(Std.string(missing));
	}
}
