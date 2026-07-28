class M6HttpNullableBytesIntegrationTest {
	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) < 0) {
			throw label + ": expected to find '" + needle + "'";
		}
	}

	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition) {
			throw message;
		}
	}

	static function hasCommand(cmd:String):Bool {
		try {
			final p = new sys.io.Process(cmd, ["--version"]);
			final code = p.exitCode();
			p.close();
			return code == 0;
		} catch (_:haxe.Exception) {
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
		if (s.length == 0) {
			s = "ocaml_app";
		}
		if (s.charCodeAt(0) >= 48 && s.charCodeAt(0) <= 57) {
			s = "_" + s;
		}
		return s.toLowerCase();
	}

	static function main() {
		final outDir = "out_ocaml_m6_http_nullable_bytes_" + Std.string(Std.int(Date.now().getTime()));
		sys.FileSystem.createDirectory(outDir);

		final args = [
			"-cp",
			"test",
			"-main",
			"HttpNullableBytesMain",
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
			"ocaml_portable_native_surface=error"
		];

		final exitCode = Sys.command("haxe", args);
		if (exitCode != 0) {
			throw "haxe compile failed: " + exitCode;
		}

		final httpBasePath = outDir + "/haxe_http_HttpBase.ml";
		if (!sys.FileSystem.exists(httpBasePath)) {
			throw "missing output: " + httpBasePath;
		}

		final httpBaseContent = sys.io.File.getContent(httpBasePath);
		assertContains(httpBaseContent, "responseAsString", "response getter emitted");
		assertTrue(httpBaseContent.indexOf("(() : string)") < 0, "responseData getter must not lower to unit placeholder");
		final hasBytesStringLowering = httpBaseContent.indexOf("HxBytes.getString") >= 0
			|| httpBaseContent.indexOf("HxBytes.toString") >= 0;
		assertTrue(hasBytesStringLowering, "responseData getter should lower via HxBytes string helpers");
		assertContains(httpBaseContent, "HxRuntime.is_null (Obj.repr __bytes_receiver_input_", "nullable response body receiver check");
		assertContains(httpBaseContent, 'HxRuntime.hx_throw_typed (Obj.repr "Null Access") ["String"; "Dynamic"]', "nullable response body failure");

		if (hasCommand("dune") && hasCommand("ocamlc")) {
			final exeName = exeNameFromOutDir(outDir);
			final prevCwd = Sys.getCwd();
			Sys.setCwd(outDir);
			final buildExit = Sys.command("dune", ["build", "./" + exeName + ".exe"]);
			Sys.setCwd(prevCwd);
			if (buildExit != 0) {
				throw "dune build failed: " + buildExit;
			}

			final runExit = Sys.command("./" + outDir + "/_build/default/" + exeName + ".exe", []);
			if (runExit != 0) {
				throw "compiled executable failed: " + runExit;
			}
		}
	}
}
