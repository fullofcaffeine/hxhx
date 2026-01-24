class M3IntegrationTest {
	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) < 0) {
			throw label + ": expected to find '" + needle + "'";
		}
	}

	static function assertNotContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) >= 0) {
			throw label + ": expected to NOT find '" + needle + "'";
		}
	}

	static function main() {
		final outDir = "out_ocaml_m3_integration_" + Std.string(Std.int(Date.now().getTime()));
		sys.FileSystem.createDirectory(outDir);

		final args = [
			"-cp", "test",
			"-main", "ClosureMain",
			"--no-output",
			"-lib", "reflaxe.ocaml",
			"-D", "no-traces",
			"-D", "no_traces",
			"-D", "ocaml_output=" + outDir
		];

		final exitCode = Sys.command("haxe", args);
		if (exitCode != 0) throw "haxe compile failed: " + exitCode;

		final path = outDir + "/ClosureMain.ml";
		if (!sys.FileSystem.exists(path)) throw "missing output: " + path;
		final content = sys.io.File.getContent(path);

		assertContains(content, "let x = ref", "captured local becomes ref");
		assertContains(content, "x :=", "assignment becomes :=");
		assertContains(content, "!x", "reads become deref");

		// Ensure closure itself isn't forced into a ref by default.
		assertNotContains(content, "let bump = ref", "closure binding not ref");
	}
}

