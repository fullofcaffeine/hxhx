class M8EntrypointFallbackIntegrationTest {
	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) < 0) {
			throw label + ": expected to find '" + needle + "'";
		}
	}

	static function assertNotContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) >= 0) {
			throw label + ": expected to not find '" + needle + "'";
		}
	}

	static function main() {
		final outDir = "out_ocaml_m8_entrypoint_fallback_" + Std.string(Std.int(Date.now().getTime()));
		sys.FileSystem.createDirectory(outDir);

		final args = [
			"-cp",
			"test/portable/fixtures/haxe_core_bucket01_basic/src",
			"-main",
			"Main",
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
			"ocaml_output=" + outDir
		];

		final exitCode = Sys.command("haxe", args);
		if (exitCode != 0)
			throw "haxe compile failed: " + exitCode;

		final dunePath = outDir + "/dune";
		if (!sys.FileSystem.exists(dunePath))
			throw "missing dune file: " + dunePath;
		final dune = sys.io.File.getContent(dunePath);

		final needle = "(name ";
		final start = dune.indexOf(needle);
		if (start < 0)
			throw "failed to find '(name ...)' in dune file";
		final end = dune.indexOf(")", start);
		if (end < 0)
			throw "failed to parse exe name from dune file";

		final exeName = StringTools.trim(dune.substr(start + needle.length, end - (start + needle.length)));
		final entryPath = outDir + "/" + exeName + ".ml";
		if (!sys.FileSystem.exists(entryPath))
			throw "missing entry module: " + entryPath;

		final entry = sys.io.File.getContent(entryPath);
		assertContains(entry, "Main.main ()", "entry should call inferred Main.main");
		assertNotContains(entry, "let () = ()", "entry should not fall back to noop");
	}
}
