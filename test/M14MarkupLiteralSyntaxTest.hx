import haxe.macro.Expr;
import sys.io.File;

/**
	Inline markup literals parse as upstream reads them (haxe_ocaml-jewla).

	Haxe 4.3.7 reads `<xml>...</xml>` in expression position. Its lexer takes the source text from
	`<` to the matching close tag (`lexer.ml` `lex_xml`, `not_xml`), and the parser gives
	`@:markup "<text>"` (`parser.ml` `handle_xml_literal`). A block statement that is a markup literal
	needs no semicolon (`grammar.mly` `parse_block_elt`). hxhx failed with "Expected ')'", which
	stopped the upstream unit suite at `unitstd/InlineXml.unit.hx`.

	`expected.bodies.json` holds the bodies upstream's parse recorder
	(`scripts/oracle/upstream/ParseOracleUpstream.hx`) printed for the fixture. Ordinary and
	authored parsing must both give them: a macro reads the literal through the ordinary parse.
**/
class M14MarkupLiteralSyntaxTest {
	static final root = "test/fixtures/markup_literal_syntax";

	static function print(value:Expr):String
		return new haxe.macro.Printer().printExpr(ParseOracleNormalize.expr(value));

	static function body(source:String, name:String, authored:Bool):String {
		final path = root + "/Main.hx";
		final decl = (authored ? ParserStage.parseAuthored(source, path) : ParserStage.parse(source, path)).getDecl();
		final export = new MacroBodyExport(new MacroSyntaxPositions(path));
		final position:Position = {file: path, min: 0, max: 0};
		for (cls in HxModuleDecl.getClasses(decl))
			for (fn in HxClassDecl.getFunctions(cls))
				if (HxFunctionDecl.getName(fn) == name)
					return print(export.functionBody(HxFunctionDecl.getBody(fn), HxFunctionDecl.getBodyBraced(fn), position));
		throw "missing function " + name;
	}

	static function expect(label:String, actual:String, expected:String):Void {
		if (actual != expected)
			throw label + ":\nexpected:\n" + expected + "\nactual:\n" + actual;
	}

	static function observe(command:String, arguments:Array<String>, expected:String):Void {
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["60", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != expected)
			throw "markup literal observer differs: " + stdout + stderr;
	}

	public static function main():Void {
		final source = File.getContent(root + "/Main.hx");
		final expected:haxe.DynamicAccess<String> = haxe.Json.parse(File.getContent(root + "/expected.bodies.json"));
		for (authored in [true, false])
			for (name in expected.keys())
				expect((authored ? "authored " : "ordinary ") + name, body(source, name, authored), expected.get(name));
		Sys.println("MARKUP_LITERAL_BODIES:PASS");

		// A markup literal field initializer needs no semicolon; the next field still parses.
		for (authored in [true, false]) {
			final decl = (authored ? ParserStage.parseAuthored(source, root + "/Main.hx") : ParserStage.parse(source, root + "/Main.hx")).getDecl();
			final initializers = new Map<String, String>();
			for (cls in HxModuleDecl.getClasses(decl))
				if (HxClassDecl.getName(cls) == "Fields")
					for (field in HxClassDecl.getFields(cls))
						initializers.set(HxFieldDecl.getName(field),
							print(new MacroBodyExport(new MacroSyntaxPositions(root + "/Main.hx")).fieldInitializer(HxFieldDecl.getInit(field), {
								file: root + "/Main.hx",
								min: 0,
								max: 0
							})));
			expect((authored ? "authored" : "ordinary") + " fields", initializers.get("plain") + " " + initializers.get("after"),
				'@:markup "<field kind=\\"static\\"></field>" @:markup "<after/>"');
		}
		Sys.println("MARKUP_LITERAL_FIELDS:PASS");

		// A macro's `Context.parseInlineString` reads text with the expression parser.
		final position:Position = {file: "spec.hx", min: 0, max: 0};
		final parsed = HxParser.parseExprText("{\nvar n = 1;\n<a>$n</a>\n<b/>;\nf(<c></c>);\n}");
		expect("expression text", print(new MacroSyntaxExport(new MacroSyntaxPositions("spec.hx")).quotation(parsed, position)),
			'{\n\tvar n = 1;\n\t@:markup "<a>$$n</a>";\n\t@:markup "<b/>";\n\tf(@:markup "<c></c>");\n}');
		// Function body statements need no semicolon either.
		final statements = HxParser.parseFunctionBodyText("<a></a>\n<b/>\nreturn 1;");
		expect("statements", [
			for (statement in statements)
				print(new MacroBodyExport(new MacroSyntaxPositions("spec.hx")).functionBody([statement], false, position))
		].join(" | "), '@:markup "<a></a>" | @:markup "<b/>" | return 1');
		Sys.println("MARKUP_LITERAL_STATEMENTS:PASS");

		final unterminated = try {
			HxParser.parseExprText("f(<a><b></b>)");
			null;
		} catch (error:HxParseError) {
			error.message;
		}
		expect("unterminated literal", unterminated, "Unterminated markup literal");
		Sys.println("MARKUP_LITERAL_UNTERMINATED:PASS");

		observe("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"], File.getContent(root + "/expected.stdout"));
		Sys.println("MARKUP_LITERAL_UPSTREAM_RUN:PASS");
	}
}
