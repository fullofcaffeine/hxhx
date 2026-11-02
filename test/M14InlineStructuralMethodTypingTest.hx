/**
	Inline structural annotations get the same typed facts as named typedefs.

	Why
	- Haxe allows a structure type to be written in place, in the same
	  declaration form that a typedef uses:
	  `function provide():{ function value():Int; }`.
	- The parser keeps a written annotation as compact text, and it used to
	  join the words `function value` into `functionvalue`. The resolver could
	  not read the text back, so the return type stayed unresolved while the
	  equivalent named typedef resolved to a structure with a method field.

	What
	- Each inline form below must resolve to exactly the semantic type of its
	  named typedef twin: a method without arguments, a method with arguments,
	  a variable field holding a function, and a mixed structure.
	- A duplicate field in an inline structure is still rejected.
**/
class M14InlineStructuralMethodTypingTest {
	static function check(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function typeSource(source:String):TypedModule {
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		return TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
	}

	static function returnTypes(module:TypedModule):Map<String, String> {
		final result = new Map<String, String>();
		for (typedClass in module.getTypedClasses())
			for (fn in typedClass.getFunctions())
				result.set(fn.getEnvironment().getName(), fn.getEnvironment().getReturnType().getSemanticKey());
		return result;
	}

	static function main():Void {
		final source = "typedef Reader = { function value():Int; }\n"
			+ "typedef Adder = { function add(a:Int, b:Int):Int; }\n"
			+ "typedef Holder = { var value:Void->Int; }\n"
			+ "typedef Mixed = { var count:Int; function label(prefix:String):String; }\n"
			+ "class Main {\n"
			+ "\tstatic function inlineReader():{ function value():Int; } return null;\n"
			+ "\tstatic function namedReader():Reader return null;\n"
			+ "\tstatic function inlineAdder():{ function add(a:Int, b:Int):Int; } return null;\n"
			+ "\tstatic function namedAdder():Adder return null;\n"
			+ "\tstatic function inlineHolder():{ var value:Void->Int; } return null;\n"
			+ "\tstatic function namedHolder():Holder return null;\n"
			+ "\tstatic function inlineMixed():{ var count:Int; function label(prefix:String):String; } return null;\n"
			+ "\tstatic function namedMixed():Mixed return null;\n"
			+ "}\n";
		final types = returnTypes(typeSource(source));
		for (pair in [
			["inlineReader", "namedReader"],
			["inlineAdder", "namedAdder"],
			["inlineHolder", "namedHolder"],
			["inlineMixed", "namedMixed"]
		]) {
			final written = types.get(pair[0]);
			final named = types.get(pair[1]);
			check(written != null && named != null, "missing typed function " + pair.join("/"));
			check(StringTools.startsWith(named, "anonymous:{"), pair[1] + " did not resolve to a structure: " + named);
			check(written == named, pair[0] + " differs from its typedef: " + written + " vs " + named);
		}
		check(types.get("inlineReader") == "anonymous:{value:method<0>:function:()->primitive:Int}",
			"inline method field lost its method contract: " + types.get("inlineReader"));

		var rejected:Null<String> = null;
		try {
			typeSource("class Main {\n\tstatic function twice():{ function value():Int; function value():Int; } return null;\n}\n");
		} catch (error:Dynamic) {
			rejected = Std.string(error);
		}
		check(rejected != null && rejected.indexOf("Duplicate field declaration : value") >= 0,
			"duplicate inline structural field was not rejected: " + rejected);
		Sys.println("M14_INLINE_STRUCTURAL_METHOD_TYPING:PASS");
	}
}
