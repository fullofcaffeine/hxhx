import haxe.macro.Expr;

/**
	`MacroBodyExport` turns parsed function bodies into the public `haxe.macro.Expr` shape that
	upstream Haxe 4.3.7 produces for the same source. The expected texts below were produced by
	upstream Haxe 4.3.7 for this exact source with `scripts/oracle/upstream/ParseOracleUpstream.hx`,
	that is, upstream's parse printed with `haxe.macro.Printer` after the parse oracle's
	normalization (`scripts/oracle/shared/ParseOracleNormalize.hx`).
**/
class M14MacroBodyExportTest {
	static function exportFunction(source:String, name:String):String {
		final decl = ParserStage.parse(source, "Main.hx").getDecl();
		final export = new MacroBodyExport(new MacroSyntaxPositions("Main.hx"));
		final position:Position = {file: "Main.hx", min: 0, max: 0};
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

	static function main():Void {
		final source = "class Main {
	static function braced(x:Int):Int {
		return x + 1;
	}
	static function bare(x:Int):Int return x * 2;
	static function loops(items:Array<Int>):Int {
		var total = 0;
		for (item in items) total += item;
		while (total > 10) total -= 10;
		do {
			total++;
		} while (total < 3);
		return total;
	}
	static function patterns(value:Null<Int>):String {
		switch (value) {
			case null: return \"none\";
			case 1 | 2: return \"small\";
			case v if (v > 100): return \"big\";
			default: return \"other\";
		}
	}
	static function guarded(text:String):Int {
		try {
			throw text;
		} catch (e:String) {
			return e.length;
		}
	}
}";
		expect("braced body", exportFunction(source, "braced"), "{\n\treturn x + 1;\n}");
		expect("expression body", exportFunction(source, "bare"), "return x * 2");
		expect("loops", exportFunction(source, "loops"),
			"{\n\tvar total = 0;\n\tfor (item in items) total += item;\n\twhile (total > 10) total -= 10;\n\tdo {\n\t\ttotal++;\n\t} while (total < 3);\n\treturn total;\n}");
		expect("patterns", exportFunction(source, "patterns"),
			"{\n\tswitch (value) {\n\t\tcase null:{\n\t\t\treturn \"none\";\n\t\t};\n\t\tcase 1 | 2:{\n\t\t\treturn \"small\";\n\t\t};\n\t\tcase v if (v > 100):{\n\t\t\treturn \"big\";\n\t\t};\n\t\tcase _:{\n\t\t\treturn \"other\";\n\t\t};\n\t};\n}");
		expect("try", exportFunction(source, "guarded"), "{\n\ttry {\n\t\tthrow text;\n\t} catch(e:String) {\n\t\treturn e.length;\n\t};\n}");
		Sys.println("M14_MACRO_BODY_EXPORT:PASS");
	}
}
