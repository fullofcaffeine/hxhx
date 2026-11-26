/**
	Conditional compilation reads both operands of `&&` and `||`, even when the left side decides
	the result (haxe_ocaml-ac5i9.16).

	The evaluator wrote `left = left || parseAnd()`. When `left` was true, the short-circuit skipped
	the call, so the right operand's tokens stayed unread and the rest of the condition was misread.
	`sys.Http` selects its SSL socket with
	`(neko && !(macro || interp) || eval)`, which hxhx read as false for the interp target.

	The expected branches are upstream Haxe 4.3.7's, checked with
	`haxe -D yes --run Main` on the same conditions (defines: yes, sys, interp, eval).
**/
class M14ConditionalOperandsTest {
	static function filter(source:String, defines:haxe.ds.StringMap<String>):String
		return StringTools.trim(HxConditionalCompilation.filterSource(source, defines));

	static function expect(label:String, actual:String, expected:String):Void {
		if (actual != expected)
			throw label + ": expected '" + expected + "', got '" + actual + "'";
	}

	static function main():Void {
		final defines = new haxe.ds.StringMap<String>();
		for (name in ["yes", "sys", "interp", "eval"])
			defines.set(name, "1");

		expect("and decided by its left side", filter("#if (neko && !(macro || interp) || eval) A #else B #end", defines), "A");
		expect("or decided by its left side", filter("#if ((yes || no) && no) A #else B #end", defines), "B");
		expect("group after a decided and", filter("#if (no && (yes || no) || yes) A #else B #end", defines), "A");
		expect("and binds tighter than or", filter("#if (yes || no && no) A #else B #end", defines), "A");
		expect("sys.Http SSL condition",
			filter("#if (!no_ssl && (hxssl || hl || cpp || (neko && !(macro || interp) || eval) || (lua && !lua_vanilla))) A #else B #end", defines), "A");
		expect("negation after a decided group", filter("#if ((yes || (no) || no) && !yes) A #else B #end", defines), "B");
		Sys.println("M14_CONDITIONAL_OPERANDS:PASS");

		// An operand that cannot change the result is read but observes no define, as upstream's
		// evaluation never looks at it. Compilation-server invalidation relies on this.
		final observed = HxConditionalCompilation.filterSourceObserved("#if ((yes || later) && (no && skipped) || last) A #else B #end", defines);
		expect("observed branch", StringTools.trim(observed.getFilteredSource()), "B");
		expect("observed defines", observed.getObservation().getObservedDefineNames().join(","), "last,no,yes");
		Sys.println("M14_CONDITIONAL_OPERANDS_OBSERVATION:PASS");
	}
}
