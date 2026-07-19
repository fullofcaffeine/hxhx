/** Focused executable proof for exact-Int array compound assignment. */
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

	static function rhsMutatingArray():Int {
		events.push("rhs_mutates_array");
		values[1] = 100;
		return 3;
	}

	static function main():Void {
		final result = receiver()[index()] += rhsMutatingArray();
		Sys.println("result=" + result + " final=" + values[1] + " events=" + events.join(","));

		final floats:Array<Float> = [1.5];
		final floatResult = floats[0] += 0.5;
		Sys.println("float=" + floatResult + " final=" + floats[0]);
	}
}
