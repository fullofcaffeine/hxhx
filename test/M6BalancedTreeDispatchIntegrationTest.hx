class M6BalancedTreeDispatchIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function hasCommand(cmd:String):Bool {
		try {
			final process = new sys.io.Process(cmd, ["--version"]);
			final code = process.exitCode();
			process.close();
			return code == 0;
		} catch (_) {
			return false;
		}
	}

	static function exeNameFromOutDir(outDir:String):String {
		final base = haxe.io.Path.withoutDirectory(haxe.io.Path.normalize(outDir));
		final out = new StringBuf();
		for (index in 0...base.length) {
			final code = base.charCodeAt(index);
			final isAlphaNum = (code >= 97 && code <= 122) || (code >= 65 && code <= 90) || (code >= 48 && code <= 57);
			out.add(isAlphaNum ? String.fromCharCode(code) : "_");
		}
		var name = out.toString();
		if (name.length == 0)
			name = "ocaml_app";
		if (name.charCodeAt(0) >= 48 && name.charCodeAt(0) <= 57)
			name = "_" + name;
		return name.toLowerCase();
	}

	static function main() {
		final outDir = "out_ocaml_m6_balanced_tree_dispatch_" + Std.string(Std.int(Date.now().getTime()));
		sys.FileSystem.createDirectory(outDir);

		final args = [
			"-cp",
			"test",
			"-main",
			"BalancedTreeDispatchMain",
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

		final compileExit = Sys.command("haxe", args);
		assertTrue(compileExit == 0, "haxe compile failed: " + compileExit);

		final generatedPath = outDir + "/haxe_ds_BalancedTree.ml";
		assertTrue(sys.FileSystem.exists(generatedPath), "missing generated balanced tree module: " + generatedPath);

		if (!hasCommand("dune") || !hasCommand("ocamlc")) {
			Sys.println("Skipping dune verification: dune/ocamlc not available.");
			return;
		}

		final exeName = exeNameFromOutDir(outDir);
		final previousCwd = Sys.getCwd();
		Sys.setCwd(outDir);
		final buildExit = Sys.command("dune", ["build", "./" + exeName + ".exe"]);
		assertTrue(buildExit == 0, "dune build failed: " + buildExit);

		final builtExe = "_build/default/" + exeName + ".exe";
		assertTrue(sys.FileSystem.exists(builtExe), "missing built executable: " + builtExe);

		final outputPath = "run.stdout";
		final runExit = Sys.command("sh", ["-c", "./" + builtExe + " > " + outputPath]);
		assertTrue(runExit == 0, "built executable failed: " + runExit);
		final output = StringTools.trim(sys.io.File.getContent(outputPath));
		assertTrue(output == "true", "unexpected executable output: " + output);

		Sys.setCwd(previousCwd);
	}
}
