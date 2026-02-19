class M13DuneLayoutLibIntegrationTest {
	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) < 0)
			throw label + ": expected to find '" + needle + "'";
	}

	static function main() {
		final outDir = "out_ocaml_m13_dune_lib_" + Std.string(Std.int(Date.now().getTime()));
		sys.FileSystem.createDirectory(outDir);

		final args = [
			"-cp",
			"test",
			"-main",
			"pkg.M13MliMain",
			"--no-output",
			"-lib",
			"reflaxe.ocaml",
			"-D",
			"no-traces",
			"-D",
			"no_traces",
			"-D",
			"ocaml_no_build",
			"-D",
			"ocaml_output=" + outDir,
			"-D",
			"ocaml_dune_layout=lib"
		];

		final exitCode = Sys.command("haxe", args);
		if (exitCode != 0)
			throw "haxe compile failed: " + exitCode;

		final dunePath = outDir + "/dune";
		if (!sys.FileSystem.exists(dunePath))
			throw "missing dune file: " + dunePath;
		final dune = sys.io.File.getContent(dunePath);
		assertContains(dune, "(library", "dune: library stanza");
		assertContains(dune, "(libraries hx_runtime", "dune: depends on hx_runtime");

		// Ensure executable stanzas aren't present in library-only mode.
		if (dune.indexOf("(executable") >= 0 || dune.indexOf("(executables") >= 0) {
			throw "dune: expected library-only layout (found executable stanza)";
		}

		// No entry module is generated for library-only outputs.
		// Sanity: there should not be a generated entry module that calls main().
		var foundEntry = false;
		for (name in sys.FileSystem.readDirectory(outDir)) {
			if (!StringTools.endsWith(name, ".ml"))
				continue;
			final content = sys.io.File.getContent(outDir + "/" + name);
			if (content.indexOf("ignore (Pkg_M13MliMain.main ())") >= 0)
				foundEntry = true;
		}
		if (foundEntry)
			throw "unexpected entry module in lib layout";
	}
}
