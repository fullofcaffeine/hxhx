/** Source behavior shared by the upstream observer and fresh hxhx JavaScript generation. */
class Main {
	static var events:Array<String> = [];
	static var values:Array<Int> = [2];

	var delta:Int = 3;

	public function new() {}

	static function receiver():Array<Int> {
		events.push("receiver");
		return values;
	}

	static function index():Int {
		events.push("index");
		return 0;
	}

	static function right():Int {
		events.push("right");
		values[0] = 100;
		return 3;
	}

	static function fail():Int {
		events.push("throw");
		throw "stop";
	}

	static function fallback():Int {
		events.push("fallback");
		return 9;
	}

	function lexical():Void {
		var __hx_value = 4;
		var items = [2];
		final result = (items[0] += this.delta + __hx_value);
		Sys.println("lexical:" + result + ":" + items[0]);
	}

	static function main():Void {
		final result = (receiver()[index()] += right());
		Sys.println("compound:" + result + ":" + values[0] + ":" + events.join(","));
		events = new Array<String>();
		values = [2];
		try {
			receiver()[index()] += fail();
		} catch (_:String) {}
		Sys.println("throw:" + values[0] + ":" + events.join(","));
		events = new Array<String>();
		var nullable:Array<Null<Int>> = [4, null];
		final present = (nullable[0] ??= fallback());
		final absent = (nullable[1] ??= fallback());
		Sys.println("coalesce:" + present + ":" + absent + ":" + nullable.join(",") + ":" + events.join(","));
		new Main().lexical();
	}
}
