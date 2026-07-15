/**
	Repo-owned upstream Haxe oracle for generic calls with array arguments.

	The generic cases cover flat, nested, and already-concrete arrays. The final
	case keeps a non-generic `Array<Int>` parameter as a control.
**/
class Main {
	@:generic static function count<A, B>(label:A, values:Array<B>):Int {
		return values.length;
	}

	static function countInts(values:Array<Int>):Int {
		return values.length;
	}

	static function emit(id:String, value:Dynamic):Void {
		Sys.println(id + "|value|" + Std.string(value));
	}

	static function main():Void {
		emit("generic-call-array-01:flat", count("flat", [1, 2]));
		emit("generic-call-array-01:nested", count("nested", [[1, 2]]));

		final concrete = [3, 4, 5];
		emit("generic-call-array-01:concrete", count("concrete", concrete));
		emit("generic-call-array-01:control", countInts([6, 7]));
	}
}
