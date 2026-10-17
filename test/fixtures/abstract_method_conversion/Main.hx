/** A generic source value whose concrete argument can come from the conversion result. */
class Cell<T> {
	public var value:Null<T>;

	public function new() {
		value = null;
	}

	public function read():Null<T> {
		return this.value;
	}
}

/** The conversion has an observable effect and must execute as a real method call. */
abstract Tagged<T>(Cell<T>) {
	public function new(value:Cell<T>) {
		this = value;
	}

	@:from static function convert<U>(value:Cell<U>):Tagged<U> {
		Sys.println("convert");
		return new Tagged(value);
	}

	public function isEmpty():Bool {
		return this.value == null;
	}

	public function reader():Void->Null<T> {
		return () -> this.value;
	}
}

/** A method may change representation; its computation cannot be replaced with a cast. */
abstract Size(Int) {
	public function new(value:Int) {
		this = value;
	}

	@:from static function measure(value:String):Size {
		Sys.println("measure");
		return new Size(value == "abcd" ? 4 : 0);
	}

	public function value():Int {
		return this;
	}
}

/** Compare inferred and explicit returns with a written local initialized by an effectful operand. */
class Main {
	static function inferred():Tagged<String> {
		final result = new Cell();
		return result;
	}

	static function explicit():Tagged<String> {
		final result = new Cell<String>();
		return result;
	}

	static function operand():Cell<String> {
		Sys.println("operand");
		return new Cell();
	}

	static function main():Void {
		Sys.println(inferred().isEmpty());
		Sys.println(explicit().isEmpty());
		final local:Tagged<String> = operand();
		Sys.println(local.isEmpty());
		final cell = new Cell<String>();
		cell.value = "payload";
		final populated:Tagged<String> = cell;
		Sys.println(populated.isEmpty());
		final read = populated.reader();
		Sys.println(read());
		cell.value = "changed";
		Sys.println(read());
		Sys.println(cell.read());
		final measured:Size = "abcd";
		Sys.println(measured.value());
	}
}
