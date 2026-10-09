import sys.io.File;

/** Custom providers prove construction and abstract method behavior independently of Map names. */
class M14MultiTypeRuntimeTest {
	static function main():Void {
		final source = File.getContent("test/fixtures/multitype_specialization/Main.hx");
		run("declared_methods", source);
		var rebind = StringTools.replace(source, "public inline function label()",
			"public inline function clear():Void this = null; public inline function clearAgain():Void clear(); public inline function label()");
		rebind = StringTools.replace(rebind, "final text =", "var text =");
		rebind = StringTools.replace(rebind, 'throw "abstract method body";',
			'throw "abstract method body"; text.clearAgain(); if (text != null) throw "receiver rebinding";');
		run("receiver_rebinding", rebind);
		run("temporary_receiver", StringTools.replace(source, "text.description()", "(new Choice<String>()).description()"));
		run("followed_abstract", "abstract TextKey(String) {}\n" + StringTools.replace(source, "new Choice<String>()", "new Choice<TextKey>()"));
		final effects = 'class Effects { public static var events:String = ""; public static var receivers:Int = 0;'
			+ 'public static function text():String { events += "a"; return "hello"; }'
			+ 'public static function number():Int { events += "b"; return 7; }'
			+ 'public static function take(value:Choice<String>):Choice<String> { receivers++; return value; } }\n';
		var arguments = StringTools.replace(source, "public function new();", "public function new(value:T);");
		arguments = StringTools.replace(arguments, "unused:Storage<T>):TextStorage", "unused:Storage<T>, value:T):TextStorage");
		arguments = StringTools.replace(arguments, "return new TextStorage();",
			'{ if (unused != null || value != "hello") throw "text inputs"; Effects.events += "t"; return new TextStorage(); }');
		arguments = StringTools.replace(arguments, "unused:Storage<T>):NumberStorage", "unused:Storage<T>, value:T):NumberStorage");
		arguments = StringTools.replace(arguments, "return new NumberStorage();",
			'{ if (unused != null || value != 7) throw "number inputs"; Effects.events += "n"; return new NumberStorage(); }');
		arguments = StringTools.replace(arguments, "new Choice<String>()", "new Choice<String>(Effects.text())");
		arguments = StringTools.replace(arguments, "new Choice<Int>()", "new Choice<Int>(Effects.number())");
		arguments = StringTools.replace(arguments, "text.description()", "Effects.take(text).description()");
		arguments = StringTools.replace(arguments, 'throw "abstract method body";',
			'throw "abstract method body"; if (Effects.events != "atbn" || Effects.receivers != 1) throw "effect order";');
		run("arguments_and_receiver_once", effects + arguments);
		run("inferred_constructor_arguments",
			effects + StringTools.replace(StringTools.replace(arguments, "new Choice<String>", "new Choice"), "new Choice<Int>", "new Choice"));
		Sys.println("MULTITYPE_RUNTIME:PASS");
	}

	static function run(name:String, source:String):Void {
		final output = JsRuntimeFixture.reserveOutput();
		File.saveContent(output + "/Main.hx", source);
		@:privateAccess M14JsFunctionLiteralRuntimeTest.command("haxe", ["-cp", output, "-main", "Main", "-js", output + "/upstream.js"]);
		@:privateAccess M14JsFunctionLiteralRuntimeTest.command("node", [output + "/upstream.js"]);
		Sys.println("MULTITYPE_RUNTIME:" + name + ":upstream:PASS");
		final resolved = new ResolvedModule("Main", output + "/Main.hx", ParserStage.parse(source, output + "/Main.hx"));
		final index = TyperIndex.build([resolved]);
		final typed = TyperStage.typeResolvedModule(resolved, index);
		JsRuntimeFixture.assertRuntime(typed, "Main", "");
		Sys.println("MULTITYPE_RUNTIME:" + name + ":local:PASS");
		@:privateAccess JsRuntimeFixture.removeOutput(output);
	}
}
