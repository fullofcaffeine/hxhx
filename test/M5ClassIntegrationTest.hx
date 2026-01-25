class M5ClassIntegrationTest {
	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) < 0) {
			throw label + ": expected to find '" + needle + "'";
		}
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
		assertContains(pointMl, "type t = { mutable x : int; mutable y : int }", "record type decl");
		final createRe = ~/let create = fun ([A-Za-z_][A-Za-z0-9_]*) ([A-Za-z_][A-Za-z0-9_]*) ->/;
		if (!createRe.match(pointMl)) throw "create fn: expected to find 'let create = fun <x> <y> ->'";
		final xArg = createRe.matched(1);
		final yArg = createRe.matched(2);
		assertContains(pointMl, "self.x <- " + xArg, "ctor assigns x");
		assertContains(pointMl, "self.y <- " + yArg, "ctor assigns y");
		assertContains(pointMl, "incX = fun self () ->", "instance method incX");
		assertContains(pointMl, "self.x <- self.x + 1", "incX updates field");

		final mainPath = outDir + "/ClassMain.ml";
		if (!sys.FileSystem.exists(mainPath)) throw "missing output: " + mainPath;
		final mainMl = sys.io.File.getContent(mainPath);
		assertContains(mainMl, "Point.create 1 2", "new -> create");
		assertContains(mainMl, "Point.incX p ()", "method call (no args)");
		assertContains(mainMl, "Point.add p 3 4", "method call (args)");
		assertContains(mainMl, "Point.sum p ()", "method call returning int");
	}
}
