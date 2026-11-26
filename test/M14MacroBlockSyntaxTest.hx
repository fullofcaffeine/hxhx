import sys.io.File;

/**
	A block that starts with a type quotation stays a block (haxe_ocaml-ac5i9.18).

	Haxe 4.3.7 lexes `macro` as a keyword (`lexer.ml`), and a brace starts an object literal only
	when an identifier, a `$name` or a string comes first and `:` follows (`grammar.mly`, `block1`).
	So `{ macro : Dynamic; }` is a block that holds a type quotation. hxhx lexes `macro` as an
	identifier, and `HxParser.parseBraceExpr` read the block as the object literal
	`{macro: Dynamic}`, in ordinary and authored parsing. `haxe.macro.TypeTools.toComplexType`
	has this shape.
**/
class M14MacroBlockSyntaxTest {
	static final root = "test/fixtures/macro_block_syntax";

	static function functionBody(source:String, name:String, authored:Bool):String {
		final path = root + "/Main.hx";
		final decl = (authored ? ParserStage.parseAuthored(source, path) : ParserStage.parse(source, path)).getDecl();
		for (cls in HxModuleDecl.getClasses(decl))
			for (fn in HxClassDecl.getFunctions(cls))
				if (HxFunctionDecl.getName(fn) == name)
					return Std.string(HxFunctionDecl.getBody(fn));
		throw "missing function " + name;
	}

	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function observe(command:String, arguments:Array<String>, expected:String):Void {
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["60", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != expected)
			throw "macro block observer differs: " + stdout + stderr;
	}

	public static function main():Void {
		final source = File.getContent(root + "/Main.hx");
		for (authored in [false, true]) {
			final label = authored ? "authored" : "ordinary";
			final pick = functionBody(source, "pick", authored);
			require(pick.indexOf("EMacroType(") >= 0, label + ": the block must hold the type quotation: " + pick);
			require(pick.indexOf("EAnon") < 0, label + ": the block must not be an object literal: " + pick);
			// The same block as a statement.
			final statement = functionBody(source, "statement", authored);
			require(statement.indexOf("EAnon") < 0 && statement.indexOf("ENull),SBlock([SExpr(EMacroType(") >= 0,
				label + ": the statement must be a block holding the type quotation: " + statement);
			// An identifier followed by `:` still starts an object literal.
			final object = functionBody(source, "object", authored);
			require(object.indexOf("EAnon([name]") >= 0, label + ": `{name: 1}` must stay an object literal: " + object);
		}
		Sys.println("MACRO_BLOCK_PARSE:PASS");

		// The fixture is a valid upstream program with this result.
		observe("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"], File.getContent(root + "/expected.stdout"));
		Sys.println("MACRO_BLOCK_UPSTREAM_RUN:PASS");
	}
}
