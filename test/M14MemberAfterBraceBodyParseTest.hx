/**
	Haxe 4.3.7 does not require `;` after a method body without braces that ends with `}`,
	such as `public function name(p:Param):String return switch (p) { ... }` followed by the
	next method on the following line.

	The hxhx parser read the expression, then skipped tokens up to the next `;` to resynchronize.
	That recovery skipped the whole next method without an error, so the method disappeared. In
	the standard library, `haxe.macro.Printer.printTypePath` became part of `printTypeParam`, and
	three modules failed to type (haxe_ocaml-xjl1v).
**/
class M14MemberAfterBraceBodyParseTest {
	static function functionNames(members:String):String {
		final source = "class Main {\n" + members + "\n}\n";
		final decl = try ParserStage.parse(source, "Main.hx").getDecl() catch (e:haxe.Exception) throw "parse failed: " + e.message;
		return [
			for (fn in HxClassDecl.getFunctions(HxModuleDecl.getClasses(decl)[0]))
				HxFunctionDecl.getName(fn)
		].join(",");
	}

	static function expect(label:String, members:String, names:String):Void {
		final actual = functionNames(members);
		if (actual != names)
			throw label + ": expected " + names + ", got " + actual;
	}

	static function main():Void {
		final switchBody = "\tpublic function name(p:Int):String\n\t\treturn switch (p) {\n\t\t\tcase 0: \"a\";\n\t\t\tcase _: \"b\";\n\t\t}\n";
		expect("public method after a switch body", switchBody + "\n\tpublic function next():Int\n\t\treturn 1;", "name,next");
		expect("private method after a switch body", switchBody + "\tprivate function next():Int\n\t\treturn 1;", "name,next");
		expect("static method after a switch body", switchBody + "\tstatic function next():Int\n\t\treturn 1;", "name,next");
		expect("override after a switch body", switchBody + "\toverride function next():Int\n\t\treturn 1;", "name,next");
		expect("method after an if-else body",
			"\tpublic function pick(b:Bool):Int\n\t\treturn if (b) {\n\t\t\t1;\n\t\t} else {\n\t\t\t2;\n\t\t}\n\tpublic function next():Int\n\t\treturn 1;",
			"pick,next");
		expect("method after an object literal body", "\tpublic function obj()\n\t\treturn {a: 1}\n\tpublic function next():Int\n\t\treturn 1;", "obj,next");
		expect("with semicolon", switchBody.substr(0, switchBody.length - 1) + ";\n\tpublic function next():Int\n\t\treturn 1;", "name,next");
		expect("three methods", switchBody + switchBody.split("name").join("other") + "\tpublic function last():Int\n\t\treturn 1;", "name,other,last");

		Sys.println("M14_MEMBER_AFTER_BRACE_BODY_PARSE:PASS");
	}
}
