/** A generic callback restores temporary state for supplied and omitted method arguments. */
class Scope {
	public var depth:Int = 0;
	public var optional:Int = 0;
	public var defaults:Int = 0;
	public var sources:Int = 0;

	public function new() {}

	/** The enum and typed object pass unchanged beside a separately adapted callback. */
	public function withSource<T>(source:Source, type:Value, action:() -> T, ?typed:Value):T {
		switch (source) {
			case Item(value):
				if (value != type || (typed != null && typed != type))
					throw "source identity changed";
		}
		sources++;
		return within(action, typed);
	}

	public function within<T>(action:() -> T, ?typed:Value):T {
		final previous = depth;
		depth++;
		Peer.observe(this);
		if (typed != null)
			optional++;
		try {
			final result = action();
			depth = previous;
			return result;
		} catch (error:Dynamic) {
			// Haxe can throw any value. Preserve that value unchanged at this exception boundary.
			depth = previous;
			throw error;
		}
	}

	public function withDefault<T>(action:() -> T, amount:Int = 3):T {
		defaults += amount;
		return action();
	}
}
