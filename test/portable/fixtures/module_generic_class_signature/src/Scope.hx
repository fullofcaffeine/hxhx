/** Restores request state around callbacks while keeping the result generic. */
class Scope {
	public var active:Bool = false;
	public final values:Array<model.Payload> = [];
	public var retained:Null<{value:model.Payload}> = null;

	public function new() {}

	public function within<T>(action:() -> T):T {
		final previous = active;
		active = true;
		try {
			final value = action();
			active = previous;
			return value;
		} catch (error:Dynamic) {
			// Haxe permits arbitrary thrown payloads; this boundary preserves the exact value.
			active = previous;
			throw error;
		}
	}

	public function map<T>(value:T, action:T->T):T {
		return action(value);
	}
}
