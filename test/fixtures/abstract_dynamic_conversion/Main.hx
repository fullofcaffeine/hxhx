/** Ordinary storage stays a class while the authored conversion chooses an opaque value. */
class Cell {
	public var value:Int;

	public function new(value:Int)
		this.value = value;
}

/** Conversion effects expose skipped calls, repeated operands, and wrong boundary ordering. */
abstract Wrapped(Cell) {
	public function new(value:Int)
		this = new Cell(value);

	public function read():Int
		return this.value;

	@:to public function erase():Dynamic {
		Sys.println("erase");
		return this.value;
	}

	@:from public static function recover(value:Dynamic):Wrapped {
		Sys.println("recover");
		return new Wrapped(Std.int(value));
	}
}

/** Each source operand and conversion must execute once at its written value boundary. */
class Main {
	static var stored:Dynamic;

	static function operand(value:Int):Wrapped {
		Sys.println("operand");
		return new Wrapped(value);
	}

	static function returned():Dynamic
		return operand(4);

	static function accept(value:Dynamic):Void
		Sys.println(value);

	static function main():Void {
		var value:Dynamic = operand(1);
		Sys.println(value);
		value = operand(2);
		Sys.println(value);
		accept(operand(3));
		Sys.println(returned());
		stored = operand(5);
		Sys.println(stored);
		final restored:Wrapped = value;
		Sys.println(restored.read());
	}
}
