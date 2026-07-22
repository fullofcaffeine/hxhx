/**
	Compact display fingerprint for deterministic compiler observation reports.

	The server's real in-memory identity remains the complete length-prefixed text.
	This small value makes reports readable and detects accidental nondeterminism in
	tests, but it is not collision-resistant and must never authorize cache reuse.
**/
class CompilerObservationFingerprint {
	public static function display(value:String):String {
		final text = value == null ? "" : value;
		var state = 17;
		for (index in 0...text.length)
			state = state * 31 + text.charCodeAt(index);
		return "display31-v1:" + text.length + ":" + state;
	}
}
