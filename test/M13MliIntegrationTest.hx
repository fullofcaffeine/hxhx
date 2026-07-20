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
		final manifest = OcamlArtifactManifestTestHelper.validate(outDir, "portable");
		OcamlArtifactManifestTestHelper.assertEntry(manifest, "pkg_M13MliMain.mli", "mli-generator", "inferred-interface", true);
		OcamlArtifactManifestTestHelper.assertEntry(manifest, "HxTypeRegistry.mli", "mli-generator", "inferred-interface", true);
		final firstSummary:Dynamic = Reflect.field(manifest, "summary");
		final repeatedExitCode = Sys.command("haxe", args);
		if (repeatedExitCode != 0)
			throw "repeated haxe compile failed: " + repeatedExitCode;
		final repeatedManifest = OcamlArtifactManifestTestHelper.validate(outDir, "portable");
		final repeatedSummary:Dynamic = Reflect.field(repeatedManifest, "summary");
		if (Reflect.field(firstSummary, "sourceBundleRevision") != Reflect.field(repeatedSummary, "sourceBundleRevision"))
			throw "inferred-interface source bundle changed across an identical rebuild";
		if (Reflect.field(firstSummary, "artifactSetRevision") != Reflect.field(repeatedSummary, "artifactSetRevision"))
			throw "inferred-interface artifact set changed across an identical rebuild";
	}
}
