class M6RuntimeExceptionsIntegrationTest {
	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) < 0) {
			throw label + ": expected to find '" + needle + "'";
		}
	}

	static function main() {
		final outDir = "out_ocaml_m6_exn_" + Std.string(Std.int(Date.now().getTime()));
		sys.FileSystem.createDirectory(outDir);

		final args = [
			"-cp", "test",
			"-main", "TryMain",
			"--no-output",
			"-lib", "reflaxe.ocaml",
			"-D", "no-traces",
			"-D", "no_traces",
			"-D", "ocaml_no_build",
			"-D", "ocaml_output=" + outDir
		];

		final exitCode = Sys.command("haxe", args);
		if (exitCode != 0) throw "haxe compile failed: " + exitCode;

		final mainPath = outDir + "/TryMain.ml";
		if (!sys.FileSystem.exists(mainPath)) throw "missing output: " + mainPath;
		final mainMl = sys.io.File.getContent(mainPath);
		assertContains(mainMl, "try ", "try lowers to OCaml try");
		assertContains(mainMl, "HxRuntime.Hx_exception", "catch matches Hx_exception");
		assertContains(mainMl, "HxRuntime.hx_throw_typed", "throw->hx_throw_typed");
		assertContains(mainMl, "Obj.repr", "throw boxes value");

		final rtPath = outDir + "/runtime/HxRuntime.ml";
		if (!sys.FileSystem.exists(rtPath)) throw "missing runtime: " + rtPath;
		final rtMl = sys.io.File.getContent(rtPath);
		assertContains(rtMl, "let hx_throw_typed", "runtime defines hx_throw_typed");
		assertContains(rtMl, "let tags_has", "runtime defines tags_has");
	}
}
