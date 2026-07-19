/** Focused executable proof for value-producing exact-Int array assignment. */
class Main {
	static final events:Array<String> = [];
	static final values:Array<Int> = [10, 20];

	static function receiver():Array<Int> {
		events.push("array");
		return values;
	}

	static function index():Int {
		events.push("index");
		return 1;
	}

	static function rhs():Int {
		events.push("rhs");
		return 7;
	}

	static function main():Void {
		final result = receiver()[index()] = rhs();
		Sys.println("result=" + result + " final=" + values[1] + " events=" + events.join(","));

		final vector = new haxe.ds.Vector<Int>(1);
		final vectorResult = vector[0] = 5;
		Sys.println("vector=" + vectorResult + " final=" + vector[0]);
	}
}
