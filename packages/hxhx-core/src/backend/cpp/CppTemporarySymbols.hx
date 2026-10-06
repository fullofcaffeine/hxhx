package backend.cpp;

import haxe.ds.StringMap;

/**
	Names target-created storage without changing any authored local's symbol.

	Each rendering scope reserves its executable's complete local inventory first.
	Repeated requests for a preferred name return the same temporary. Callers may
	reuse that name only in separate C++ lexical scopes; simultaneous temporaries
	must have distinct preferred names. No source identifier lookup uses this map.
**/
class CppTemporarySymbols {
	final occupied = new StringMap<Bool>();
	final symbols = new StringMap<String>();

	public function new(locals:CppExecutableLocals) {
		for (symbol in locals.getOccupiedSymbols())
			occupied.set(symbol, true);
	}

	/** Allocate once per explicit temporary name, including collisions with prior helpers. */
	public function symbol(preferred:String):String {
		final previous = symbols.get(preferred);
		if (previous != null)
			return previous;
		var emitted = preferred;
		var suffix = 1;
		while (occupied.exists(emitted)) {
			suffix++;
			emitted = preferred + "_" + suffix;
		}
		occupied.set(emitted, true);
		symbols.set(preferred, emitted);
		return emitted;
	}
}
