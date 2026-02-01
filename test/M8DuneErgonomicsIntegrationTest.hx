class M8DuneErgonomicsIntegrationTest {
	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) < 0) {
			throw label + ": expected to find '" + needle + "'";
		}
	}

	static function main() {
		final outDir = "out_ocaml_m8_dune_" + Std.string(Std.int(Date.now().getTime()));
		sys.FileSystem.createDirectory(outDir);

		final args = [
			"-cp", "test",
			"-main", "pkg.M8DuneErgonomicsMain",
			"--no-output",
			"-lib", "reflaxe.ocaml",
			"-D", "no-traces",
			"-D", "no_traces",
			"-D", "ocaml_no_build",
			"-D", "ocaml_output=" + outDir,
			"-D", "ocaml_dune_libraries=unix,extlib"
		];

		final exitCode = Sys.command("haxe", args);
		if (exitCode != 0) throw "haxe compile failed: " + exitCode;

		// Dune deps: ensure ocaml_dune_libraries is reflected in dune files.
		final dunePath = outDir + "/dune";
		if (!sys.FileSystem.exists(dunePath)) throw "missing dune file: " + dunePath;
		final dune = sys.io.File.getContent(dunePath);
		assertContains(dune, "(libraries hx_runtime unix extlib)", "dune libraries include extlib");

		// Entry inference: find executable name and ensure entry file calls the correct main module.
		final needle = "(name ";
		final start = dune.indexOf(needle);
		if (start < 0) throw "failed to find '(name ...)' in dune file";
		final end = dune.indexOf(")", start);
		if (end < 0) throw "failed to parse exe name from dune file";
		final exeName = StringTools.trim(dune.substr(start + needle.length, end - (start + needle.length)));
		final entryPath = outDir + "/" + exeName + ".ml";
		if (!sys.FileSystem.exists(entryPath)) throw "missing entry module: " + entryPath;
		final entry = sys.io.File.getContent(entryPath);
		assertContains(entry, "Pkg_M8DuneErgonomicsMain.main ()", "entry calls main module");
	}
}
