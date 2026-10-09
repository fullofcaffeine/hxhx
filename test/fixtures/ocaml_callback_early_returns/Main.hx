/** Early returns preserve converted callbacks and bypass ordinary Haxe catch clauses. */
class Main {
	/** Dynamic is the generic callback boundary; validate its Boolean tag immediately. */
	static function echo(value:Dynamic):Dynamic {
		if (!Std.isOfType(value, Bool))
			throw "Boolean callback argument lost its type";
		return value;
	}

	static function branch(early:Bool, callback:Dynamic->Dynamic):Bool->Bool {
		if (early) {
			Sys.println("early");
			return callback;
		}
		Sys.println("late");
		return echo;
	}

	static function guarded(early:Bool, callback:Dynamic->Dynamic):Bool->Bool {
		try {
			if (early)
				return callback;
		} catch (error:Dynamic) {
			// Catch input is intentionally ignored: an ordinary catch must never see a return signal.
			throw "Early callback return entered an ordinary catch";
		}
		return echo;
	}

	static function aliased(early:Bool, callback:Dynamic->Dynamic):Bool->Bool {
		final alias:Bool->Bool = callback;
		if (early)
			return alias;
		return echo;
	}

	static function original():Dynamic->Dynamic {
		return echo;
	}

	static function forwarded(early:Bool):Bool->Bool {
		if (early)
			return original();
		return echo;
	}

	/** The returned closure must retain this invocation's captured state across native collection. */
	static function captured(early:Bool, seed:Int):Int->Int {
		if (early)
			return function(value:Int):Int {
				return seed + value;
			};
		return function(value:Int):Int {
			return seed - value;
		};
	}

	/** A declared callback result does not require a value when every path throws. */
	static function unavailable():Int->Int {
		throw "unavailable";
	}

	static function main() {
		final callback:Dynamic->Dynamic = echo;
		final first = branch(true, callback);
		Sys.println(first(false));
		Sys.println(first == callback);
		final last = branch(false, callback);
		Sys.println(last(false));
		Sys.println(last == callback);
		final caught = guarded(true, callback);
		Sys.println(caught(false));
		Sys.println(caught == callback);
		final alias = aliased(true, callback);
		Sys.println(alias(false));
		Sys.println(alias == callback);
		final called = forwarded(true);
		Sys.println(called(false));
		Sys.println(called == callback);
		final capture = captured(true, 10);
		#if ocaml
		NativeGc.full_major();
		#end
		Sys.println(capture(5));
		Sys.println(capture == capture);
		Sys.println(capture == captured(true, 10));
		try {
			final missing = unavailable();
			Sys.println(missing(7));
		} catch (error:String) {
			Sys.println(error);
		}
	}
}

#if ocaml
/** Test-only extern: force the real native collector after a closure escapes through return control. */
@:native("Stdlib.Gc")
private extern class NativeGc {
	static function full_major():Void;
}
#end
