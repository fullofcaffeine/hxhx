/** Observe native condition reads independently of numeric formatting or arithmetic. */
class Main {
	static function observe(value:Dynamic):Void {
		Sys.println(if (value) 1 else 0);
		Sys.println(switch 1 {
			case 1 if (value): 1;
			case _: 0;
		});
	}

	static function main():Void {
		observe(null);
		observe(false);
		observe(true);
		observe(0);
		observe(1);
		observe(-1);
		observe("");
		observe("false");
		observe("true");
		observe([]);
		observe({});
		observe(() -> 1);
	}
}
