class Main {
	static var evaluationOrder = "";

	/** Prints through the native system API or the JavaScript console. */
	static function printLine(value:String):Void {
		#if js
		js.Syntax.code("console.log({0})", value);
		#else
		Sys.println(value);
		#end
	}

	/** Records when a literal element is evaluated, then returns its String value. */
	static function element(label:String, value:String):String {
		evaluationOrder += label;
		return value;
	}

	/** Makes Haxe null slots visible without relying on a target's String conversion. */
	static function render(value:String):String {
		return value == null ? "<null>" : value;
	}

	static function main():Void {
		final values:Array<String> = [element("a", "alpha"), element("b", "beta")];
		final alias = values;
		printLine('dense=$evaluationOrder:${values.length}:${render(values[0])}:${render(values[1])}:${values == alias}');

		values[1] = null;
		printLine('null=${values.length}:${render(values[1])}:${values[-1] == null}:${values[9] == null}');

		values[4] = "epsilon";
		printLine('sparse=${values.length}:${render(values[2])}:${render(values[3])}:${render(values[4])}');

		values[1] = "beta2";
		values[2] = "gamma";
		printLine('refill=${values.length}:${render(values[1])}:${render(values[2])}');

		values.resize(7);
		printLine('grow=${values.length}:${render(values[5])}:${render(values[6])}');

		values.resize(3);
		alias[0] = "ALPHA";
		printLine('shrink=${values.length}:${render(values[0])}:${render(values[1])}:${render(values[2])}:${values == alias}');
	}
}
