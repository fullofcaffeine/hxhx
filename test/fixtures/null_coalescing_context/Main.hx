/** Fallbacks inherit collection/callable context and execute only for a null left operand. */
class Main {
	static var attempts:Int = 0;

	static function fallback():Map<String, Int> {
		attempts++;
		return ["fallback" => 2];
	}

	static function main():Void {
		var initial = ["retained" => 1];
		var absent:Map<String, Int> = null;
		var first = initial ?? fallback();
		if (attempts != 0 || first.get("retained") != 1)
			throw "eager fallback";
		var next = absent ?? fallback();
		if (attempts != 1 || next.get("fallback") != 2)
			throw "fallback count";
		var empty = absent ?? [];
		empty["new"] = 7;
		if (empty.get("new") != 7)
			throw "empty Map context";
		var copied = initial.copy() ?? [];
		copied["new"] = 9;
		if (initial.exists("new") || copied.get("retained") != 1)
			throw "Map copy ownership";
		var input:Null<Array<String>> = null;
		var values = input ?? [];
		values.push("ok");
		if (values[0] != "ok")
			throw "empty Array context";
		var callback:Null<(Int) -> Int> = null;
		var selected = callback ?? (value -> value + 1);
		if (selected(2) != 3)
			throw "callback input context";
	}
}
