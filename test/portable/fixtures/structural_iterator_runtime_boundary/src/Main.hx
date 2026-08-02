/**
	Exercises the supported ways a Haxe program consumes an `Iterator<Int>`.

	The output is intentionally small and behavior-focused: direct calls on an
	iterator object literal and a standard-library `Iterable` consumer must agree
	with Haxe 4.3.7. Standalone iterator method values and nominal-to-structural
	adaptation are separate unsupported boundaries and are not claimed here.
**/
class Main {
	static function emit(line:String):Void {
		#if js
		js.Syntax.code("console.log({0})", line);
		#else
		Sys.println(line);
		#end
	}

	static function fromArray(values:Array<Int>):Iterator<Int> {
		var index = 0;
		return {
			hasNext: () -> index < values.length,
			next: () -> values[index++]
		};
	}

	static function sum(iterator:Iterator<Int>):Int {
		var result = 0;
		while (iterator.hasNext())
			result += iterator.next();
		return result;
	}

	static function main():Void {
		emit("literal.sum=" + sum(fromArray([1, 2, 3])));

		emit("array.count=" + Lambda.count([7, 8, 9]));
	}
}
