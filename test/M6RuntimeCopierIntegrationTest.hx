private typedef ProfileReportVerifier = {
	final mode:String;
	final enabled:Bool;
	final result:String;
}

private typedef ProfileReport = {
	final contractVersion:Int;
	final requestedProfile:Null<String>;
	final normalizedProfile:String;
	final verifier:ProfileReportVerifier;
}

private typedef RuntimePlanReport = {
	final contractVersion:Int;
	final profile:String;
	final selectionMode:String;
	final availableModules:Array<String>;
	final trackedModules:Array<String>;
	final tokenScanFallbackEnabled:Bool;
	final selectedModules:Array<String>;
	final selectedFeatures:Array<String>;
}

private typedef CompileInvocationResult = {
	final exitCode:Int;
	final stdout:String;
	final stderr:String;
}

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

	static function assertArrayEquals(expected:Array<String>, actual:Array<String>, label:String):Void {
		if (expected.length != actual.length)
			throw label + ": length mismatch";
		for (i in 0...expected.length) {
			if (expected[i] != actual[i])
				throw label + ": mismatch at index " + Std.string(i) + " expected=" + expected[i] + " actual=" + actual[i];
		}
	}

	static function shellQuote(value:String):String {
		return "'" + StringTools.replace(value, "'", "'\"'\"'") + "'";
	}

	static function runHaxe(args:Array<String>):CompileInvocationResult {
		final tempRoot = ".tmp/m6_runtime_haxe_run_" + Std.string(Std.int(Date.now().getTime())) + "_" + Std.string(Std.random(1000000));
		sys.FileSystem.createDirectory(tempRoot);
		final stdoutPath = tempRoot + "/stdout.log";
		final stderrPath = tempRoot + "/stderr.log";
		final quotedArgs = [for (arg in args) shellQuote(arg)];
		final command = "haxe " + quotedArgs.join(" ") + " > " + shellQuote(stdoutPath) + " 2> " + shellQuote(stderrPath);
		final exitCode = Sys.command("sh", ["-c", command]);
		final stdout = sys.FileSystem.exists(stdoutPath) ? sys.io.File.getContent(stdoutPath) : "";
		final stderr = sys.FileSystem.exists(stderrPath) ? sys.io.File.getContent(stderrPath) : "";
		if (sys.FileSystem.exists(stdoutPath))
			sys.FileSystem.deleteFile(stdoutPath);
		if (sys.FileSystem.exists(stderrPath))
			sys.FileSystem.deleteFile(stderrPath);
		if (sys.FileSystem.exists(tempRoot))
			sys.FileSystem.deleteDirectory(tempRoot);
		return {
			exitCode: exitCode,
			stdout: stdout,
			stderr: stderr
		};
	}

	static function compileRuntimeFixture(outDir:String, profile:Null<String>, classPath:String = "test", mainClass:String = "Main"):CompileInvocationResult {
		sys.FileSystem.createDirectory(outDir);
		final args = [
			"-cp",
			classPath,
			"-main",
			mainClass,
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
		return runHaxe(args);
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

	static function readProfileReport(outDir:String):ProfileReport {
		final reportPath = outDir + "/ocaml_profile_report.json";
		if (!sys.FileSystem.exists(reportPath))
			throw "missing profile report: " + reportPath;
		return cast haxe.Json.parse(sys.io.File.getContent(reportPath));
	}

	static function readRuntimePlanReport(outDir:String):RuntimePlanReport {
		final reportPath = outDir + "/ocaml_runtime_plan_report.json";
		if (!sys.FileSystem.exists(reportPath))
			throw "missing runtime plan report: " + reportPath;
		return cast haxe.Json.parse(sys.io.File.getContent(reportPath));
	}

	static function main() {
		final rootOutDir = "out_ocaml_m6_runtime_" + Std.string(Std.int(Date.now().getTime()));
		final portableOutDir = rootOutDir + "/portable";
		final metalOutDir = rootOutDir + "/metal";
		final emptyProfileOutDir = rootOutDir + "/portable_empty";
		final metalTokenNoiseOutDir = rootOutDir + "/metal_token_noise";
		final invalidProfileOutDir = rootOutDir + "/invalid_profile";
		sys.FileSystem.createDirectory(rootOutDir);

		final portableCompile = compileRuntimeFixture(portableOutDir, null);
		assertTrue(portableCompile.exitCode == 0, "portable compile failed: " + portableCompile.stderr);
		final metalCompile = compileRuntimeFixture(metalOutDir, "MeTaL");
		assertTrue(metalCompile.exitCode == 0, "metal mixed-case compile failed: " + metalCompile.stderr);
		final emptyProfileCompile = compileRuntimeFixture(emptyProfileOutDir, "");
		assertTrue(emptyProfileCompile.exitCode == 0, "empty-profile compile failed: " + emptyProfileCompile.stderr);
		final metalTokenNoiseCompile = compileRuntimeFixture(metalTokenNoiseOutDir, "metal", "test/fixtures/m6_runtime_token_noise/src", "Main");
		assertTrue(metalTokenNoiseCompile.exitCode == 0, "metal token-noise compile failed: " + metalTokenNoiseCompile.stderr);
		final invalidProfileCompile = compileRuntimeFixture(invalidProfileOutDir, "weird");
		assertTrue(invalidProfileCompile.exitCode != 0, "invalid profile should fail fast");
		final invalidCombinedOutput = invalidProfileCompile.stderr + "\n" + invalidProfileCompile.stdout;
		assertContains(invalidCombinedOutput, "ocaml_profile", "invalid profile should mention ocaml_profile");
		assertContains(invalidCombinedOutput, "portable|metal", "invalid profile should mention expected values");
		assertTrue(!sys.FileSystem.exists(invalidProfileOutDir + "/ocaml_profile_report.json"), "invalid profile should fail before profile report generation");

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
		final emptyProfileModules = runtimeModules(emptyProfileOutDir);
		final portableProfileReport = readProfileReport(portableOutDir);
		final metalProfileReport = readProfileReport(metalOutDir);
		final emptyProfileReport = readProfileReport(emptyProfileOutDir);
		final portableRuntimeReport = readRuntimePlanReport(portableOutDir);
		final metalRuntimeReport = readRuntimePlanReport(metalOutDir);
		final emptyProfileRuntimeReport = readRuntimePlanReport(emptyProfileOutDir);
		final metalTokenNoiseRuntimeReport = readRuntimePlanReport(metalTokenNoiseOutDir);

		assertTrue(portableModules.length > 0, "portable runtime should include modules");
		assertTrue(metalModules.length > 0, "metal runtime should include modules");
		assertTrue(metalModules.length < portableModules.length, "metal runtime should link fewer modules than portable");
		assertArrayEquals(portableModules, emptyProfileModules, "empty profile should match portable runtime module set");

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

		assertTrue(portableProfileReport.contractVersion == 1, "portable profile report contract version");
		assertTrue(portableProfileReport.requestedProfile == null, "portable report keeps null requested profile");
		assertTrue(portableProfileReport.normalizedProfile == "portable", "portable report normalized profile");
		assertTrue(portableProfileReport.verifier.enabled == false, "portable report verifier mode");
		assertTrue(portableProfileReport.verifier.result == "not_run_in_runtime_copier", "portable report verifier result");

		assertTrue(metalProfileReport.contractVersion == 1, "metal profile report contract version");
		assertTrue(metalProfileReport.requestedProfile == "MeTaL", "metal report should keep requested mixed-case profile");
		assertTrue(metalProfileReport.normalizedProfile == "metal", "metal report normalized profile");
		assertTrue(metalProfileReport.verifier.mode == "reflaxe_stage0_macro", "metal report verifier mode label");

		assertTrue(emptyProfileReport.contractVersion == 1, "empty profile report contract version");
		assertTrue(emptyProfileReport.requestedProfile == "", "empty profile report keeps empty requested profile");
		assertTrue(emptyProfileReport.normalizedProfile == "portable", "empty profile normalizes to portable");

		assertTrue(portableRuntimeReport.contractVersion == 1, "portable runtime report contract version");
		assertTrue(portableRuntimeReport.profile == "portable", "portable runtime report profile");
		assertTrue(portableRuntimeReport.selectionMode == "full", "portable runtime report mode");
		assertTrue(portableRuntimeReport.tokenScanFallbackEnabled == false, "portable runtime report token-scan fallback flag");
		assertTrue(portableRuntimeReport.selectedModules.length == portableRuntimeReport.selectedFeatures.length, "portable selected modules/features size");
		assertContains("\n" + portableRuntimeReport.selectedModules.join("\n") + "\n", "\nHxRuntime\n", "portable report includes HxRuntime");

		assertTrue(metalRuntimeReport.contractVersion == 1, "metal runtime report contract version");
		assertTrue(metalRuntimeReport.profile == "metal", "metal runtime report profile");
		assertTrue(metalRuntimeReport.selectionMode == "compiler_tracked", "metal runtime report mode");
		assertTrue(metalRuntimeReport.tokenScanFallbackEnabled == false, "metal runtime report token-scan fallback flag");
		assertTrue(metalRuntimeReport.selectedModules.length == metalRuntimeReport.selectedFeatures.length, "metal selected modules/features size");
		assertContains("\n" + metalRuntimeReport.trackedModules.join("\n") + "\n", "\nHxRuntime\n", "metal report tracked modules include HxRuntime");
		assertContains("\n" + metalRuntimeReport.selectedModules.join("\n") + "\n", "\nHxRuntime\n", "metal report includes HxRuntime");
		assertNotContains("\n" + metalRuntimeReport.selectedModules.join("\n") + "\n", "\nHxFile\n", "metal report omits HxFile");

		assertTrue(emptyProfileRuntimeReport.profile == "portable", "empty profile runtime report profile");
		assertTrue(emptyProfileRuntimeReport.selectionMode == "full", "empty profile runtime report selection mode");

		assertTrue(metalTokenNoiseRuntimeReport.profile == "metal", "token noise report profile");
		assertTrue(metalTokenNoiseRuntimeReport.selectionMode == "compiler_tracked", "token noise report mode");
		assertNotContains("\n" + metalTokenNoiseRuntimeReport.selectedModules.join("\n") + "\n", "\nHxFile\n",
			"token noise report omits HxFile despite HxFile string tokens");
		assertArrayEquals(metalRuntimeReport.selectedModules, metalTokenNoiseRuntimeReport.selectedModules,
			"token noise runtime plan should match baseline metal plan");
	}
}
