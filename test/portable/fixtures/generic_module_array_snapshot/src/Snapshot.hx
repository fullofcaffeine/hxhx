/** Saves a generic array view and later reports whether its elements still compare equal. */
class Snapshot {
	public static function unchanged<T>(read:() -> Array<T>):() -> Bool {
		final saved = read().copy();
		return function() {
			final current = read();
			if (current.length != saved.length)
				return false;
			for (index in 0...saved.length)
				if (saved[index] != current[index])
					return false;
			return Cycle.depth(1) == 1;
		};
	}

	public static function depth(n:Int):Int {
		return n == 0 ? 0 : Cycle.depth(n - 1) + 1;
	}
}
