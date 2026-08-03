private typedef Location = {
	var file:String;
	var line:Int;
}

class Main {
	static final events:Array<String> = [];

	/** Writes the same observable line on stock JavaScript and system targets. */
	static function printLine(value:String):Void {
		#if js
		js.Syntax.code("console.log({0})", value);
		#else
		Sys.println(value);
		#end
	}

	/**
		Returns either Haxe `null` or one mutable anonymous object.

		The label makes exactly-once evaluation visible. The caller later mutates an
		alias so every target must also preserve the returned object's shared identity.
	**/
	static function choose(label:String, present:Bool):Null<Location> {
		events.push(label);
		if (!present)
			return null;
		return {file: "src/Main.hx", line: 42};
	}

	static function main():Void {
		final missing = choose("missing", false);
		final found = choose("present", true);
		printLine("missing=" + Std.string(missing == null));
		if (found == null) {
			printLine("found=null");
		} else {
			printLine('found=${found.file}:${found.line}');
			final alias = found;
			alias.line = 43;
			printLine('alias=${found.line}');
		}
		printLine("events=" + events.join(","));
	}
}
