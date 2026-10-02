/** Observes the function actually called after direct and captured replacement. */
class EnumProducerMutationProbe {
	static function describe(value:Null<Payload>):String {
		return switch (value) {
			case null: "null";
			case Empty: "empty";
			case Text(text): text;
		};
	}

	static function unchanged(flag:Bool):String {
		final producer = function():Null<Payload> {
			if (flag)
				return null;
			return Text("unchanged");
		};
		return describe(producer());
	}

	static function direct(flag:Bool, empty:Bool):String {
		var producer = function():Null<Payload> {
			if (flag)
				return null;
			return Text("initial");
		};
		final replacement = function():Null<Payload> {
			if (empty)
				return null;
			return Text("direct");
		};
		producer = replacement;
		return describe(producer());
	}

	static function captured(flag:Bool, empty:Bool):String {
		var producer = function():Null<Payload> {
			if (flag)
				return null;
			return Text("initial");
		};
		final replacement = function():Null<Payload> {
			if (empty)
				return null;
			return Text("captured");
		};
		final replace = function():Void {
			producer = replacement;
		};
		replace();
		return describe(producer());
	}

	static function main():Void {
		Sys.println(unchanged(false));
		Sys.println(unchanged(true));
		Sys.println(direct(false, false));
		Sys.println(direct(false, true));
		Sys.println(captured(false, false));
		Sys.println(captured(false, true));
	}
}
