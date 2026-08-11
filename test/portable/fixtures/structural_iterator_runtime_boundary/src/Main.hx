/**
	Exercises the supported ways a Haxe program consumes an `Iterator<Int>`.

	The output is intentionally small and behavior-focused: direct calls, method
	values captured from a complete structural Iterator, and a standard-library
	`Iterable` consumer must agree with Haxe 4.3.7. Nominal-to-structural
	adaptation remains a separate unsupported boundary and is not claimed here.
**/
class Main {
	static var arrayBuilds = 0;

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

	static function makeArray():Array<Int> {
		arrayBuilds++;
		return [7, 8];
	}

	static function consumeArrayIterator(iterator:Iterator<Int>):String {
		final values:Array<String> = [];
		while (iterator.hasNext())
			values.push(Std.string(iterator.next()));
		return values.join(",");
	}

	/**
		Exercises the generic Iterator returned by `ObjectMap.keys()`.

		Haxe can keep the generated `next()` call's result as an unresolved generic
		placeholder even though the declared Iterator member returns `Dynamic`.
		That valid difference must still be owned by the direct Iterator call plan;
		it must not be mistaken for a separately captured method value.
	**/
	static function countObjectMapKeys():Int {
		final key:Dynamic = {id: 1};
		final map = new haxe.ds.ObjectMap<Dynamic, Dynamic>();
		map.set(key, "present");
		var count = 0;
		for (_ in map.keys())
			count++;
		return count;
	}

	static function main():Void {
		emit("literal.sum=" + sum(fromArray([1, 2, 3])));
		emit("method.values=" + consumeMethodValues(fromArray([4, 5])));
		emit("objectmap.keys=" + countObjectMapKeys());

		emit("array.count=" + Lambda.count([7, 8, 9]));

		arrayBuilds = 0;
		emit("array.direct=" + consumeArrayIterator(makeArray().iterator()) + ":builds=" + arrayBuilds);
		arrayBuilds = 0;
		final iteratorFactory = makeArray().iterator;
		emit("array.stored=" + consumeArrayIterator(iteratorFactory()) + ":builds=" + arrayBuilds);
	}
}
