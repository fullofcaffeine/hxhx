enum Choice {
	Payload(values:Array<Int>);
}

enum Result {
	Mapped(value:Choice);
}

/** Reproduces a concrete enum callback forwarded to a generic array mapper. */
class Main {
	static function apply(items:Array<Choice>, transform:Choice->Choice):Array<Choice> {
		return new Mapper<Choice>(items).apply(transform);
	}

	static function nextMapper(items:Array<Choice>):Mapper<Choice> {
		Sys.println("receiver");
		return new Mapper(items);
	}

	static function nextCallback():Choice->Choice {
		Sys.println("callback");
		return input -> {
			Sys.println("invoke");
			return input;
		};
	}

	static function main():Void {
		final payload = [7];
		final choice = Payload(payload);
		final items = [choice];
		final results = [Mapped(choice)];
		var calls = 0;
		final mapped = apply(items, original -> {
			switch (original) {
				case Payload(values): if (values != payload) throw "lost input identity";
			}
			calls++;
			return switch (results[0]) {
				case Mapped(value): value;
			};
		});
		payload.push(9);
		switch (mapped[0]) {
			case Payload(values):
				Sys.println(values.join(","));
		}
		Sys.println("same=" + (mapped == items) + ",calls=" + calls);
		final reordered = nextMapper(items).apply(nextCallback());
		Sys.println("ordered-same=" + (reordered == items));
		var repeated = 0;
		new Mapper<Choice>([choice, choice]).apply(value -> {
			repeated++;
			return value;
		});
		Sys.println("repeat=" + repeated);
		final absent = new Mapper<Choice>([null]).apply(value -> value);
		Sys.println("null=" + (absent[0] == null));
		try {
			new Mapper(items).apply(input -> {
				throw "callback-error";
				return input;
			});
		} catch (message:String) {
			Sys.println(message);
		}
	}
}
