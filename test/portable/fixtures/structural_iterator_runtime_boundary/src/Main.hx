/**
	Exercises the supported ways a Haxe program consumes an `Iterator<Int>`.

	The output is intentionally small and behavior-focused: direct calls, method
	values captured from a complete structural Iterator, and a standard-library
	`Iterable` consumer must agree with Haxe 4.3.7. Nominal-to-structural
	adaptation remains a separate unsupported boundary and is not claimed here.
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

	static function consumeMethodValues(iterator:Iterator<Int>):String {
		final hasNext = iterator.hasNext;
		final next = iterator.next;
		final values:Array<String> = [];
		while (hasNext())
			values.push(Std.string(next()));
		return values.join(",");
	}

	static function main():Void {
		emit("literal.sum=" + sum(fromArray([1, 2, 3])));
		emit("method.values=" + consumeMethodValues(fromArray([4, 5])));

		emit("array.count=" + Lambda.count([7, 8, 9]));
	}
}
