/**
	Omitted inputs used in array access take their types from that use, as in Haxe 4.3.7:
	the receiver becomes an Array, the subscript becomes Int, and later uses bind the element.
	The operations live in their own class, declared before `Main`, so that calls from `main`
	cannot supply the evidence.
**/
class Ops {
	public static function write(values, index) {
		values[index] = 1;
		return values.length;
	}

	public static function readTyped(values:Array<String>, index)
		return values[index];

	public static function element(values, index) {
		final value = values[index];
		return value + 1;
	}

	public static function pair(values, index)
		return values[index] + values[index + 1];

	public static function nested(rows, row, column) {
		rows[row][column] = "x";
		return rows.length;
	}
}

class Main {
	static function main() {
		Sys.println(Ops.write([0, 0, 0], 1));
		Sys.println(Ops.readTyped(["a", "b"], 1));
		Sys.println(Ops.element([4, 5], 1));
		Sys.println(Ops.pair([2, 3, 4], 1));
		Sys.println(Ops.nested([["a"], ["b"]], 1, 0));
	}
}
