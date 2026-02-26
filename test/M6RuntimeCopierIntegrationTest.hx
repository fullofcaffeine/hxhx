private typedef ProfileReportVerifier = {
	final mode:String;
	final enabled:Bool;
	final result:String;
	final strictScope:String;
	final violationCount:Int;
	final violations:Array<String>;
	final laneModules:Array<String>;
}

private typedef ProfileReport = {
	final schemaVersion:Int;
	final requestedProfile:Null<String>;
	final normalizedProfile:String;
	final atomicSemantics:String;
	final runtimeMode:String;
	final portableNativeSurfacePolicy:String;
	final strictUserBoundaries:Bool;
	final metalFallbackAllowed:Bool;
	final verifier:ProfileReportVerifier;
}

private typedef RuntimePlanInclusionReason = {
	final module:String;
	final reasons:Array<String>;
}

private typedef RuntimePlanReport = {
	final schemaVersion:Int;
	final profile:String;
	final runtimeMode:String;
	final selectionMode:String;
	final availableModules:Array<String>;
	final trackedModules:Array<String>;
	final manualModules:Array<String>;
	final runtimeInferenceDisabled:Bool;
	final runtimeDebugLaneEnabled:Bool;
	final tokenScanFallbackEnabled:Bool;
	final selectedModules:Array<String>;
	final selectedFeatures:Array<String>;
	final inclusionReasons:Array<RuntimePlanInclusionReason>;
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

	static function reasonsForModule(report:RuntimePlanReport, moduleName:String):Array<String> {
		for (entry in report.inclusionReasons) {
			if (entry.module == moduleName)
				return entry.reasons.copy();
		}
		return [];
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

	static function compileRuntimeFixture(outDir:String, profile:Null<String>, classPath:String = "test", mainClass:String = "Main",
			extraDefines:Array<String> = null):CompileInvocationResult {
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
		if (extraDefines != null) {
			for (defineValue in extraDefines) {
				args.push("-D");
				args.push(defineValue);
			}
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
		final metalFullOutDir = rootOutDir + "/metal_full";
		final emptyProfileOutDir = rootOutDir + "/portable_empty";
		final portableManualOutDir = rootOutDir + "/portable_manual_selective";
		final metalTokenNoiseOutDir = rootOutDir + "/metal_token_noise";
		final metalTokenFallbackNoDebugOutDir = rootOutDir + "/metal_token_fallback_no_debug";
		final metalTokenFallbackDebugOutDir = rootOutDir + "/metal_token_fallback_debug";
		final invalidProfileOutDir = rootOutDir + "/invalid_profile";
		final invalidAtomicSemanticsOutDir = rootOutDir + "/invalid_atomic_semantics";
		final invalidRuntimeModeOutDir = rootOutDir + "/invalid_runtime_mode";
		final noneRuntimeModeOutDir = rootOutDir + "/none_runtime_mode";
		sys.FileSystem.createDirectory(rootOutDir);

		final portableCompile = compileRuntimeFixture(portableOutDir, null);
		assertTrue(portableCompile.exitCode == 0, "portable compile failed: " + portableCompile.stderr);
		final metalCompile = compileRuntimeFixture(metalOutDir, "MeTaL");
		assertTrue(metalCompile.exitCode == 0, "metal mixed-case compile failed: " + metalCompile.stderr);
		final metalFullCompile = compileRuntimeFixture(metalFullOutDir, "metal", "test", "Main", ["ocaml_runtime_mode=full"]);
		assertTrue(metalFullCompile.exitCode == 0, "metal full-runtime override compile failed: " + metalFullCompile.stderr);
		final emptyProfileCompile = compileRuntimeFixture(emptyProfileOutDir, "");
		assertTrue(emptyProfileCompile.exitCode == 0, "empty-profile compile failed: " + emptyProfileCompile.stderr);
		final portableManualCompile = compileRuntimeFixture(portableManualOutDir, "portable", "test", "Main", [
			"ocaml_runtime_mode=selective",
			"ocaml_runtime_no_infer",
			"ocaml_runtime_modules=HxRuntime"
		]);
		assertTrue(portableManualCompile.exitCode == 0, "portable manual selective compile failed: " + portableManualCompile.stderr);
		final metalTokenNoiseCompile = compileRuntimeFixture(metalTokenNoiseOutDir, "metal", "test/fixtures/m6_runtime_token_noise/src", "Main");
		assertTrue(metalTokenNoiseCompile.exitCode == 0, "metal token-noise compile failed: " + metalTokenNoiseCompile.stderr);
		final metalTokenFallbackNoDebugCompile = compileRuntimeFixture(metalTokenFallbackNoDebugOutDir, "metal", "test", "Main",
			["ocaml_runtime_token_scan_fallback"]);
		assertTrue(metalTokenFallbackNoDebugCompile.exitCode == 0,
			"metal token fallback (no debug lane) compile failed: " + metalTokenFallbackNoDebugCompile.stderr);
		final metalTokenFallbackDebugCompile = compileRuntimeFixture(metalTokenFallbackDebugOutDir, "metal", "test", "Main",
			["ocaml_runtime_token_scan_fallback", "ocaml_runtime_debug_lane"]);
		assertTrue(metalTokenFallbackDebugCompile.exitCode == 0, "metal token fallback (debug lane) compile failed: " + metalTokenFallbackDebugCompile.stderr);
		final invalidProfileCompile = compileRuntimeFixture(invalidProfileOutDir, "weird");
		assertTrue(invalidProfileCompile.exitCode != 0, "invalid profile should fail fast");
		final invalidCombinedOutput = invalidProfileCompile.stderr + "\n" + invalidProfileCompile.stdout;
		assertContains(invalidCombinedOutput, "ocaml_profile", "invalid profile should mention ocaml_profile");
		assertContains(invalidCombinedOutput, "portable|metal", "invalid profile should mention expected values");
		assertTrue(!sys.FileSystem.exists(invalidProfileOutDir + "/ocaml_profile_report.json"), "invalid profile should fail before profile report generation");
		final invalidAtomicSemanticsCompile = compileRuntimeFixture(invalidAtomicSemanticsOutDir, "portable", "test", "Main", ["ocaml_atomic_semantics=true"]);
		assertTrue(invalidAtomicSemanticsCompile.exitCode != 0, "invalid atomic semantics should fail fast");
		final invalidAtomicSemanticsOutput = invalidAtomicSemanticsCompile.stderr + "\n" + invalidAtomicSemanticsCompile.stdout;
		assertContains(invalidAtomicSemanticsOutput, "ocaml_atomic_semantics", "invalid atomic semantics should mention define");
		assertContains(invalidAtomicSemanticsOutput, "only emulated is currently supported", "invalid atomic semantics should use actionable error");
		final invalidRuntimeModeCompile = compileRuntimeFixture(invalidRuntimeModeOutDir, "portable", "test", "Main", ["ocaml_runtime_mode=weird"]);
		assertTrue(invalidRuntimeModeCompile.exitCode != 0, "invalid runtime mode should fail fast");
		final invalidRuntimeModeOutput = invalidRuntimeModeCompile.stderr + "\n" + invalidRuntimeModeCompile.stdout;
		assertContains(invalidRuntimeModeOutput, "ocaml_runtime_mode", "invalid runtime mode should mention define");
		assertContains(invalidRuntimeModeOutput, "full|selective", "invalid runtime mode should mention expected values");
		final noneRuntimeModeCompile = compileRuntimeFixture(noneRuntimeModeOutDir, "portable", "test", "Main", ["ocaml_runtime_mode=none"]);
		assertTrue(noneRuntimeModeCompile.exitCode != 0, "none runtime mode should fail fast");
		final noneRuntimeModeOutput = noneRuntimeModeCompile.stderr + "\n" + noneRuntimeModeCompile.stdout;
		assertContains(noneRuntimeModeOutput, "ocaml_runtime_mode", "none runtime mode should mention define");
		assertContains(noneRuntimeModeOutput, "none is not supported", "none runtime mode should use actionable error");

		final runtimePath = portableOutDir + "/runtime/HxRuntime.ml";
		if (!sys.FileSystem.exists(runtimePath))
			throw "missing runtime: " + runtimePath;
		final runtimeArrayPath = portableOutDir + "/runtime/HxArray.ml";
		if (!sys.FileSystem.exists(runtimeArrayPath))
			throw "missing runtime array module: " + runtimeArrayPath;
		final runtimeArrayContent = sys.io.File.getContent(runtimeArrayPath);
		assertContains(runtimeArrayContent, "type storage =", "HxArray runtime should define adaptive storage variants");
		assertContains(runtimeArrayContent, "ObjStore", "HxArray runtime should include ObjStore variant");
		assertContains(runtimeArrayContent, "IntStore", "HxArray runtime should include IntStore variant");
		assertContains(runtimeArrayContent, "FloatStore", "HxArray runtime should include FloatStore variant");
		assertContains(runtimeArrayContent, "StringStore", "HxArray runtime should include StringStore variant");
		assertContains(runtimeArrayContent, "promote_obj_store_if_possible", "HxArray runtime should include typed-store promotion helper");
		assertContains(runtimeArrayContent, "ensure_obj_store", "HxArray runtime should include deopt helper");
		final runtimeAnonPath = portableOutDir + "/runtime/HxAnon.ml";
		if (!sys.FileSystem.exists(runtimeAnonPath))
			throw "missing runtime anon module: " + runtimeAnonPath;
		final runtimeAnonContent = sys.io.File.getContent(runtimeAnonPath);
		assertContains(runtimeAnonContent, "type shape =", "HxAnon runtime should define shape metadata");
		assertContains(runtimeAnonContent, "type t = {", "HxAnon runtime should define shape-backed object record");
		assertContains(runtimeAnonContent, "slot_index", "HxAnon runtime should expose slot index lookup helper");
		assertContains(runtimeAnonContent, "ensure_value_capacity", "HxAnon runtime should expose slot-capacity helper");
		assertContains(runtimeAnonContent, "present : bool array", "HxAnon runtime should track field presence independently from value nullability");
		assertContains(runtimeAnonContent, "last_field", "HxAnon runtime should include repeated-field fast-path cache");

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
		final metalFullModules = runtimeModules(metalFullOutDir);
		final emptyProfileModules = runtimeModules(emptyProfileOutDir);
		final portableManualModules = runtimeModules(portableManualOutDir);
		final portableProfileReport = readProfileReport(portableOutDir);
		final metalProfileReport = readProfileReport(metalOutDir);
		final metalFullProfileReport = readProfileReport(metalFullOutDir);
		final emptyProfileReport = readProfileReport(emptyProfileOutDir);
		final portableManualProfileReport = readProfileReport(portableManualOutDir);
		final portableRuntimeReport = readRuntimePlanReport(portableOutDir);
		final metalRuntimeReport = readRuntimePlanReport(metalOutDir);
		final metalFullRuntimeReport = readRuntimePlanReport(metalFullOutDir);
		final emptyProfileRuntimeReport = readRuntimePlanReport(emptyProfileOutDir);
		final portableManualRuntimeReport = readRuntimePlanReport(portableManualOutDir);
		final metalTokenNoiseRuntimeReport = readRuntimePlanReport(metalTokenNoiseOutDir);
		final metalTokenFallbackNoDebugRuntimeReport = readRuntimePlanReport(metalTokenFallbackNoDebugOutDir);
		final metalTokenFallbackDebugRuntimeReport = readRuntimePlanReport(metalTokenFallbackDebugOutDir);

		assertTrue(portableModules.length > 0, "portable runtime should include modules");
		assertTrue(metalModules.length > 0, "metal runtime should include modules");
		assertTrue(metalModules.length < portableModules.length, "metal runtime should link fewer modules than portable");
		assertArrayEquals(portableModules, metalFullModules, "metal full override should match portable runtime module set");
		assertArrayEquals(portableModules, emptyProfileModules, "empty profile should match portable runtime module set");
		assertTrue(portableManualModules.length > 0, "portable manual runtime should include modules");
		assertTrue(portableManualModules.length < portableModules.length, "portable manual runtime should link fewer modules than portable");

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

		assertTrue(portableProfileReport.schemaVersion == 2, "portable profile report schema version");
		assertTrue(portableProfileReport.requestedProfile == null, "portable report keeps null requested profile");
		assertTrue(portableProfileReport.normalizedProfile == "portable", "portable report normalized profile");
		assertTrue(portableProfileReport.atomicSemantics == "emulated", "portable report atomic semantics");
		assertTrue(portableProfileReport.runtimeMode == "full", "portable profile report runtime mode");
		assertTrue(portableProfileReport.portableNativeSurfacePolicy == "warn", "portable profile report native-surface policy");
		assertTrue(portableProfileReport.verifier.enabled == true, "portable report verifier enabled");
		assertTrue(portableProfileReport.verifier.result == "pass", "portable report verifier pass");
		assertTrue(portableProfileReport.verifier.violationCount == 0, "portable report verifier violation count");
		assertTrue(portableProfileReport.verifier.strictScope == "disabled", "portable report strict scope");

		assertTrue(metalProfileReport.schemaVersion == 2, "metal profile report schema version");
		assertTrue(metalProfileReport.requestedProfile == "MeTaL", "metal report should keep requested mixed-case profile");
		assertTrue(metalProfileReport.normalizedProfile == "metal", "metal report normalized profile");
		assertTrue(metalProfileReport.atomicSemantics == "emulated", "metal report atomic semantics");
		assertTrue(metalProfileReport.verifier.mode == "reflaxe_stage0_macro", "metal report verifier mode label");
		assertTrue(metalProfileReport.verifier.enabled == true, "metal report verifier enabled");
		assertTrue(metalProfileReport.verifier.result == "pass", "metal report verifier pass");
		assertTrue(metalProfileReport.verifier.strictScope == "global_metal", "metal report strict scope");
		assertTrue(metalProfileReport.verifier.violationCount == 0, "metal report verifier violation count");

		assertTrue(metalFullProfileReport.normalizedProfile == "metal", "metal full override keeps metal profile");

		assertTrue(emptyProfileReport.schemaVersion == 2, "empty profile report schema version");
		assertTrue(emptyProfileReport.requestedProfile == "", "empty profile report keeps empty requested profile");
		assertTrue(emptyProfileReport.normalizedProfile == "portable", "empty profile normalizes to portable");
		assertTrue(emptyProfileReport.atomicSemantics == "emulated", "empty profile report atomic semantics");
		assertTrue(portableManualProfileReport.normalizedProfile == "portable", "portable manual report keeps portable profile");
		assertTrue(portableManualProfileReport.atomicSemantics == "emulated", "portable manual report atomic semantics");

		assertTrue(portableRuntimeReport.schemaVersion == 2, "portable runtime report schema version");
		assertTrue(portableRuntimeReport.profile == "portable", "portable runtime report profile");
		assertTrue(portableRuntimeReport.runtimeMode == "full", "portable runtime report mode");
		assertTrue(portableRuntimeReport.selectionMode == "full", "portable runtime report mode");
		assertTrue(portableRuntimeReport.runtimeDebugLaneEnabled == false, "portable runtime report debug-lane flag");
		assertTrue(portableRuntimeReport.tokenScanFallbackEnabled == false, "portable runtime report token-scan fallback flag");
		assertTrue(portableRuntimeReport.selectedModules.length == portableRuntimeReport.selectedFeatures.length, "portable selected modules/features size");
		assertTrue(portableRuntimeReport.inclusionReasons.length == portableRuntimeReport.selectedModules.length, "portable inclusion reasons should align");
		assertContains("\n" + portableRuntimeReport.selectedModules.join("\n") + "\n", "\nHxRuntime\n", "portable report includes HxRuntime");
		assertContains("\n" + reasonsForModule(portableRuntimeReport, "HxRuntime").join("\n") + "\n", "\nfull_runtime_mode\n",
			"portable report includes full-runtime reason");

		assertTrue(metalRuntimeReport.schemaVersion == 2, "metal runtime report schema version");
		assertTrue(metalRuntimeReport.profile == "metal", "metal runtime report profile");
		assertTrue(metalRuntimeReport.runtimeMode == "selective", "metal runtime mode should default to selective");
		assertTrue(metalRuntimeReport.selectionMode == "compiler_tracked", "metal runtime report mode");
		assertTrue(metalRuntimeReport.runtimeDebugLaneEnabled == false, "metal runtime report debug-lane flag");
		assertTrue(metalRuntimeReport.tokenScanFallbackEnabled == false, "metal runtime report token-scan fallback flag");
		assertTrue(metalRuntimeReport.selectedModules.length == metalRuntimeReport.selectedFeatures.length, "metal selected modules/features size");
		assertTrue(metalRuntimeReport.inclusionReasons.length == metalRuntimeReport.selectedModules.length, "metal inclusion reasons should align");
		assertContains("\n" + metalRuntimeReport.trackedModules.join("\n") + "\n", "\nHxRuntime\n", "metal report tracked modules include HxRuntime");
		assertContains("\n" + metalRuntimeReport.selectedModules.join("\n") + "\n", "\nHxRuntime\n", "metal report includes HxRuntime");
		assertContains("\n" + reasonsForModule(metalRuntimeReport, "HxRuntime").join("\n") + "\n", "\ncore_runtime\n",
			"metal report includes core-runtime reason");
		assertNotContains("\n" + metalRuntimeReport.selectedModules.join("\n") + "\n", "\nHxFile\n", "metal report omits HxFile");

		assertTrue(metalFullRuntimeReport.profile == "metal", "metal full runtime report profile");
		assertTrue(metalFullRuntimeReport.runtimeMode == "full", "metal full runtime report mode");
		assertTrue(metalFullRuntimeReport.selectionMode == "full", "metal full runtime report selection mode");
		assertTrue(metalFullRuntimeReport.runtimeDebugLaneEnabled == false, "metal full runtime report debug-lane flag");
		assertTrue(metalFullRuntimeReport.trackedModules.length == 0, "metal full runtime report should not expose selective tracked modules");
		assertContains("\n" + reasonsForModule(metalFullRuntimeReport, "HxRuntime").join("\n") + "\n", "\nfull_runtime_mode\n",
			"metal full report includes full-runtime reason");

		assertTrue(emptyProfileRuntimeReport.profile == "portable", "empty profile runtime report profile");
		assertTrue(emptyProfileRuntimeReport.runtimeMode == "full", "empty profile runtime mode");
		assertTrue(emptyProfileRuntimeReport.selectionMode == "full", "empty profile runtime report selection mode");

		assertTrue(portableManualRuntimeReport.profile == "portable", "portable manual runtime report profile");
		assertTrue(portableManualRuntimeReport.runtimeMode == "selective", "portable manual runtime mode");
		assertTrue(portableManualRuntimeReport.selectionMode == "manual_only", "portable manual runtime selection mode");
		assertTrue(portableManualRuntimeReport.runtimeInferenceDisabled == true, "portable manual runtime should disable inference");
		assertTrue(portableManualRuntimeReport.runtimeDebugLaneEnabled == false, "portable manual runtime report debug-lane flag");
		assertContains("\n" + portableManualRuntimeReport.manualModules.join("\n") + "\n", "\nHxRuntime\n", "portable manual report includes manual modules");
		assertTrue(portableManualRuntimeReport.trackedModules.length == 0, "portable manual runtime should suppress tracked modules");
		assertNotContains("\n" + portableManualRuntimeReport.selectedModules.join("\n") + "\n", "\nHxFile\n", "portable manual runtime omits file runtime");

		assertTrue(metalTokenNoiseRuntimeReport.profile == "metal", "token noise report profile");
		assertTrue(metalTokenNoiseRuntimeReport.runtimeMode == "selective", "token noise runtime mode");
		assertTrue(metalTokenNoiseRuntimeReport.selectionMode == "compiler_tracked", "token noise report mode");
		assertTrue(metalTokenNoiseRuntimeReport.runtimeDebugLaneEnabled == false, "token noise runtime report debug-lane flag");
		assertNotContains("\n" + metalTokenNoiseRuntimeReport.selectedModules.join("\n") + "\n", "\nHxFile\n",
			"token noise report omits HxFile despite HxFile string tokens");
		assertArrayEquals(metalRuntimeReport.selectedModules, metalTokenNoiseRuntimeReport.selectedModules,
			"token noise runtime plan should match baseline metal plan");

		assertTrue(metalTokenFallbackNoDebugRuntimeReport.profile == "metal", "fallback-no-debug report profile");
		assertTrue(metalTokenFallbackNoDebugRuntimeReport.runtimeMode == "selective", "fallback-no-debug runtime mode");
		assertTrue(metalTokenFallbackNoDebugRuntimeReport.runtimeDebugLaneEnabled == false, "fallback-no-debug should keep debug lane disabled");
		assertTrue(metalTokenFallbackNoDebugRuntimeReport.tokenScanFallbackEnabled == false, "fallback-no-debug should remain disabled");
		assertTrue(metalTokenFallbackNoDebugRuntimeReport.selectionMode == "compiler_tracked", "fallback-no-debug should stay compiler-tracked mode");
		assertArrayEquals(metalRuntimeReport.selectedModules, metalTokenFallbackNoDebugRuntimeReport.selectedModules,
			"fallback-no-debug runtime plan should match baseline metal plan");

		assertTrue(metalTokenFallbackDebugRuntimeReport.profile == "metal", "fallback-debug report profile");
		assertTrue(metalTokenFallbackDebugRuntimeReport.runtimeMode == "selective", "fallback-debug runtime mode");
		assertTrue(metalTokenFallbackDebugRuntimeReport.runtimeDebugLaneEnabled == true, "fallback-debug should enable debug lane");
		assertTrue(metalTokenFallbackDebugRuntimeReport.tokenScanFallbackEnabled == true, "fallback-debug should be enabled");
		assertContains(metalTokenFallbackDebugRuntimeReport.selectionMode, "plus_token_scan_fallback",
			"fallback-debug selection mode should expose token-scan suffix");
	}
}
