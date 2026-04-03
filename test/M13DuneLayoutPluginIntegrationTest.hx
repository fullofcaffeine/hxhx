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

	static function exeNameFromOutDir(outDir:String):String {
		final base = haxe.io.Path.withoutDirectory(haxe.io.Path.normalize(outDir));
		final out = new StringBuf();
		for (i in 0...base.length) {
			final c = base.charCodeAt(i);
			final isAlphaNum = (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57);
			out.add(isAlphaNum ? String.fromCharCode(c) : "_");
		}
		var s = out.toString();
		if (s.length == 0)
			s = "ocaml_app";
		if (s.charCodeAt(0) >= 48 && s.charCodeAt(0) <= 57)
			s = "_" + s;
		return s.toLowerCase();
	}

	static function runCompile(outDir:String, duneLayout:String, extraDefines:Array<String>):M13DuneLayoutPluginCompileResult {
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
		for (define in extraDefines) {
			args.push("-D");
			args.push(define);
		}
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

		final pluginCompile = runCompile(outDir, "plugin", []);
		if (pluginCompile.exitCode != 0) {
			throw "haxe compile failed for ocaml_dune_layout=plugin: " + pluginCompile.exitCode + "\n" + pluginCompile.stderr;
		}

		final dunePath = outDir + "/dune";
		if (!sys.FileSystem.exists(dunePath))
			throw "missing dune file: " + dunePath;

		final dune = sys.io.File.getContent(dunePath);
		assertContains(dune, "(executable", "dune: plugin executable stanza");
		assertContains(dune, "(modes (native plugin) (byte plugin))", "dune: plugin modes");
		assertContains(dune, "(libraries hx_runtime", "dune: depends on hx_runtime");
		if (dune.indexOf("(library") >= 0 || dune.indexOf("(executables") >= 0) {
			throw "dune: expected single plugin executable stanza";
		}

		final exeName = exeNameFromOutDir(outDir);
		final entryPath = outDir + "/" + exeName + ".ml";
		if (!sys.FileSystem.exists(entryPath))
			throw "missing plugin entry module: " + entryPath;
		final entryContent = sys.io.File.getContent(entryPath);
		assertContains(entryContent, "let () = ()", "plugin entry should be a no-op");
		if (entryContent.indexOf("Pkg_M13MliMain.main") >= 0)
			throw "plugin entry should not call the main module";

		if (Sys.command("sh", ["-c", "command -v dune >/dev/null 2>&1 && command -v ocamlc >/dev/null 2>&1"]) == 0) {
			final prev = Sys.getCwd();
			Sys.setCwd(outDir);
			final buildCode = Sys.command("dune", ["build", "./" + exeName + ".cma", "./" + exeName + ".cmxs"]);
			Sys.setCwd(prev);
			if (buildCode != 0)
				throw "dune build failed for plugin layout: " + buildCode;
		}

		final invalidOutDir = "out_ocaml_m13_dune_plugin_invalid_" + Std.string(Std.int(Date.now().getTime()));
		sys.FileSystem.createDirectory(invalidOutDir);
		final filteredOutDir = "out_ocaml_m13_dune_plugin_filtered_" + Std.string(Std.int(Date.now().getTime()));
		sys.FileSystem.createDirectory(filteredOutDir);
		final filteredCompile = runCompile(filteredOutDir, "plugin", [
			"ocaml_plugin_mode=1",
			"ocaml_emit_exclude_packages=haxe.iterators",
			"ocaml_emit_exclude_paths=Any,HxTypeRegistry"
		]);
		if (filteredCompile.exitCode != 0) {
			throw "haxe compile failed for filtered ocaml_dune_layout=plugin: " + filteredCompile.exitCode + "\n" + filteredCompile.stderr;
		}
		final filteredDunePath = filteredOutDir + "/dune";
		if (!sys.FileSystem.exists(filteredDunePath))
			throw "missing filtered dune file: " + filteredDunePath;
		if (sys.FileSystem.exists(filteredOutDir + "/Haxe.ml"))
			throw "plugin mode should disable package alias emission by default";
		if (sys.FileSystem.exists(filteredOutDir + "/haxe_iterators_ArrayIterator.ml"))
			throw "expected excluded package output to be pruned";
		if (sys.FileSystem.exists(filteredOutDir + "/Any.ml"))
			throw "expected excluded path output to be pruned (Any.ml)";
		if (sys.FileSystem.exists(filteredOutDir + "/HxTypeRegistry.ml"))
			throw "expected excluded path output to be pruned (HxTypeRegistry.ml)";
		final filteredExeName = exeNameFromOutDir(filteredOutDir);
		if (!sys.FileSystem.exists(filteredOutDir + "/" + filteredExeName + ".ml"))
			throw "filtered plugin layout should still emit the plugin entry module";
		if (Sys.command("sh", ["-c", "command -v dune >/dev/null 2>&1 && command -v ocamlc >/dev/null 2>&1"]) == 0) {
			final prev = Sys.getCwd();
			Sys.setCwd(filteredOutDir);
			final buildCode = Sys.command("dune", ["build", "./" + filteredExeName + ".cma", "./" + filteredExeName + ".cmxs"]);
			Sys.setCwd(prev);
			if (buildCode != 0)
				throw "dune build failed for filtered plugin layout: " + buildCode;
		}

		final invalidCompile = runCompile(invalidOutDir, "weird", []);
		if (invalidCompile.exitCode == 0)
			throw "invalid ocaml_dune_layout should fail";
		final invalidOutput = invalidCompile.stdout + "\n" + invalidCompile.stderr;
		assertContains(invalidOutput, "ocaml_dune_layout", "invalid layout should mention define");
		assertContains(invalidOutput, "exe|lib|plugin", "invalid layout should mention expected values");
	}
}
