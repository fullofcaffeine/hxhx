/**
	Uses `try` and `catch` without braces in every statement and value
	position, and prints which handler ran.

	A parser that loses a catch clause either lets the failure escape, runs the
	handler body outside the handler, or prints a different line.
**/
class Failure {
	public final label:String;

	public function new(label:String) {
		this.label = label;
	}
}

class Main {
	// Cleared in place: Stage3 does not store writes to static fields yet (haxe_ocaml-ailt8).
	static final log = new Array<String>();

	static function fail(message:String):Int {
		throw message;
	}

	static function failText(message:String):String {
		throw message;
	}

	static function failWith(value:Dynamic):Int {
		throw value;
	}

	static function note(text:String):Void
		log.push(text);

	static function flush():Void {
		Sys.println(log.join(" | "));
		log.splice(0, log.length);
	}

	static function main():Void {
		// One catch, statement form. A `;` after the whole statement is optional only before `}`.
		try
			fail("one")
		catch (e:String)
			note("caught " + e);
		try
			note("no failure")
		catch (e:String)
			note("wrong");
		note("after");
		flush();

		// Several catches, the second one matches.
		try
			failWith(42)
		catch (e:String)
			note("string")
		catch (e:Int)
			note("int " + e)
		catch (e:Dynamic)
			note("dynamic");
		try
			failWith(new Failure("typed"))
		catch (e:String)
			note("string")
		catch (e:Failure)
			note("failure " + e.label);
		try
			failWith(1.5)
		catch (e:String)
			note("string")
		catch (e:Dynamic)
			note("dynamic " + e);
		flush();

		// In if/else branches and loop bodies.
		for (index in 0...3)
			if (index == 1)
				try
					fail("branch " + index)
				catch (e:String)
					note("then " + e)
			else
				try
					fail("other " + index)
				catch (e:String)
					note("else " + e);
		var count = 0;
		while (count < 2)
			try {
				count++;
				fail("loop " + count);
			} catch (e:String)
				note("while " + e);
		for (index in 0...2)
			try
				fail("for " + index)
			catch (e:String)
				note(e);
		flush();

		// As a value.
		final value = try fail("value") catch (e:String) e.length;
		final fallback = try fail("fallback") catch (e:Dynamic) -1;
		final success = try 5 catch (e:Dynamic) -1;
		note("value " + value + " " + fallback + " " + success);
		note("argument " + (try failText("argument") catch (e:String) e));
		flush();

		// Nested unbraced tries. Every following catch belongs to the innermost try.
		try
			try
				fail("inner")
			catch (e:Int)
				note("wrong inner")
			catch (e:String)
				note("innermost got " + e);
		try
			(try fail("handled") catch (e:String) note("inner got " + e))
		catch (e:Dynamic)
			note("wrong outer");
		try
			(try fail("escapes") catch (e:Int) note("wrong inner"))
		catch (e:String)
			note("outer got " + e);
		try {
			try
				fail("rethrown")
			catch (e:String)
				throw e + "!";
		} catch (e:String)
			note("rethrow reached " + e);
		flush();

		// Unbraced catch bodies after braced try bodies, and a statement after them.
		try {
			fail("braced body");
		} catch (e:String)
			note("unbraced handler " + e);
		try {
			fail("braced handler");
		} catch (e:String) {
			note("braced handler " + e);
		}
		note("done");
		flush();
	}
}
