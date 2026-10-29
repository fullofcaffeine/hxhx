/** A custom multi-type abstract chooses a provider from its resolved type argument. */
interface Storage<T> {
	public function label():String;
}

class TextStorage implements Storage<String> {
	public function new() {}

	public function label():String
		return "text";
}

class NumberStorage implements Storage<Int> {
	public function new() {}

	public function label():String
		return "number";
}

@:multiType(@:followWithAbstracts T)
@:probe("spaced (value)", [1, 2])
@:probe("second")
abstract Choice<T>(Storage<T>) {
	public function new();

	public inline function label():String
		return this.label();

	public inline function description():String
		return "[" + this.label() + "]";

	@:to static inline function text<T:String>(unused:Storage<T>):TextStorage
		return new TextStorage();

	@:to static inline function number<T:Int>(unused:Storage<T>):NumberStorage
		return new NumberStorage();
}

class Main {
	static function main():Void {
		final text = new Choice<String>();
		final number = new Choice<Int>();
		if (text.label() != "text" || number.label() != "number")
			throw "provider selection";
		if (text.description() != "[text]" || number.description() != "[number]")
			throw "abstract method body";
	}
}
