/** Runtime type checks whose Python behavior must match upstream Haxe 4.3.7. */
class Animal {
	public function new() {}
}

class Dog extends Animal {
	public function new() {
		super();
	}
}

class Main {
	static final intIsFloat:Bool = Std.isOfType(1, Float);
	static final animalClass:Class<Animal> = Animal;

	final textIsInt:Bool = Std.isOfType("text", Int);

	function new() {}

	static function show(label:String, value:Bool):Void {
		Sys.println(label + "=" + (value ? "true" : "false"));
	}

	static function main():Void {
		final infinity:Float = 1e308 * 10.0;
		final values:Array<Dynamic> = [
			1,
			2.5,
			3.0,
			-0.0,
			2147483648.0,
			infinity - infinity,
			infinity,
			true,
			"s",
			null,
			[1, 2],
			new Animal(),
			new Dog()
		];
		for (index in 0...values.length) {
			final v:Dynamic = values[index];
			final label = Std.string(index);
			show(label + " Int", Std.isOfType(v, Int));
			show(label + " Float", Std.isOfType(v, Float));
			show(label + " Bool", Std.isOfType(v, Bool));
			show(label + " String", Std.isOfType(v, String));
			show(label + " Dynamic", Std.isOfType(v, Dynamic));
			show(label + " Array", Std.isOfType(v, Array));
			show(label + " Animal", Std.isOfType(v, Animal));
			show(label + " Dog", Std.isOfType(v, Dog));
			show(label + " is Animal", (v is Animal));
			show(label + " is Int", (v is Int));
		}
		show("static initializer", intIsFloat);
		show("instance initializer", new Main().textIsInt);
		show("class value", animalClass == Animal);
	}
}
