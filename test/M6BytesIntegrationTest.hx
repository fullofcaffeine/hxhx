class M6BytesIntegrationTest {
	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) < 0) {
			throw label + ": expected to find '" + needle + "'";
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
		if (s.length == 0) s = "ocaml_app";
		if (s.charCodeAt(0) >= 48 && s.charCodeAt(0) <= 57) s = "_" + s;
		return s.toLowerCase();
	}

	static function main() {
		final outDir = "out_ocaml_m6_bytes_" + Std.string(Std.int(Date.now().getTime()));
		sys.FileSystem.createDirectory(outDir);

		final args = [
			"-cp", "test",
			"-main", "BytesMain",
			"--no-output",
			"-lib", "reflaxe.ocaml",
			"-D", "no-traces",
			"-D", "no_traces",
			"-D", "ocaml_no_build",
			"-D", "ocaml_output=" + outDir
		];

		final exitCode = Sys.command("haxe", args);
		if (exitCode != 0) throw "haxe compile failed: " + exitCode;

		final runtimePath = outDir + "/runtime/HxBytes.ml";
		if (!sys.FileSystem.exists(runtimePath)) throw "missing runtime: " + runtimePath;

		final mainPath = outDir + "/BytesMain.ml";
		if (!sys.FileSystem.exists(mainPath)) throw "missing output: " + mainPath;

		final content = sys.io.File.getContent(mainPath);
		assertContains(content, "HxBytes.alloc", "alloc");
		assertContains(content, "HxBytes.ofString", "ofString");
		assertContains(content, "HxBytes.length", "length");
		assertContains(content, "HxBytes.get", "get");
		assertContains(content, "HxBytes.set", "set");
		assertContains(content, "HxBytes.blit", "blit");
		assertContains(content, "HxBytes.sub", "sub");
		assertContains(content, "HxBytes.compare", "compare");
		assertContains(content, "HxBytes.getString", "getString");
		assertContains(content, "HxBytes.toString", "toString");
		assertContains(content, "HxBytes.fill", "fill");

		// Best-effort: if dune+ocamlc are available, ensure dune build + run succeeds.
		if (hasCommand("dune") && hasCommand("ocamlc")) {
			final exeName = exeNameFromOutDir(outDir);
			final prev = Sys.getCwd();
			Sys.setCwd(outDir);
			final exit = Sys.command("dune", ["build", "./" + exeName + ".exe"]);
			if (exit == 0) {
				final builtExe = "_build/default/" + exeName + ".exe";
				if (sys.FileSystem.exists(builtExe)) {
					final runExit = Sys.command("./" + builtExe, []);
					if (runExit != 0) throw "built exe failed: " + runExit;
				}
			}
			Sys.setCwd(prev);
			if (exit != 0) throw "dune build failed: " + exit;
		}
	}
}

