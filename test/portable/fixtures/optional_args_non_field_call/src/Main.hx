class Foo {
	public static function greet(name:String, ?suffix:String):String {
		return suffix == null ? "hi " + name : ("hi " + name + suffix);
	}

	public static function optOnly(?s:String):String {
		return s == null ? "none" : s;
	}
}

class Main {
	static function main() {
		// Non-field callsite: the callee is a function value, not a TField node.
		//
		// In OCaml, we represent Haxe optional parameters as normal arguments that accept
		// the `HxRuntime.hx_null` sentinel. That means we must *pad* omitted optional
		// args at callsites; otherwise the generated OCaml becomes a partial application
		// (warning 5 under dune's warn-error setups).
		final f = Foo.greet;
		final g = Foo.optOnly;

		Sys.println("greet=" + f("bob"));
		Sys.println("optOnly=" + g());
	}
}

