import Shapes;

/** Calls that upstream Haxe 4.3.7 accepts and that the arity checks must keep accepting. */
class Accepted {
	static var field:Box<Int, String>;
	static var constantField:Const<"a\",b">;

	static function main():Void {
		final explicit = new Box<Int, String>();
		final inferred:Box<Int, String> = new Box();
		final alias:Pair<Int, String> = new Pair<Int, String>();
		final defaulted:Def<Int> = new Def<Int>();
		final overridden = new Def<Int, Bool>();
		final wrapped = new Wrap<Int>(1);
		new Opt(1);
		new Opt(1, 2);
		new Rest(1);
		new Rest(1, 2, 3, 4);
		new Child(1, 2);
		new G(1);
		new G<Int>(1);
		new GC<Int>(1);
		final first = new Ext("s");
		final second = new Ext(1, 2);
		final map = new Map<String, Int>();
		final error = new haxe.Exception("x");
		final buffer = new StringBuf();
		// A `,` or `>` inside a structure extension or a string constant is not an empty slot.
		final extended = new Holder<{ > S1, > S2, z:Int}>();
		final arrow = new Box<Int->Int, String>();
		final commas = new Const<"a,,b">();
		final brackets = new Const<"<>">();
		final comma = new Const<",">();
		final escapedQuote = new Const<"a\"b,c">();
		final backslash = new Const<"a\\,b">();
		final singleQuoted = new Const<'a",b'>();
		final twoConstants = new Const2<'"', "c">();
		final nestedConstant = new One<Const<"a\",b">>();
		// Macros own the arguments of a generic-build class and the members of a built one.
		final multi = new Multi<Int, String, Bool>();
		final built = new Built(1);
		final autoBuilt = new AutoChild(1);
		trace(make(explicit) == explicit);
	}

	static function make(value:Box<Int, String>):Box<Int, String> {
		return value;
	}
}
