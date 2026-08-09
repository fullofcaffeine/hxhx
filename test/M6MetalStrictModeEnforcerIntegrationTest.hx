private typedef CompileInvocationResult = {
	final exitCode:Int;
	final stdout:String;
	final stderr:String;
}

class M6MetalStrictModeEnforcerIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) < 0)
			throw label + ": expected to find '" + needle + "'";
	}

	static function assertNotContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) >= 0)
			throw label + ": expected to not find '" + needle + "'";
	}

	static function shellQuote(value:String):String {
		return "'" + StringTools.replace(value, "'", "'\"'\"'") + "'";
	}

	static function runHaxe(args:Array<String>):CompileInvocationResult {
		final tempRoot = ".tmp/m6_metal_enforcer_haxe_run_" + Std.string(Std.int(Date.now().getTime())) + "_" + Std.string(Std.random(1000000));
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

	/** Runs target syntax construction only when a case must test the backend boundary itself. */
	static function compileFixture(fixtureName:String, defines:Array<String>, generateOutput:Bool = false):CompileInvocationResult {
		final outDir = ".tmp/m6_metal_enforcer_out_" + fixtureName + "_" + Std.string(Std.int(Date.now().getTime()));
		sys.FileSystem.createDirectory(outDir);
		final classPath = "test/fixtures/m6_metal_strict_enforcer/" + fixtureName + "/src";
		final args = [
			"-cp",
			classPath,
			"-main",
			"Main",
			"-lib",
			"reflaxe.ocaml",
			"-D",
			"ocaml_no_build",
			"-D",
			"ocaml_output=" + outDir,
			"-D",
			"no-traces",
			"-D",
			"no_traces"
		];
		if (!generateOutput)
			args.push("--no-output");
		for (defineValue in defines) {
			args.push("-D");
			args.push(defineValue);
		}
		return runHaxe(args);
	}

	static function combinedOutput(result:CompileInvocationResult):String {
		return result.stderr + "\n" + result.stdout;
	}

	static function main():Void {
		final portableInjection = compileFixture("injection", ["ocaml_profile=portable"]);
		assertTrue(portableInjection.exitCode == 0, "portable profile should allow __ocaml__ injection");

		final portablePrivateRuntimeInjection = compileFixture("private_runtime_injection", ["ocaml_profile=portable"], true);
		assertTrue(portablePrivateRuntimeInjection.exitCode != 0, "portable raw OCaml should reject compiler-private runtime names");
		assertContains(combinedOutput(portablePrivateRuntimeInjection), "HxRuntime", "private runtime injection failure should name the rejected identifier");

		final portableNativeSurfaceWarn = compileFixture("portable_native_surface", ["ocaml_profile=portable"]);
		assertTrue(portableNativeSurfaceWarn.exitCode == 0, "portable native-surface warn policy should compile");
		assertContains(combinedOutput(portableNativeSurfaceWarn), "ocaml_portable_native_surface", "portable warn policy should mention policy define");

		final portableNativeSurfaceError = compileFixture("portable_native_surface", ["ocaml_profile=portable", "ocaml_portable_native_surface=error"]);
		assertTrue(portableNativeSurfaceError.exitCode != 0, "portable native-surface error policy should fail");
		assertContains(combinedOutput(portableNativeSurfaceError), "ocaml_portable_native_surface", "portable error policy should mention policy define");

		final portableNativeSurfaceAllow = compileFixture("portable_native_surface", ["ocaml_profile=portable", "ocaml_portable_native_surface=allow"]);
		assertTrue(portableNativeSurfaceAllow.exitCode == 0, "portable native-surface allow policy should compile");
		assertNotContains(combinedOutput(portableNativeSurfaceAllow), "ocaml_portable_native_surface", "allow policy should not warn");

		final portableAtomicUsage = compileFixture("atomic_usage", ["ocaml_profile=portable"]);
		assertTrue(portableAtomicUsage.exitCode == 0, "portable atomic usage should compile");
		assertContains(combinedOutput(portableAtomicUsage), "haxe.atomic.*", "portable atomic usage should emit atomic semantics diagnostic");
		assertContains(combinedOutput(portableAtomicUsage), "ocaml_atomic_semantics", "portable atomic usage should mention define contract");

		final metalInjection = compileFixture("injection", ["ocaml_profile=metal"]);
		assertTrue(metalInjection.exitCode != 0, "metal profile should reject __ocaml__ injection");
		assertContains(combinedOutput(metalInjection), "__ocaml__", "metal injection failure should mention __ocaml__");

		final metalReflection = compileFixture("reflection", ["ocaml_profile=metal"]);
		assertTrue(metalReflection.exitCode != 0, "metal profile should reject reflection calls");
		assertContains(combinedOutput(metalReflection), "Reflect.field", "metal reflection failure should mention reflection API");

		final metalDynamic = compileFixture("dynamic", ["ocaml_profile=metal"]);
		assertTrue(metalDynamic.exitCode != 0, "metal profile should reject explicit Dynamic annotations");
		assertContains(combinedOutput(metalDynamic), "Dynamic", "metal dynamic failure should mention Dynamic policy");

		final fallbackInjection = compileFixture("injection", ["ocaml_profile=metal", "ocaml_metal_allow_fallback"]);
		assertTrue(fallbackInjection.exitCode == 0, "metal fallback should allow compilation");
		assertContains(combinedOutput(fallbackInjection), "ocaml_metal_allow_fallback", "fallback build should emit warning message");
	}
}
