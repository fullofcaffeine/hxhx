class M5ClassIntegrationTest {
	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) < 0) {
			throw label + ": expected to find '" + needle + "'";
		}
	}

	static function assertMatches(haystack:String, re:EReg, label:String):Void {
		if (!re.match(haystack)) {
			throw label + ": expected regex to match";
		}
	}

	static function assertMatchesEither(haystack:String, res:Array<EReg>, label:String):Void {
		for (re in res) {
			if (re.match(haystack)) return;
		}
		throw label + ": expected one of the regexes to match";
	}

	static function main() {
		final outDir = "out_ocaml_m5_class_" + Std.string(Std.int(Date.now().getTime()));
		sys.FileSystem.createDirectory(outDir);

		final args = [
			"-cp", "test",
			"-main", "ClassMain",
			"--no-output",
			"-lib", "reflaxe.ocaml",
			"-D", "no-traces",
			"-D", "no_traces",
			"-D", "ocaml_output=" + outDir,
			"-D", "ocaml_no_build"
		];

		final exitCode = Sys.command("haxe", args);
		if (exitCode != 0) throw "haxe compile failed: " + exitCode;

		final pointPath = outDir + "/Point.ml";
		if (!sys.FileSystem.exists(pointPath)) throw "missing output: " + pointPath;
		final pointMl = sys.io.File.getContent(pointPath);
		assertContains(pointMl, "type t = { __hx_type : Obj.t; mutable x : int; mutable y : int }", "record type decl");
		final createRe = ~/let create = fun ([A-Za-z_][A-Za-z0-9_]*) ([A-Za-z_][A-Za-z0-9_]*) ->/;
		if (!createRe.match(pointMl)) throw "create fn: expected to find 'let create = fun <x> <y> ->'";
		final xArg = createRe.matched(1);
		final yArg = createRe.matched(2);
		// Codegen may introduce a temp assignment to preserve Haxe assignment-expression semantics.
		assertMatchesEither(pointMl, [
			new EReg("self\\.x <- " + xArg, ""),
			new EReg("let __assign_[0-9]+ = " + xArg + " in \\(\\s*self\\.x <- __assign_[0-9]+;", "")
		], "ctor assigns x");
		assertMatchesEither(pointMl, [
			new EReg("self\\.y <- " + yArg, ""),
			new EReg("let __assign_[0-9]+ = " + yArg + " in \\(\\s*self\\.y <- __assign_[0-9]+;", "")
		], "ctor assigns y");
		assertContains(pointMl, "incX = fun self () ->", "instance method incX");
		assertMatchesEither(pointMl, [
			new EReg("self\\.x <- self\\.x \\+ 1", ""),
			new EReg("let __assign_[0-9]+ = self\\.x \\+ 1 in \\(\\s*self\\.x <- __assign_[0-9]+;", "")
		], "incX updates field");

		final mainPath = outDir + "/ClassMain.ml";
		if (!sys.FileSystem.exists(mainPath)) throw "missing output: " + mainPath;
		final mainMl = sys.io.File.getContent(mainPath);
		assertContains(mainMl, "Point.create 1 2", "new -> create");
		assertContains(mainMl, "Point.incX p ()", "method call (no args)");
		assertContains(mainMl, "Point.add p 3 4", "method call (args)");
		assertContains(mainMl, "Point.sum p ()", "method call returning int");
	}
}
