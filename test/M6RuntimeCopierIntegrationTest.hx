class M6RuntimeCopierIntegrationTest {
	static function compareStrings(a:String, b:String):Int {
		return a < b ? -1 : (a > b ? 1 : 0);
	}

	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) < 0) {
			throw label + ": expected to find '" + needle + "'";
		}
	}

	static function assertNotContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) >= 0) {
			throw label + ": expected to not find '" + needle + "'";
		}
	}

	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function compileRuntimeFixture(outDir:String, profile:Null<String>):Void {
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
			"ocaml_no_build",
			"-D",
			"ocaml_output=" + outDir
		];
		if (profile != null) {
			args.push("-D");
			args.push("ocaml_profile=" + profile);
		}

		final exitCode = Sys.command("haxe", args);
		if (exitCode != 0)
			throw "haxe compile failed: " + exitCode;
	}

	static function runtimeModules(outDir:String):Array<String> {
		final runtimeDir = outDir + "/runtime";
		if (!sys.FileSystem.exists(runtimeDir))
			throw "missing runtime dir: " + runtimeDir;
		final modules:Array<String> = [];
		for (name in sys.FileSystem.readDirectory(runtimeDir)) {
			if (StringTools.endsWith(name, ".ml"))
				modules.push(name);
		}
		modules.sort(compareStrings);
		return modules;
	}

	static function main() {
		final rootOutDir = "out_ocaml_m6_runtime_" + Std.string(Std.int(Date.now().getTime()));
		final portableOutDir = rootOutDir + "/portable";
		final metalOutDir = rootOutDir + "/metal";
		sys.FileSystem.createDirectory(rootOutDir);

		compileRuntimeFixture(portableOutDir, null);
		compileRuntimeFixture(metalOutDir, "metal");

		final runtimePath = portableOutDir + "/runtime/HxRuntime.ml";
		if (!sys.FileSystem.exists(runtimePath))
			throw "missing runtime: " + runtimePath;

		final dunePath = portableOutDir + "/dune";
		if (!sys.FileSystem.exists(dunePath))
			throw "missing dune file: " + dunePath;
		final dune = sys.io.File.getContent(dunePath);
		assertContains(dune, "(libraries hx_runtime", "dune links runtime lib");

		final rtDunePath = portableOutDir + "/runtime/dune";
		if (!sys.FileSystem.exists(rtDunePath))
			throw "missing runtime dune: " + rtDunePath;
		final rtDune = sys.io.File.getContent(rtDunePath);
		assertContains(rtDune, "(library", "runtime dune has library stanza");
		assertContains(rtDune, "(name hx_runtime)", "runtime dune library name");

		final portableModules = runtimeModules(portableOutDir);
		final metalModules = runtimeModules(metalOutDir);

		assertTrue(portableModules.length > 0, "portable runtime should include modules");
		assertTrue(metalModules.length > 0, "metal runtime should include modules");
		assertTrue(metalModules.length < portableModules.length, "metal runtime should link fewer modules than portable");

		final portableJoined = "\n" + portableModules.join("\n") + "\n";
		final metalJoined = "\n" + metalModules.join("\n") + "\n";

		assertContains(portableJoined, "\nHxRuntime.ml\n", "portable runtime includes HxRuntime");
		assertContains(portableJoined, "\nHxFile.ml\n", "portable runtime includes file runtime");
		assertContains(portableJoined, "\nHxFileSystem.ml\n", "portable runtime includes filesystem runtime");

		assertContains(metalJoined, "\nHxRuntime.ml\n", "metal runtime includes HxRuntime");
		assertNotContains(metalJoined, "\nHxFile.ml\n", "metal runtime omits unused file runtime");
		assertNotContains(metalJoined, "\nHxFileSystem.ml\n", "metal runtime omits unused filesystem runtime");
		assertNotContains(metalJoined, "\nHxFileStream.ml\n", "metal runtime omits unused file stream runtime");
		assertNotContains(metalJoined, "\nHxReflect.ml\n", "metal runtime omits unused reflect runtime");
		assertNotContains(metalJoined, "\nHxSys.ml\n", "metal runtime omits unused sys runtime");
	}
}
