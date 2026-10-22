/** A concrete enum keeps callback arguments and results outside primitive-only calls. */
enum Term {
	Value(number:Int);
}

typedef Resolver = (Term, String) -> Null<Term>;

/** Concrete class values check that callback invocation keeps native record types. */
class Payload {
	public final number:Int;

	public function new(number:Int) {
		this.number = number;
	}
}

/** A nullable function field returns an ordinary, non-null class instance. */
class ClassHost {
	var callback:Null<(Payload, String) -> Payload>;

	public function new(callback:(Payload, String) -> Payload) {
		this.callback = callback;
	}

	public function run(value:Payload):Payload {
		if (callback == null)
			return value;
		return callback(value, "entry");
	}
}

/** Stores an optional callback without changing its concrete Haxe signature. */
class CallbackHost {
	var resolve:Null<Resolver>;

	public function new() {}

	public function configure(callback:Resolver):Void {
		resolve = callback;
	}

	public function clear():Void {
		resolve = null;
	}

	function replaceDuringArgument(callback:Resolver):String {
		resolve = callback;
		return "hit";
	}

	public function runAndReplace(value:Term, callback:Resolver):Null<Term> {
		return resolve(value, replaceDuringArgument(callback));
	}

	public function run(value:Term, name:String):Null<Term> {
		if (resolve == null)
			return null;
		return resolve(value, name);
	}
}

/** Checks absent, present, replaced, and cleared callbacks through parameters and fields. */
class Main {
	static var empty:Null<() -> String>;

	static function invokeAbsent(callback:Null<() -> String>):String {
		return callback();
	}

	static function invokeAfterArgument(callback:Null<Int->String>, effect:() -> Int):String {
		return callback(effect());
	}

	static function optional(value:Term, name:String, ?resolve:Resolver):Null<Term> {
		if (resolve == null)
			return null;
		return resolve(value, name);
	}

	static function describe(value:Null<Term>):String {
		return value == null ? "absent" : switch value {
			case Value(number): Std.string(number);
		};
	}

	static function main():Void {
		var calls = 0;
		final callback:Resolver = (term, name) -> {
			calls++;
			return name == "hit" ? switch term {
				case Value(number): Value(number + 1);
			} : null;
		};
		Sys.println("optional absent=" + describe(optional(Value(4), "hit")));
		Sys.println("optional present=" + describe(optional(Value(4), "hit", callback)));
		Sys.println("optional miss=" + describe(optional(Value(4), "miss", callback)));
		final host = new CallbackHost();
		Sys.println("field absent=" + describe(host.run(Value(9), "hit")));
		host.configure(callback);
		Sys.println("field present=" + describe(host.run(Value(9), "hit")));
		host.configure((_, _) -> Value(30));
		Sys.println("field replaced=" + describe(host.run(Value(9), "hit")));
		host.clear();
		Sys.println("field cleared=" + describe(host.run(Value(9), "hit")));
		Sys.println("calls=" + calls);
		final classHost = new ClassHost((value, name) -> new Payload(value.number + name.length));
		Sys.println("class=" + classHost.run(new Payload(6)).number);
		empty = () -> "ready";
		Sys.println("static=" + empty());
		var caught = false;
		try {
			invokeAbsent(null);
		} catch (error:haxe.Exception) {
			caught = true;
		}
		Sys.println("absent invocation caught=" + caught);
		host.configure(callback);
		Sys.println("captured before replacement=" + describe(host.runAndReplace(Value(40), (_, _) -> Value(70))));
		Sys.println("replacement retained=" + describe(host.run(Value(40), "hit")));
		var effects = 0;
		try {
			invokeAfterArgument(null, () -> ++effects);
		} catch (error:haxe.Exception) {}
		Sys.println("absent argument effects=" + effects);
	}
}
