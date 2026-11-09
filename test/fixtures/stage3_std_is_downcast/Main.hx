/**
	Runs the class type tests and downcasts that Stage3 supports, through
	`Std.isOfType`, `(value is T)`, `Std.downcast`, and the deprecated `Std.is`
	and `Std.instance`. Operands are typed as the class, a superclass, an interface,
	`Dynamic`, and `Any`, and include `null`, primitives, an anonymous object,
	and an array. Each operand that comes from `observed` logs once, so the
	output also shows that every operand runs exactly once.
**/
interface Shape {
	function name():String;
}

/** An interface that extends another interface. */
interface Polygon extends Shape {}

class Base implements Shape {
	public var label:String;

	public function new()
		label = "base";

	public function name():String
		return "base";
}

class Square extends Base implements Polygon {
	public function new() {
		super();
		label = "square";
	}

	override public function name():String
		return "square";
}

/** A subclass of a subclass, which implements both interfaces through its parents. */
class Tile extends Square {
	public function new() {
		super();
		label = "tile";
	}

	override public function name():String
		return "tile";
}

class Other {
	public function new() {}
}

class Main {
	static var staticCheck:Bool = Std.is(new Tile(), Polygon);
	static var log:Array<String> = [];

	static function observed(label:String, value:Shape):Shape {
		log.push(label);
		return value;
	}

	/**
		Reads a plain field, not the overridden `name()`, so the output does not
		depend on virtual dispatch through a `Base`-typed value.
	**/
	static function describe(value:Null<Base>):String
		return value == null ? "null" : value.label;

	/** Prints a Bool through a branch, independent of Bool-to-String conversion. */
	static function show(flag:Bool):String
		return flag ? "true" : "false";

	static function main():Void {
		final base:Base = new Base();
		final square:Base = new Square();
		final tile:Shape = new Tile();
		final dynamicSquare:Dynamic = new Square();
		final anyTile:Any = new Tile();
		final other:Dynamic = new Other();
		final nothing:Dynamic = null;
		final anonymous:Dynamic = {name: "anon"};
		final numbers:Dynamic = [1, 2];

		Sys.println("static " + show(staticCheck));
		Sys.println("is " + Std.is(base, Square) + " " + Std.is(square, Square) + " " + Std.is(square, Tile) + " " + Std.is(tile, Square));
		Sys.println("is-interface "
			+ Std.is(base, Shape)
			+ " "
			+ Std.is(base, Polygon)
			+ " "
			+ Std.is(square, Polygon)
			+ " "
			+ Std.is(dynamicSquare, Shape));
		Sys.println("is-other "
			+ Std.is(other, Base)
			+ " "
			+ Std.is(nothing, Base)
			+ " "
			+ Std.is(anonymous, Shape)
			+ " "
			+ Std.is(numbers, Base));
		Sys.println("is-primitive " + Std.is(1, Base) + " " + Std.is("text", Base) + " " + Std.is(true, Shape) + " " + Std.is(2.5, Base));
		Sys.println("is-array " + Std.is(numbers, Array) + " " + Std.is(square, Array) + " " + Std.is(nothing, Array));
		Sys.println("isOfType " + Std.isOfType(anyTile, Tile) + " " + Std.isOfType(anyTile, Polygon) + " " + Std.isOfType(base, Tile));
		Sys.println("operator " + show(square is Square) + " " + show(tile is Base) + " " + show(base is Polygon) + " " + show(nothing is Base) + " "
			+ show(other is Shape));

		Sys.println("downcast " + describe(Std.downcast(square, Square)) + " " + describe(Std.downcast(base, Square)) + " "
			+ describe(Std.downcast(tile, Tile)) + " " + describe(Std.downcast(tile, Base)));
		final narrowed:Null<Square> = Std.downcast(square, Square);
		Sys.println("narrowed " + (narrowed == null ? "null" : narrowed.name() + " " + show(narrowed == square)));
		final missing:Null<Tile> = Std.downcast(square, Tile);
		Sys.println("missing " + show(missing == null));
		Sys.println("downcast-null " + show(Std.downcast((null : Base), Square) == null));
		final squareShape:Shape = new Square();
		final baseShape:Shape = base;
		final asShape:Null<Polygon> = Std.downcast(squareShape, Polygon);
		Sys.println("downcast-interface "
			+ (asShape == null ? "null" : asShape.name())
			+ " "
			+ show(Std.downcast(baseShape, Polygon) == null));
		Sys.println("downcast-dynamic " + describe(Std.downcast(dynamicSquare, Square)) + " " + describe(Std.downcast(other, Base)) + " "
			+ describe(Std.downcast(anyTile, Tile)) + " " + describe(Std.downcast(nothing, Square)));
		Sys.println("instance " + describe(Std.instance(tile, Square)) + " " + describe(Std.instance(base, Tile)));

		final checked = Std.is(observed("is", square), Square);
		final cast1 = Std.downcast(observed("downcast", base), Square);
		final cast2 = Std.downcast(observed("downcast-hit", tile), Base);
		Sys.println("order " + show(checked) + " " + describe(cast1) + " " + describe(cast2) + " " + log.join(","));
	}
}
