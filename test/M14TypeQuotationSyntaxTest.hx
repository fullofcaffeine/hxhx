import haxe.macro.Expr;
import sys.io.File;

/**
	Type quotations export as upstream parses them (haxe_ocaml-ac5i9.14).

	Haxe 4.3.7 turns `macro : Null<$t>` into
	`(TPath({ pack : [], name : "Null", params : [TPType(t)] }) : haxe.macro.Expr.ComplexType)` while
	it parses. hxhx keeps `EMacroType(text)`, and the export refused it. The export now writes the
	same construction syntax (`MacroTypeQuotation`).

	`expected.bodies.json` holds the bodies upstream's parse recorder
	(`scripts/oracle/upstream/ParseOracleUpstream.hx`) printed for this fixture.
**/
class M14TypeQuotationSyntaxTest {
	static final root = "test/fixtures/type_quotation_syntax";

	static function body(source:String, name:String):String {
		final path = root + "/Main.hx";
		final decl = ParserStage.parseAuthored(source, path).getDecl();
		final export = new MacroBodyExport(new MacroSyntaxPositions(path));
		final position:Position = {file: path, min: 0, max: 0};
		for (cls in HxModuleDecl.getClasses(decl))
			for (fn in HxClassDecl.getFunctions(cls))
				if (HxFunctionDecl.getName(fn) == name)
					return new haxe.macro.Printer().printExpr(ParseOracleNormalize.expr(export.functionBody(HxFunctionDecl.getBody(fn),
						HxFunctionDecl.getBodyBraced(fn), position)));
		throw "missing function " + name;
	}

	static function expect(label:String, actual:String, expected:String):Void {
		if (actual != expected)
			throw label + ":\nexpected:\n" + expected + "\nactual:\n" + actual;
	}

	static function expectFailure(label:String, typeText:String, fragment:String):Void {
		final message = try {
			MacroTypeQuotation.expression(typeText, {file: root + "/Main.hx", min: 0, max: 0});
			null;
		} catch (error:String) {
			error;
		}
		if (message == null || message.indexOf(fragment) < 0)
			throw label + ": expected a failure that mentions `" + fragment + "`, got " + message;
	}

	static function observe(command:String, arguments:Array<String>, expected:String):Void {
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["60", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != expected)
			throw "type quotation observer differs: " + stdout + stderr;
	}

	public static function main():Void {
		final source = File.getContent(root + "/Main.hx");
		final expected:haxe.DynamicAccess<String> = haxe.Json.parse(File.getContent(root + "/expected.bodies.json"));
		for (name in expected.keys())
			expect(name, body(source, name), expected.get(name));
		Sys.println("TYPE_QUOTATION_AUTHORED:PASS");

		// Upstream writes exact source ranges into a structure type; hxhx records no end offsets yet.
		expectFailure("structure type", "{a:Int}", "macro syntax export: a structure type");
		// The shared type grammar reads no expression type parameters.
		expectFailure("expression type parameter", "Foo<1>", "macro syntax export: quoted type `Foo<1>` could not be read");
		Sys.println("TYPE_QUOTATION_UNSUPPORTED:PASS");

		// The fixture is a valid upstream program with these results.
		observe("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"], File.getContent(root + "/expected.stdout"));
		Sys.println("TYPE_QUOTATION_UPSTREAM_RUN:PASS");
	}
}
