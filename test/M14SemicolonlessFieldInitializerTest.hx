/**
	A field initializer that ends with `}` does not need a semicolon in Haxe 4.3.7:
	`static final noop = function() {}` followed by the next member parses upstream. The same
	holds for a block, an object literal, an `if ... else { }`, and a `switch`. An initializer
	that ends with another token, such as the array literal `[1, 2]`, still needs one.

	The hxhx parser accepted only initializers that start with `{` or are a `switch` or `try`,
	so the standard library module `sys.thread.EventLoop` (eval) failed with "Expected ';'"
	and lost all 18 of its field bodies (haxe_ocaml-ac5i9.8, found by the parse oracle).
**/
class M14SemicolonlessFieldInitializerTest {
	static function parseClass(members:String):HxClassDecl {
		final decl = ParserStage.parse("class Main {\n" + members + "\n}\n", "Main.hx").getDecl();
		return HxModuleDecl.getClasses(decl)[0];
	}

	static function expectMembers(label:String, members:String, fieldNames:Array<String>, functionNames:Array<String>):Void {
		final cls = try parseClass(members) catch (e:haxe.Exception) throw label + ": parse failed: " + e.message;
		final fields = [for (field in HxClassDecl.getFields(cls)) HxFieldDecl.getName(field)];
		final functions = [for (fn in HxClassDecl.getFunctions(cls)) HxFunctionDecl.getName(fn)];
		if (fields.join(",") != fieldNames.join(","))
			throw label + ": expected fields " + fieldNames + ", got " + fields;
		if (functions.join(",") != functionNames.join(","))
			throw label + ": expected functions " + functionNames + ", got " + functions;
	}

	static function main():Void {
		final next = "\n\tpublic function after():Void {\n\t\tvar count = 0;\n\t\t++count;\n\t}";
		expectMembers("function expression", "\tstatic final noop = function() {}" + next, ["noop"], ["after"]);
		expectMembers("function expression before a doc comment", "\tstatic final noop = function() {}\n\n\t/** Doc. **/" + next, ["noop"], ["after"]);
		expectMembers("function with a body", "\tstatic final twice = function(x:Int) { return x * 2; }" + next, ["twice"], ["after"]);
		expectMembers("object literal", "\tstatic final o = {a: 1}" + next, ["o"], ["after"]);
		expectMembers("if with else block", "\tstatic final c = if (true) { 2; } else { 3; }" + next, ["c"], ["after"]);
		expectMembers("block", "\tstatic final b = { 1; }" + next, ["b"], ["after"]);
		expectMembers("switch", "\tstatic final s = switch (1) { case _: 5; }" + next, ["s"], ["after"]);
		expectMembers("two fields", "\tstatic final f = function() {}\n\tstatic final g = function() {}" + next, ["f", "g"], ["after"]);
		expectMembers("with semicolon", "\tstatic final noop = function() {};" + next, ["noop"], ["after"]);

		final arrayFailure = try {
			parseClass("\tstatic final arr = [1, 2]" + next);
			null;
		} catch (e:haxe.Exception)
			e.message;
		if (arrayFailure == null)
			throw "array literal: a field initializer that ends with ']' must still require ';'";

		Sys.println("M14_SEMICOLONLESS_FIELD_INITIALIZER:PASS");
	}
}
