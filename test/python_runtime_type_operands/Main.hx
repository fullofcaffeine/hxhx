/** Runtime type checks whose Python behavior must match upstream Haxe 4.3.7. */
class Animal {
	public function new() {}
}

class Dog extends Animal {
	public function new() {
		super();
	}
}

class Checks {
	public static inline function isDogOrInt(v:Dynamic):Bool
		return Std.isOfType(v, Dog) || Std.isOfType(v, Int);

	public static function same(c:Dynamic):Dynamic
		return c;
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
		final classes:Array<Dynamic> = [Animal, Dog];
		show("class value passed", Checks.same(Dog) == classes[1] && Checks.same(Animal) != Dog);
		show("inline Dog", Checks.isDogOrInt(new Dog()));
		show("inline Int", Checks.isDogOrInt(7));
		show("inline String", Checks.isDogOrInt("7"));
		final closure = function(x:Dynamic) return Std.isOfType(x, Animal) && (x is Dog);
		final arrow = (x:Dynamic) -> x is String;
		show("closure Dog", closure(new Dog()));
		show("closure Animal", closure(new Animal()));
		show("arrow String", arrow("a"));
		show("arrow Int", arrow(1));
		Sys.println("class name " + Type.getClassName(Dog));
		final named:Class<Dynamic> = Animal;
		Sys.println("class name through value " + Type.getClassName(named));
		final callback = () -> 1;
		show("getClass instance", Type.getClass(new Dog()) == Dog);
		show("getClass class object", Type.getClass(Dog) == null);
		show("getClass anonymous", Type.getClass({a: 1}) == null);
		show("getClass string", Type.getClass("s") == null);
		show("getClass null", Type.getClass(null) == null);
		show("isObject class", Reflect.isObject(Dog));
		show("isObject instance", Reflect.isObject(new Animal()));
		show("isObject anonymous", Reflect.isObject({a: 1}));
		show("isObject string", Reflect.isObject("s"));
		show("isObject number", Reflect.isObject(1));
		show("isObject function", Reflect.isObject(callback));
		show("isObject null", Reflect.isObject(null));
		Sys.println("class name packaged " + Type.getClassName(zoo.Cat));
		Sys.println("class name nested " + Type.getClassName(zoo.deep.Owl));
		Sys.println("class name sub-type " + Type.getClassName(zoo.deep.Owl.Nest));
		Sys.println("class name reserved " + Type.getClassName(zoo.deep.Owl.None));
		Sys.println("class name of instance " + Type.getClassName(Type.getClass(new zoo.deep.Owl())));
		Sys.println("class name of top-level instance " + Type.getClassName(Type.getClass(new Dog())));
		Sys.println("class name of string " + Type.getClassName(Type.getClass("s")));
		show("packaged is", Std.isOfType(new zoo.Cat(), zoo.Cat));
	}
}
