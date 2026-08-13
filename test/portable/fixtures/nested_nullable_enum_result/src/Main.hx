enum Choice {
	Plain;
	Payload(value:Int);
}

enum Envelope {
	Wrapped(value:Null<Choice>);
}

class Main {
	static function wrap(mode:Int):Envelope {
		function choose():Null<Choice> {
			if (mode == 0)
				return null;
			final value:Choice = Plain;
			if (mode == 1)
				return value;
			return Payload(mode);
		}
		return Wrapped(choose());
	}

	static function describe(value:Envelope):String {
		return switch (value) {
			case Wrapped(null): "null";
			case Wrapped(Plain): "Plain";
			case Wrapped(Payload(number)): 'Payload:$number';
		};
	}

	static function main() {
		Sys.println(describe(wrap(0)));
		Sys.println(describe(wrap(1)));
		Sys.println(describe(wrap(2)));
	}
}
