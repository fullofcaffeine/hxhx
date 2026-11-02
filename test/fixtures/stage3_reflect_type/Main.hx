import Reflect.fields as reflectFields;

using Type;

/**
	Runs the `Reflect` and `Type` calls that Stage3 routes to its runtime, on
	anonymous objects and class instances, and prints each result. The native
	executable must print exactly what upstream Haxe 4.3.7 prints.
**/
enum Color {
	Red;
	Rgb(r:Int, g:Int, b:Int);
}

class Point {
	public var x:Int;
	public var y:Int;
	public var label:Null<String>;

	public function new(x:Int, y:Int) {
		this.x = x;
		this.y = y;
	}

	public function sum():Int
		return x * 10;

	public function scaled(factor:Int):Int
		return y * factor;
}

class Point3 extends Point {
	public var z:Int;

	public function new(x:Int, y:Int, z:Int) {
		super(x, y);
		this.z = z;
	}

	override public function sum():Int
		return z * 100;
}

/** A property whose reads and writes go through accessor methods. */
class Box {
	public var size(get, set):Int;

	var stored:Int = 2;

	public function new() {}

	function get_size():Int
		return stored * 3;

	function set_size(value:Int):Int {
		stored = value;
		return value;
	}
}

class Main {
	static function sorted(names:Array<String>):String {
		final copy = names.copy();
		copy.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		return copy.join(",");
	}

	static function describe(value:Dynamic):String {
		return switch (Type.typeof(value)) {
			case TNull: "TNull";
			case TInt: "TInt";
			case TFloat: "TFloat";
			case TBool: "TBool";
			case TObject: "TObject";
			case TFunction: "TFunction";
			case TClass(c): "TClass " + Type.getClassName(c);
			case TEnum(e): "TEnum " + Type.getEnumName(e);
			case TUnknown: "TUnknown";
		};
	}

