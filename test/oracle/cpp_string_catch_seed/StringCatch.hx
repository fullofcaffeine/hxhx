/**
	Dynamic is the arbitrary-throw boundary. Only a matched String or Bool enters
	its typed handler; unmatched explicit wrappers must preserve their identity.
 */
class StringCatch {
	public static function select(value:Dynamic, booleanFirst:Bool):String {
		if (booleanFirst) {
			try {
				throw value;
			} catch (caught:Bool) {
				return caught ? "bool:true" : "bool:false";
			} catch (caught:String) {
				return "string:" + caught;
			} catch (caught:Dynamic) {
				return caught == value ? "carrier" : "wrong-carrier";
			}
		} else {
			try {
				throw value;
			} catch (caught:String) {
				return "string:" + caught;
			} catch (caught:Bool) {
				return caught ? "bool:true" : "bool:false";
			} catch (caught:Dynamic) {
				return caught == value ? "carrier" : "wrong-carrier";
			}
		}
	}

	/** An unmatched wrapped payload escapes the entire typed-handler group. */
	public static function escaped(value:Dynamic, booleanFirst:Bool):Dynamic {
		try {
			select(value, booleanFirst);
		} catch (caught:Dynamic) {
			return caught;
		}
		return null;
	}

	public static function unmatched(value:Dynamic):Dynamic {
		try {
			try {
				throw value;
			} catch (_:String) {
				return null;
			} catch (_:Bool) {
				return null;
			}
		} catch (caught:Dynamic) {
			return caught;
		}
		return null;
	}

	/** Throwing a replacement leaves the handler and cannot enter its sibling catch-all. */
	public static function replacement():String {
		try {
			try {
				throw "original";
			} catch (caught:String) {
				caught = "replacement";
				throw caught;
			} catch (_:Dynamic) {
				return "wrong-sibling";
			}
		} catch (caught:String) {
			return caught;
		}
		return "wrong-completion";
	}

	/** Each invocation owns a distinct mutable catch cell after native unwinding ends. */
	public static function capture(value:Dynamic):String->String {
		try {
			throw value;
		} catch (caught:String) {
			return next -> {
				final previous = caught;
				caught = next;
				return previous;
			};
		}
		return null;
	}
}
