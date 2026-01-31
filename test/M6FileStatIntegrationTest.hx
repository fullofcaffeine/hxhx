class M6FileStatIntegrationTest {
	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) < 0) {
			throw label + ": expected to find '" + needle + "'";
		}
	}

	static function main() {
		final outDir = "out_ocaml_m6_filestat_" + Std.string(Std.int(Date.now().getTime()));
		sys.FileSystem.createDirectory(outDir);

		final args = [
			"-cp", "test",
			"-main", "FileStatMain",
			"--no-output",
			"-lib", "reflaxe.ocaml",
			"-D", "no-traces",
			"-D", "no_traces",
			"-D", "ocaml_no_build",
			"-D", "ocaml_output=" + outDir
		];

		final exitCode = Sys.command("haxe", args);
		if (exitCode != 0) throw "haxe compile failed: " + exitCode;

		final runtimePath = outDir + "/runtime/HxFileSystem.ml";
		if (!sys.FileSystem.exists(runtimePath)) throw "missing runtime: " + runtimePath;

		final dateRuntimePath = outDir + "/runtime/Date.ml";
		if (!sys.FileSystem.exists(dateRuntimePath)) throw "missing runtime: " + dateRuntimePath;

		final mainPath = outDir + "/FileStatMain.ml";
		if (!sys.FileSystem.exists(mainPath)) throw "missing output: " + mainPath;

		final content = sys.io.File.getContent(mainPath);
		assertContains(content, "HxFileSystem.stat", "FileSystem.stat lowering");
		assertContains(content, ".size", "FileStat.size field access");
		assertContains(content, "Date.getTime", "Date.getTime call");
	}
}

