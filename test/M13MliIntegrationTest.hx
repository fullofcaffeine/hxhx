class M13MliIntegrationTest {
	static function main() {
		final outDir = "out_ocaml_m13_mli_" + Std.string(Std.int(Date.now().getTime()));
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
			"ocaml_mli"
		];

		final exitCode = Sys.command("haxe", args);
		if (exitCode != 0)
			throw "haxe compile failed: " + exitCode;

		final mainMli = outDir + "/pkg_M13MliMain.mli";
		if (!sys.FileSystem.exists(mainMli))
			throw "missing inferred .mli: " + mainMli;

		final regMli = outDir + "/HxTypeRegistry.mli";
		if (!sys.FileSystem.exists(regMli))
			throw "missing inferred .mli: " + regMli;
	}
}
