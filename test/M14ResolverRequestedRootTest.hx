/**
	Checks that the program root is selected by module path, not by resolution order.

	Resolution adds the implicit standard declarations (`StdTypes`, `Class`) as
	roots. The dependency walk can return one of them first, so `resolved[0]` is not
	the requested main module. Stage3's type-only summary and the compiler driver
	both need the requested root itself.
**/
class M14ResolverRequestedRootTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	/** CI installs the pinned compiler through Lix; developers may set HAXE_STD_PATH. */
	static function pinnedStdPath(version:String):String {
		final configured = Sys.getEnv("HAXE_STD_PATH");
		if (configured != null && configured != "" && sys.FileSystem.isDirectory(configured))
			return configured;
		final home = Sys.getEnv("HOME");
		if (home != null && home != "") {
			final lixManaged = haxe.io.Path.join([home, "haxe", "versions", version, "std"]);
			if (sys.FileSystem.isDirectory(lixManaged))
				return lixManaged;
		}
		final localOracle = haxe.io.Path.normalize("vendor/haxe/std");
		if (sys.FileSystem.isDirectory(localOracle))
			return localOracle;
		throw 'Could not locate the Haxe $version standard library. Set HAXE_STD_PATH or install that version through Lix.';
	}

	static function main():Void {
		final std = pinnedStdPath("4.3.7");
		final classPaths = ["workloads/hih-compiler/fixtures/src", std];
		final resolved = ResolverStage.parseProjectRoots(classPaths, ["demo.A"], null);
		final paths = [for (module in resolved) ResolvedModule.getModulePath(module)];
		assertTrue(paths.indexOf("StdTypes") >= 0, "implicit StdTypes root was not resolved: " + paths.join(","));
		assertTrue(ResolvedModule.getModulePath(resolved[0]) != "demo.A",
			"fixture no longer reproduces a non-root first module; resolution order: " + paths.join(","));
		final root = ResolverStage.requestedRoot(resolved, ["demo.A"]);
		assertTrue(ResolvedModule.getModulePath(root) == "demo.A", "requested root resolved to " + ResolvedModule.getModulePath(root));
		assertTrue(ResolverStage.requestedRoot(resolved, []) == resolved[0], "an empty root list must keep the first resolved module");
		var missing = "";
		try {
			ResolverStage.requestedRoot(resolved, ["demo.Missing"]);
		} catch (error:String) {
			missing = error;
		}
		assertTrue(missing.indexOf("demo.Missing") >= 0, "an unresolved requested root must be reported, got: " + missing);
		Sys.println("M14_RESOLVER_REQUESTED_ROOT:PASS");
	}
}
