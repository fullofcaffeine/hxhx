/** A callback record retained across calls without eager callback construction. */
typedef Service = {final apply:Int->Int;}

/** Null-initialized cells must preserve identity in a real Cache/Peer module cycle. */
class Cache {
	static var stored:Null<Service> = null;
	static var storedState:Null<ServiceState> = null;

	/** Construct once per clear operation; the callback refers to the peer module. */
	public static function get():Service {
		if (stored != null)
			return stored;
		final created:Service = {apply: Peer.twice};
		stored = created;
		return created;
	}

	/** Exercise a nominal class carrier as well as the callback record carrier. */
	public static function getState():ServiceState {
		var state = storedState;
		if (state == null) {
			state = new ServiceState(13, get());
			storedState = state;
		}
		return state;
	}

	public static function clear():Void {
		stored = null;
		storedState = null;
	}
}
