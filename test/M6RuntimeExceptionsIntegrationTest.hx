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
		assertContains(mainMl, "HxRuntime.hx_try", "try->hx_try");
		assertContains(mainMl, "HxRuntime.hx_throw", "throw->hx_throw");
		assertContains(mainMl, "Obj.repr", "throw boxes value");

		final rtPath = outDir + "/runtime/HxRuntime.ml";
		if (!sys.FileSystem.exists(rtPath)) throw "missing runtime: " + rtPath;
		final rtMl = sys.io.File.getContent(rtPath);
		assertContains(rtMl, "let hx_try", "runtime defines hx_try");
	}
}

