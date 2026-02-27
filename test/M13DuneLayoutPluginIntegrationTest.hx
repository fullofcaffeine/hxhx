private typedef M13DuneLayoutPluginCompileResult = {
	final exitCode:Int;
	final stdout:String;
	final stderr:String;
}

class M13DuneLayoutPluginIntegrationTest {
	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) < 0)
			throw label + ": expected to find '" + needle + "'";
	}

	static function runCompile(outDir:String, duneLayout:String):M13DuneLayoutPluginCompileResult {
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
			"ocaml_dune_layout=" + duneLayout
		];
		final process = new sys.io.Process("haxe", args);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final exitCode = process.exitCode();
		process.close();
		return {exitCode: exitCode, stdout: stdout, stderr: stderr};
	}

	static function main() {
		final outDir = "out_ocaml_m13_dune_plugin_" + Std.string(Std.int(Date.now().getTime()));
		sys.FileSystem.createDirectory(outDir);

		final pluginCompile = runCompile(outDir, "plugin");
		if (pluginCompile.exitCode != 0) {
			throw "haxe compile failed for ocaml_dune_layout=plugin: " + pluginCompile.exitCode + "\n" + pluginCompile.stderr;
		}

		final dunePath = outDir + "/dune";
		if (!sys.FileSystem.exists(dunePath))
			throw "missing dune file: " + dunePath;

		final dune = sys.io.File.getContent(dunePath);
		assertContains(dune, "(library", "dune: plugin library stanza");
		assertContains(dune, "(kind plugin)", "dune: plugin kind");
		assertContains(dune, "(libraries hx_runtime", "dune: depends on hx_runtime");
		if (dune.indexOf("(executable") >= 0 || dune.indexOf("(executables") >= 0) {
			throw "dune: expected plugin library-only layout (found executable stanza)";
		}

		var foundEntry = false;
		for (name in sys.FileSystem.readDirectory(outDir)) {
			if (!StringTools.endsWith(name, ".ml"))
				continue;
			final content = sys.io.File.getContent(outDir + "/" + name);
			if (content.indexOf("ignore (Pkg_M13MliMain.main ())") >= 0)
				foundEntry = true;
		}
		if (foundEntry)
			throw "unexpected entry module in plugin layout";

		final invalidOutDir = "out_ocaml_m13_dune_plugin_invalid_" + Std.string(Std.int(Date.now().getTime()));
		sys.FileSystem.createDirectory(invalidOutDir);
		final invalidCompile = runCompile(invalidOutDir, "weird");
		if (invalidCompile.exitCode == 0)
			throw "invalid ocaml_dune_layout should fail";
		final invalidOutput = invalidCompile.stdout + "\n" + invalidCompile.stderr;
		assertContains(invalidOutput, "ocaml_dune_layout", "invalid layout should mention define");
		assertContains(invalidOutput, "exe|lib|plugin", "invalid layout should mention expected values");
	}
}
