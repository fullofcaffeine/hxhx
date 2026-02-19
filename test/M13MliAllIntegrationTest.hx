class M13MliAllIntegrationTest {
	static function main() {
		final outDir = "out_ocaml_m13_mli_all_" + Std.string(Std.int(Date.now().getTime()));
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
			"ocaml_output=" + outDir,
			"-D",
			"ocaml_build=byte",
			"-D",
			"ocaml_mli=all"
		];

		final exitCode = Sys.command("haxe", args);
		if (exitCode != 0)
			throw "haxe compile failed: " + exitCode;

		// This module is emitted by default but is not necessarily in the executable dependency
		// closure. `ocaml_mli=all` should still infer its interface.
		final callStackMli = outDir + "/haxe_CallStack.mli";
		if (!sys.FileSystem.exists(callStackMli))
			throw "missing inferred .mli: " + callStackMli;
	}
}
