/** Observe fields and same-named locals through both qualified and bare access. */
class Holder {
	static var calls:Int = 0;

	var stored:Int;

	public function new(value:Int)
		stored = value;

	public function advance():Int {
		stored++;
		return stored;
	}

	public static function next():Int {
		calls++;
		return calls;
	}

	public static function qualifiedNext():Int {
		Holder.calls++;
		return Holder.calls;
	}

	public static function shadow():Int {
		var calls = 40;
		calls++;
		return calls;
	}

	public static function parameter(calls:Int):Int {
		calls++;
		return calls;
	}

	public static function mixed():Int {
		var before = calls;
		{
			var calls = 90;
			calls++;
		}
		calls++;
		return before * 10 + calls;
	}
}

/** Printed values distinguish field updates from local mutation and repeated evaluation. */
class Main {
	static function main() {
		Sys.println(Holder.next());
		Sys.println(Holder.next());
		Sys.println(Holder.shadow());
		Sys.println(Holder.qualifiedNext());
		Sys.println(Holder.mixed());
		Sys.println(Holder.next());
		Sys.println(Holder.parameter(50));
		Sys.println(Holder.next());
		var holder = new Holder(6);
		Sys.println(holder.advance());
		Sys.println(holder.advance());
	}
}