	static function main() {
		final anon:Dynamic = {a: 1, b: "two"};
		final point = new Point(3, 4);
		final point3 = new Point3(1, 2, 5);
		final increment = (v:Int) -> v + 1;
		final flag = true;

		Sys.println("hasField anon " + Reflect.hasField(anon, "a") + " " + Reflect.hasField(anon, "missing"));
		// Haxe guarantees hasField only for stored fields; method names differ by target.
		Sys.println("hasField class " + Reflect.hasField(point, "x") + " " + Reflect.hasField(point, "label") + " " + Reflect.hasField(point3, "y") + " "
			+ Reflect.hasField(point, "missing"));
		Sys.println("isFunction " + Reflect.isFunction(anon) + " " + Reflect.isFunction(increment) + " " + Reflect.isFunction(1));
		Sys.println("field anon " + Reflect.field(anon, "a") + " " + Reflect.field(anon, "b") + " " + Reflect.field(anon, "missing"));
		Sys.println("field class " + Reflect.field(point, "x") + " " + Reflect.field(point3, "z") + " " + Reflect.field(point3, "x") + " "
			+ Reflect.field(point, "label"));
		Reflect.setField(anon, "c", 3);
		Reflect.setField(anon, "flag", flag);
		Reflect.setField(point, "y", 40);
		Sys.println("setField " + Reflect.field(anon, "c") + " " + Reflect.field(anon, "flag") + " " + point.y);
		Sys.println("getProperty " + Reflect.getProperty(anon, "b") + " " + Reflect.getProperty(point, "x"));
		Reflect.setProperty(point, "x", 30);
		Reflect.setProperty(anon, "d", "dee");
		Sys.println("setProperty " + point.x + " " + Reflect.field(anon, "d"));
		Sys.println("fields anon " + sorted(Reflect.fields(anon)));
		Sys.println("fields class " + sorted(Reflect.fields(point3)));
		// Separate statements fix the order of these effects; native string
		// concatenation does not yet evaluate its operands left to right.
		final deleted = Reflect.deleteField(anon, "c");
		final deletedAgain = Reflect.deleteField(anon, "c");
		Sys.println("deleteField "
			+ deleted
			+ " "
			+ deletedAgain
			+ " "
			+ Reflect.hasField(anon, "c")
			+ " "
			+ Reflect.deleteField(point, "x"));
		Sys.println("isObject "
			+ Reflect.isObject(anon)
			+ " "
			+ Reflect.isObject(point)
			+ " "
			+ Reflect.isObject(1)
			+ " "
			+ Reflect.isObject("text"));
		Sys.println("isEnumValue " + Reflect.isEnumValue(Red) + " " + Reflect.isEnumValue(point));
		Sys.println("compare " + Reflect.compare(1, 2) + " " + Reflect.compare("b", "a") + " " + Reflect.compare(3, 3));
		final args:Array<Dynamic> = [41];
		final callee:Dynamic = increment;
		Sys.println("callMethod " + Reflect.callMethod(null, callee, args));
		final copied:Dynamic = Reflect.copy(anon);
		Reflect.setField(copied, "a", 100);
		Sys.println("copy " + Reflect.field(copied, "a") + " " + Reflect.field(anon, "a"));

		Sys.println("typeof anon " + Type.typeof(anon));
		Sys.println("typeof int " + Type.typeof(1) + " float " + Type.typeof(1.5) + " bool " + Type.typeof(flag));
		Sys.println("typeof null " + Type.typeof(null) + " function " + Type.typeof(increment));
		Sys.println("typeof class " + Type.typeof(point) + " enum " + Type.typeof(Rgb(1, 2, 3)) + " string " + Type.typeof("text"));
		Sys.println("enum value " + Rgb(1, 2, 3) + " " + Red);
		Sys.println("describe " + describe(point) + "; " + describe(point3) + "; " + describe("text") + "; " + describe([1, 2]));
		Sys.println("describe " + describe(Rgb(1, 2, 3)) + "; " + describe(anon) + "; " + describe(false) + "; " + describe(null));
		Sys.println("getClassName " + Type.getClassName(Type.getClass(point3)) + " " + (Type.getClass(anon) == null));
		Sys.println("getSuperClass "
			+ Type.getClassName(Type.getSuperClass(Type.getClass(point3)))
			+ " "
			+ (Type.getSuperClass(Type.getClass(point)) == null));
		Sys.println("getInstanceFields " + sorted(Type.getInstanceFields(Type.getClass(point3))));
		final sum:Dynamic = Reflect.field(point, "sum");
		final scaled:Dynamic = Reflect.field(point, "scaled");
		Sys.println("method field "
			+ Reflect.isFunction(sum)
			+ " "
			+ Reflect.callMethod(point, sum, [])
			+ " "
			+ Reflect.callMethod(point, scaled, [args[0]]));
		Sys.println("override field "
			+ Reflect.callMethod(point3, Reflect.field(point3, "sum"), [])
			+ " "
			+ sorted(Type.getInstanceFields(Type.getClass(point3))));
		final box = new Box();
		Sys.println("accessor " + Reflect.getProperty(box, "size") + " " + Reflect.field(box, "size"));
		Reflect.setProperty(box, "size", 7);
		Sys.println("accessor set " + box.size + " " + Reflect.field(box, "stored"));
		final copiedPoint:Dynamic = Reflect.copy(point);
		Sys.println("copy class " + Type.getClassName(Type.getClass(copiedPoint)) + " " + Reflect.field(copiedPoint, "x"));
		Sys.println("null " + Reflect.field(null, "x") + " " + (Type.getClass(null) == null) + " " + Reflect.hasField(null, "x"));
		final read = Reflect.field;
		final write = Reflect.setField;
		write(anon, "w", 5);
		Sys.println("method value " + read(anon, "w") + " " + read(point, "x"));
		Sys.println("static import " + sorted(reflectFields(point3)));
		Sys.println("using " + point3.getClass().getClassName() + " " + Red.enumIndex());
		Sys.println("enumIndex " + Type.enumIndex(Red) + " " + Type.enumIndex(Rgb(1, 2, 3)));
	}
}
