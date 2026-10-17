/** Exercise bounds and effects independently of the compiler's runtime adapters. */
class Main {
	static final initial = "abcabc".substr(2);

	static function text():String {
		Sys.print("r");
		return "abcabc";
	}

	static function array():Array<Int> {
		Sys.print("r");
		return [1, 2, 1, 3];
	}

	static function needle():String {
		Sys.print("a");
		return "a";
	}

	static function value():Int {
		Sys.print("a");
		return 1;
	}

	static function bound():Null<Int> {
		Sys.print("b");
		return null;
	}

	static function expect(ok:Bool):Void {
		if (!ok)
			throw "bounds mismatch";
	}

	static function main():Void {
		expect(initial == "cabc");
		var s = "abcabc";
		var a = [1, 2, 1, 3];
		var booleans = [false, true, false];
		var erased:Array<Dynamic> = [false, true, false];
		expect(booleans.indexOf(true) == 1 && booleans.lastIndexOf(false, null) == 2);
		expect(erased.indexOf(true) == 1 && erased.lastIndexOf(false, null) == 2);
		expect(s.indexOf("a") == 0 && s.indexOf("a", null) == 0 && s.indexOf("a", 0) == 0 && s.indexOf("a", 2) == 3);
		expect(s.lastIndexOf("a") == 3 && s.lastIndexOf("a", null) == 3 && s.lastIndexOf("a", 0) == 0 && s.lastIndexOf("a", 2) == 0);
		expect(s.substr(2) == "cabc" && s.substr(2, null) == "cabc" && s.substr(2, 0) == "" && s.substr(-2) == "bc");
		expect(s.substring(2) == "cabc" && s.substring(2, null) == "cabc" && s.substring(2, 0) == "ab" && s.substring(-2, 3) == "abc");
		expect(a.indexOf(1) == 0 && a.indexOf(1, null) == 0 && a.indexOf(1, 0) == 0 && a.indexOf(1, -2) == 2);
		expect(a.lastIndexOf(1) == 2 && a.lastIndexOf(1, null) == 2 && a.lastIndexOf(1, 0) == 0 && a.lastIndexOf(1, -2) == 2);
		expect(text().indexOf(needle(), bound()) == 0);
		expect(array().lastIndexOf(value(), bound()) == 2);
		expect(text().lastIndexOf(needle()) == 3);
		expect(array().indexOf(value()) == 0);
		expect(new Search().indexOf("a", null) == 42);
		Sys.println("bounds:ok");
	}
}

/** A user method with the same spelling must keep its selected declaration. */
class Search {
	public function new() {}

	public function indexOf(value:String, ?start:Int):Int {
		return 42;
	}
}
