/** Exercises the element argument slots while preserving indices and effect order. */
class ElementOperations {
	public static function run(value:Null<Choice>):Void {
		final values:Array<Choice> = [];
		values.push(value);
		values.unshift(value);
		values.insert(1, value);
		Sys.println('operations=${values.length},${values.contains(value)},${values.indexOf(value)},${values.indexOf(value, 1)},${values.lastIndexOf(value)},${values.lastIndexOf(value, 1)},${values.remove(value)},${values.length}');

		final concrete:Choice = value;
		final nullable:Array<Null<Choice>> = [];
		nullable.push(concrete);
		nullable.unshift(null);
		nullable.insert(1, concrete);
		Sys.println('nullable=${nullable.length},${nullable[0] == null}');
		switch nullable[2] {
			case Payload(payload):
				Sys.println('payload=${payload.join(",")}');
			case _:
				throw "missing nullable payload";
		}

		final events:Array<String> = [];
		receiver(values, events).push(argument(value, events));
		Sys.println('effects=${events.join(",")}');
	}

	static function receiver(values:Array<Choice>, events:Array<String>):Array<Choice> {
		events.push("receiver");
		return values;
	}

	static function argument(value:Null<Choice>, events:Array<String>):Null<Choice> {
		events.push("argument");
		return value;
	}
}
