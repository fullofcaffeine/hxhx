/** Exercise reference comparisons independently of the syntax that produces each instance. */
class Main {
	public var length:Int;
	public var child:Main;

	public function new(length:Int) {
		this.length = length;
		child = this;
	}

	public function self():Main
		return this;

	static function observed(label:String, value:Main):Main {
		Sys.println(label);
		return value;
	}

	static function main() {
		var a = new Main(3);
		var b = new Main(3);
		var alias = a;
		if (a == b || a != alias || a.self() != a || new Main(3) == new Main(3) || a.child != a)
			throw "class reference equality changed";
		var absent:Null<Main> = null;
		if (a == absent || absent != null)
			throw "nullable class comparison changed";
		Sys.println(observed("left", a) == observed("right", b));
		Sys.println(observed("read", a).length);
		var text = "abc";
		var values = [3, 7];
		Sys.println(text.length);
		Sys.println(values.length);
		if ("a" + "b" != "ab" || 3 != 3 || true != true)
			throw "primitive equality changed";
	}
}
