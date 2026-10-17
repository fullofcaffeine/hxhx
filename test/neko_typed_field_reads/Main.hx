/** An explicitly Void constructor initializes a field without returning the allocated object from its body. */
class ValueHolder {
	public var value:String;

	public function new(value:String):Void {
		this.value = value;
	}
}

/** Observes ordinary field access and null failures through typed Haxe expressions. */
class Main {
	static function main():Void {
		var present = new ValueHolder("present");
		Sys.println(present.value);
		var missing:ValueHolder = null;
		var result = try {
			missing.value;
		} catch (error:Dynamic) {
			"NPE";
		};
		Sys.println(result);
		Sys.println(present.value);
	}
}
