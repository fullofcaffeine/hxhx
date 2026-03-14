class M6JsonPrinterIntegrationTest {
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

	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) < 0)
			throw label + ": expected to find '" + needle + "'";
	}

	static function assertEquals(actual:String, expected:String, label:String):Void {
		if (actual != expected)
			throw label + ": expected '" + expected + "' but got '" + actual + "'";
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
		final outDir = "out_ocaml_m6_json_printer_" + Std.string(Std.int(Date.now().getTime()));
		sys.FileSystem.createDirectory(outDir);

		final args = [
			"-cp",
			"test/portable/fixtures/haxe_format_json_basic/src",
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
			"ocaml_output=" + outDir,
			"-D",
			"ocaml_no_build"
		];

		final exitCode = Sys.command("haxe", args);
		if (exitCode != 0)
			throw "haxe compile failed: " + exitCode;

		final mainPath = outDir + "/Main.ml";
		if (!sys.FileSystem.exists(mainPath))
			throw "missing output: " + mainPath;

		final content = sys.io.File.getContent(mainPath);
		assertContains(content, "Haxe_format_JsonPrinter.print", "generated code should call JsonPrinter override");
		assertContains(content, "Haxe_format_JsonParser.parse", "generated code should call JsonParser override");

		if (hasCommand("dune") && hasCommand("ocamlc")) {
			final exeName = exeNameFromOutDir(outDir);
			final prev = Sys.getCwd();
			Sys.setCwd(outDir);
			final buildExit = Sys.command("dune", ["build", "./" + exeName + ".exe"]);
			Sys.setCwd(prev);
			if (buildExit != 0)
				throw "dune build failed: " + buildExit;

			Sys.setCwd(outDir);
			final runProcess = new sys.io.Process("dune", ["exec", "./" + exeName + ".exe"]);
			final stdout = runProcess.stdout.readAll().toString();
			final stderr = runProcess.stderr.readAll().toString();
			final runExit = runProcess.exitCode();
			runProcess.close();
			Sys.setCwd(prev);
			if (runExit != 0)
				throw "dune exec failed: " + runExit + "\n" + stderr;

			final lines = [for (line in stdout.split("\n")) if (line != "") line];
			assertEquals(lines[0], "name=hx", "parsed name");
			assertEquals(lines[1], "sum=6", "parsed sum");
			assertEquals(lines[2], "ok=true", "parsed ok");
			assertEquals(lines[3], "answer=42", "encoded answer");
			assertEquals(lines[4], "text=hello", "encoded text");
			assertEquals(lines[5], "flag=false", "encoded flag");
		}
	}
}
