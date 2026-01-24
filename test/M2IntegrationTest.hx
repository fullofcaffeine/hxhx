class M2IntegrationTest {
	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) < 0) {
			throw label + ": expected to find '" + needle + "'";
		}
	}

	static function main() {
		final outDir = "out_ocaml_m2_integration_" + Std.string(Std.int(Date.now().getTime()));
		sys.FileSystem.createDirectory(outDir);

		final args = [
			"-cp", "test",
			"-main", "Main",
			"--no-output",
			"-lib", "reflaxe.ocaml",
			"-D", "no-traces",
			"-D", "no_traces",
			"-D", "ocaml_output=" + outDir
		];

		final exitCode = Sys.command("haxe", args);
		if (exitCode != 0) throw "haxe compile failed: " + exitCode;

		final mainPath = outDir + "/Main.ml";
		if (!sys.FileSystem.exists(mainPath)) throw "missing output: " + mainPath;

		final content = sys.io.File.getContent(mainPath);

		assertContains(content, "let main", "main binding");
		assertContains(content, "ref", "ref locals");
		assertContains(content, ":=", "assignment");
		assertContains(content, "while", "while loop");
		assertContains(content, "match", "switch->match");
		assertContains(content, "| 1 | 2 ->", "multi-case or-pattern");
		assertContains(content, "let () = main ()", "entrypoint");
	}
}

