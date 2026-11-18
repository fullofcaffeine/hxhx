/**
	In a function body, Haxe 4.3.7 does not require `;` after a statement whose last token is `}`.
	Upstream accepts `d.onData = s -> { ... }`, `var tp = { a: 1 }`, and `@:keep { ... }` with the
	next statement on the following line. A statement that ends with another token, such as `]`,
	`)`, or the `)` of `do { } while (x)`, still needs `;` ("Missing ;").

	The hxhx parser decided this from the expression shape, so it rejected arrow-function bodies,
	object literals, assignments and metadata blocks. Upstream `TestHttp.hx`, `TestIssues.hx` and
	`UnitBuilder.hx` failed with "Expected ';' after source group expression", and the weekly
	Gate 1 run stopped there.
**/
class M14SemicolonlessBraceStatementTest {
	static function bodyLength(label:String, statements:String, nested:Bool):Int {
		final body = nested ? "\t\tvar f = () -> {\n" + statements + "\n\t\t\ttrace(\"after\");\n\t\t};" : statements + "\n\t\ttrace(\"after\");";
		final source = "class Main {\n\tfunction main() {\n" + body + "\n\t}\n}\n";
		final decl = try ParserStage.parse(source, "Main.hx").getDecl() catch (e:haxe.Exception) throw label + ": parse failed: " + e.message;
		final cls = HxModuleDecl.getClasses(decl)[0];
		final main = HxClassDecl.getFunctions(cls)[0];
		final top = HxFunctionDecl.getBody(main);
		if (!nested)
			return top.length;
		return switch top {
			case [SVar(_, _, ESourceFunction(_, ESourceGroup(children, _), _, _), _, _)]: children.length;
			case _: throw label + ": expected one arrow function with a block body, got " + top;
		};
	}

	static function expectStatements(label:String, statements:String, count:Int):Void {
		for (nested in [false, true]) {
			final actual = bodyLength(label, statements, nested);
			if (actual != count)
				throw label + (nested ? " (arrow function body)" : "") + ": expected " + count + " statements, got " + actual;
		}
	}

	/** Only the arrow-function body is checked: statement-level bodies still accept a missing `;` (haxe_ocaml-p10ck). */
	static function expectMissingSemicolon(label:String, statements:String):Void {
		final message = try {
			bodyLength(label, statements, true);
			null;
		} catch (e:Dynamic)
			Std.string(e);
		if (message == null)
			throw label + " (arrow function body): a statement that does not end with '}' must still require ';'";
	}

	static function parses(label:String, source:String):Bool {
		return try {
			ParserStage.parse("class Main {\n\tfunction main() {\n" + source + "\n\t}\n}\n", "Main.hx");
			true;
		} catch (e:haxe.Exception)
			false;
	}

	/** `while` bodies and `switch` arms in expression position follow the same rule. */
	static function expectOtherBlocks():Void {
		final whileBody = (statement:String) -> "\t\tvar f = () -> {\n\t\t\twhile (true) {\n" + statement + "\n\t\t\t\tbreak;\n\t\t\t}\n\t\t};";
		final switchArm = (statement:String) -> "\t\tvar f = () -> switch (1) {\n\t\t\tcase _:\n" + statement + "\n\t\t\t\ttrace(1);\n\t\t};";
		for (shape in [{name: "while body", wrap: whileBody}, {name: "switch arm", wrap: switchArm}]) {
			if (!parses(shape.name, shape.wrap("\t\t\t\tvar tp = {a: 1}")))
				throw shape.name + ": an object literal that ends with '}' needs no ';'";
			if (!parses(shape.name, shape.wrap("\t\t\t\tvar g = e -> {\n\t\t\t\t\ttrace(e);\n\t\t\t\t}")))
				throw shape.name + ": an arrow function that ends with '}' needs no ';'";
			if (parses(shape.name, shape.wrap("\t\t\t\tvar a = [1, 2]")))
				throw shape.name + ": an array literal must still require ';'";
		}
	}

	static function main():Void {
		expectStatements("arrow function assignment", "\t\tvar onData = null;\n\t\tonData = s -> {\n\t\t\ttrace(s);\n\t\t}", 3);
		expectStatements("field assignment of an arrow function", "\t\tthis.handler = e -> {\n\t\t\ttrace(e);\n\t\t}", 2);
		expectStatements("object literal", "\t\tvar tp = {\n\t\t\ta: 1,\n\t\t\tb: 2\n\t\t}", 2);
		expectStatements("metadata block", "\t\t@:keep {\n\t\t\ttrace(1);\n\t\t}", 2);
		expectStatements("switch initializer", "\t\tvar r = switch (1) {\n\t\t\tcase _: 2;\n\t\t}", 2);
		expectStatements("if-else assignment", "\t\tvar r = 0;\n\t\tr = if (true) {\n\t\t\t1;\n\t\t} else {\n\t\t\t2;\n\t\t}", 3);
		expectStatements("function expression", "\t\tvar g = function() {\n\t\t\treturn 4;\n\t\t}", 2);
		expectStatements("compound assignment of a block", "\t\tvar n = 0;\n\t\tn += { 5; }", 3);
		expectStatements("with semicolon", "\t\tvar tp = {a: 1};", 2);

		expectMissingSemicolon("array literal", "\t\tvar a = [1, 2]");
		expectMissingSemicolon("call with a trailing arrow function", "\t\tvar a = [1].map(x -> {\n\t\t\tx + 1;\n\t\t})");
		expectMissingSemicolon("do-while", "\t\tvar i = 0;\n\t\tdo {\n\t\t\ti++;\n\t\t} while (i < 3)");

		expectOtherBlocks();

		Sys.println("M14_SEMICOLONLESS_BRACE_STATEMENT:PASS");
	}
}
