class M2IntegrationTest {
	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) < 0) {
			throw label + ": expected to find '" + needle + "'";
		}
	}

	static function assertNotContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) >= 0) {
			throw label + ": expected to NOT find '" + needle + "'";
		}
	}

	static function hasCommand(cmd:String):Bool {
		try {
			final p = new sys.io.Process(cmd, ["--version"]);
			final code = p.exitCode();
			p.close();
			return code == 0;
		} catch (_) {
			return false;
		}
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

	static function main() {
		final outDir = "out_ocaml_m2_integration_" + Std.string(Std.int(Date.now().getTime()));
		sys.FileSystem.createDirectory(outDir);

		final args = [
			"-cp",
			"test",
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
			"ocaml_output=" + outDir
		];

		final exitCode = Sys.command("haxe", args);
		if (exitCode != 0)
			throw "haxe compile failed: " + exitCode;

		final mainPath = outDir + "/Main.ml";
		if (!sys.FileSystem.exists(mainPath))
			throw "missing output: " + mainPath;

		final content = sys.io.File.getContent(mainPath);

		assertContains(content, "let main", "main binding");
		assertContains(content, "ref", "ref locals");
		assertContains(content, ":=", "assignment");
		assertContains(content, "while", "while loop");
		assertContains(content, "match", "switch->match");
		assertContains(content, "| 1 | 2 ->", "multi-case or-pattern");
		assertNotContains(content, "let y = ref", "immutable y");

		final exeName = exeNameFromOutDir(outDir);
		final entryPath = outDir + "/" + exeName + ".ml";
		if (!sys.FileSystem.exists(entryPath))
			throw "missing output: " + entryPath;
		final entry = sys.io.File.getContent(entryPath);
		assertContains(entry, "Main.main ()", "entrypoint");

		// Best-effort: if dune+ocamlc are available, ensure dune build succeeds.
		if (hasCommand("dune") && hasCommand("ocamlc")) {
			final prev = Sys.getCwd();
			Sys.setCwd(outDir);
			final exit = Sys.command("dune", ["build", "./" + exeName + ".exe"]);
			if (exit == 0) {
				final builtExe = "_build/default/" + exeName + ".exe";
				if (sys.FileSystem.exists(builtExe)) {
					final runExit = Sys.command("./" + builtExe, []);
					if (runExit != 0)
						throw "built exe failed: " + runExit;
				}
			}
			Sys.setCwd(prev);
			if (exit != 0)
				throw "dune build failed: " + exit;
		}
	}
}
