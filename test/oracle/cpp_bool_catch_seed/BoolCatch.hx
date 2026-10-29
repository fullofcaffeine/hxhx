/** Dynamic is the deliberate arbitrary-throw boundary; only a matched Bool reaches Boolean operations. */
class BoolCatch {
	public static function select(value:Dynamic):Int {
		try {
			throw value;
		} catch (caught:Bool) {
			return caught ? 1 : 2;
		} catch (_:Dynamic) {
			return 3;
		}
	}

	public static function fallback(value:Dynamic):Dynamic {
		try {
			throw value;
		} catch (_:Bool) {
			return null;
		} catch (caught:Dynamic) {
			return caught;
		}
	}

	/** A rejected wrapped payload must escape the inner catch-all without changing identity. */
	public static function escaped(value:Dynamic):Dynamic {
		try {
			select(value);
		} catch (caught:Dynamic) {
			return caught;
		}
		return null;
	}

	public static function unmatched(value:Dynamic):Dynamic {
		try {
			try {
				throw value;
			} catch (_:Bool) {
				return null;
			}
		} catch (caught:Dynamic) {
			return caught;
		}
		return null;
	}

	public static function handlerThrows():Bool {
		try {
			try {
				throw true;
			} catch (caught:Bool) {
				caught = false;
				throw caught;
			} catch (_:Dynamic) {
				return true;
			}
		} catch (caught:Bool) {
			return caught;
		}
		return true;
	}

	/** Each handler entry owns its mutable cell after the native carrier has gone away. */
	public static function capture(value:Dynamic):Bool->Bool {
		try {
			throw value;
		} catch (caught:Bool) {
			return next -> {
				final previous = caught;
				caught = next;
				return previous;
			};
		}
		return null;
	}
}
