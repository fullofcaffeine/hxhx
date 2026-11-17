/**
	Conditional compilation must treat a dotted define name such as `target.threaded` as one
	define, as upstream Haxe 4.3.7 does. The Haxe 4.3 standard library selects code with
	`target.threaded`, `target.sys`, `target.static`, `target.unicode`, `target.utf16`, and
	`target.name`. hxhx read `target.threaded` as `target` followed by stray tokens, so every such
	condition was false (found by the parse oracle through `haxe.Timer`).
**/
class M14ConditionalDottedDefinesTest {
	static function filter(source:String, defines:haxe.ds.StringMap<String>):String
		return StringTools.trim(HxConditionalCompilation.filterSource(source, defines));

	static function expect(label:String, actual:String, expected:String):Void {
		if (actual != expected)
			throw label + ": expected '" + expected + "', got '" + actual + "'";
	}

	static function main():Void {
		final threaded = new haxe.ds.StringMap<String>();
		threaded.set("target.threaded", "1");
		threaded.set("target.name", "eval");
		threaded.set("eval", "1");
		final plain = new haxe.ds.StringMap<String>();
		plain.set("js", "1");

		expect("bare dotted define", filter("#if target.threaded A #else B #end", threaded), "A");
		expect("parenthesized", filter("#if (target.threaded) A #else B #end", threaded), "A");
		expect("and not", filter("#if (target.threaded && !cppia) A #else B #end", threaded), "A");
		expect("negated", filter("#if !target.threaded A #else B #end", threaded), "B");
		expect("elseif chain", filter("#if (flash || js) F #elseif (target.threaded && !cppia) T #else E #end", threaded), "T");
		expect("value comparison", filter("#if (target.name == \"eval\") A #else B #end", threaded), "A");
		expect("undefined dotted define", filter("#if target.threaded A #else B #end", plain), "B");
		expect("plain define still works", filter("#if js A #else B #end", plain), "A");
		Sys.println("M14_CONDITIONAL_DOTTED_DEFINES:PASS");
	}
}
