class M13DuneMultiExeIntegrationTest {
	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) < 0) throw label + ": expected to find '" + needle + "'";
	}

	static function main() {
		final outDir = "out_ocaml_m13_dune_exes_" + Std.string(Std.int(Date.now().getTime()));
		sys.FileSystem.createDirectory(outDir);

		final args = [
			"-cp", "test",
			"-main", "pkg.M13MliMain",
			"--no-output",
			"-lib", "reflaxe.ocaml",
			"-D", "no-traces",
			"-D", "no_traces",
			"-D", "ocaml_no_build",
			"-D", "ocaml_output=" + outDir,
			"-D", "ocaml_dune_exes=foo:pkg.M13MliMain,bar:pkg.M13MliMain"
		];

		final exitCode = Sys.command("haxe", args);
		if (exitCode != 0) throw "haxe compile failed: " + exitCode;

		final dunePath = outDir + "/dune";
		if (!sys.FileSystem.exists(dunePath)) throw "missing dune file: " + dunePath;
		final dune = sys.io.File.getContent(dunePath);

		assertContains(dune, "(executables", "dune: executables stanza");
		assertContains(dune, "(names foo bar)", "dune: names list");
		assertContains(dune, "(libraries hx_runtime", "dune: depends on hx_runtime");

		final fooPath = outDir + "/foo.ml";
		final barPath = outDir + "/bar.ml";
		if (!sys.FileSystem.exists(fooPath)) throw "missing entry module: " + fooPath;
		if (!sys.FileSystem.exists(barPath)) throw "missing entry module: " + barPath;
		final foo = sys.io.File.getContent(fooPath);
		final bar = sys.io.File.getContent(barPath);
		assertContains(foo, "ignore (Pkg_M13MliMain.main ())", "foo calls main");
		assertContains(bar, "ignore (Pkg_M13MliMain.main ())", "bar calls main");
	}
}

