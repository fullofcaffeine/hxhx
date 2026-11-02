/**
	Static initializers that reach later helper methods through first-class
	method values instead of direct calls.
 */
class Main {
	/** Built by a helper that passes another static method to `map`. */
	static final table:String = build();

	/** Captures a static method directly in the initializer. */
	static final exclaim:String->String = bang;

	/** Captures a helper that is only reachable through another captured value. */
	static final nested:String = wrap(["c", "d"]);

	static function build():String {
		return ["a", "b"].map(shout).join(",");
	}

	static function shout(v:String):String {
		return v.toUpperCase();
	}

	static function bang(v:String):String {
		return v + "!";
	}

	static function wrap(values:Array<String>):String {
		final apply = quote;
		return values.map(apply).join(" ");
	}

	static function quote(v:String):String {
		return "[" + shout(v) + "]";
	}

	static function main():Void {
		Sys.println(table);
		Sys.println(exclaim("hi"));
		Sys.println(nested);
	}
}
