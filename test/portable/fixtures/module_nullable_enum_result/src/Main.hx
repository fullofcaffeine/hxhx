class Main {
	static function main():Void {
		final values = [7];
		final present = Producer.optional(true, values);
		values.push(9);
		switch (present) {
			case Payload(shared):
				Sys.println(shared.join(","));
			case _:
				throw "expected payload";
		}
		Sys.println("null=" + (Producer.optional(false, values) == null));
	}
}
