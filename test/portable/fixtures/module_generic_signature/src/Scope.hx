/** Restores request-local permission after a generic callback returns or throws. */
class Scope {
	public var active(default, null):Bool = false;
	public var entries(default, null):Int = 0;

	public function new() {}

	public function entered():Void {
		entries++;
	}

	public function within<T>(action:() -> T):T {
		final previous = active;
		active = true;
		First.enter(this);
		try {
			final result = action();
			active = previous;
			return result;
		} catch (error:Dynamic) {
			// Haxe permits arbitrary thrown values. Preserve the payload and restore state.
			active = previous;
			throw error;
		}
	}

	public function fail<T>(message:String):T {
		throw message;
	}

	/** Observes the erased value inside the method, before caller conversion. */
	public function describe<T>(value:T):String {
		return Std.string(value);
	}

	/** A callback producer must run when passed, even when this method ignores it. */
	public function skip<T>(action:() -> T, fallback:T):T {
		return fallback;
	}

	/** Both invocations must share the closure created once at the call site. */
	public function twice<T>(action:() -> T):T {
		action();
		return action();
	}
}
