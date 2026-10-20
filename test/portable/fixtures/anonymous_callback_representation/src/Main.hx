/** A callback with a callback argument and a native Array result. */
typedef Service = {final run:(String->Array<String>)->Array<String>;}

/** Keeps callback callability without imposing incorrect runtime carriers. */
class Main {
	static function render(service:Service):Void {
		final result = service.run(label -> Bridge.isolate(() -> [label]));
		Sys.println(result.join(","));
	}

	static function main():Void {
		render({run: render -> render("value")});
		var index = 0;
		final iterator:Iterator<Int> = {hasNext: () -> index < 2, next: () -> [2, 3][index++]};
		final source:Iterable<Int> = {iterator: () -> iterator};
		var sum = 0;
		for (value in source)
			sum += value;
		Sys.println(sum);
	}
}
