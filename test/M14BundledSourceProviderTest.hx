import hxhx.CompilationServerSourceCache;
import hxhx.Stage3SetupSupport;

/** Prove installed compiler assets use normal lookup, exact bytes, and safe server reuse. */
class M14BundledSourceProviderTest {
	static function require(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	static function main():Void {
		final root = CompilerBundledSources.targetRoot("cpp");
		require(root != null, "C++ requires its bundled source root");
		require(CompilerBundledSources.targetRoot("neko") == null, "unrelated targets must retain their providers");
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: [],
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: "",
			targetDefine: "cpp"
		});
		require(paths.indexOf(root) >= 0, "production setup must select bundled providers");
		final provider = new CompilerSourceProvider();
		final path = provider.resolveModuleFile([root], "haxe.Exception");
		require(path != null && !sys.FileSystem.exists(path), "provider must work without a source file on disk");
		final source = provider.readSource(path);
		require(source != null, "direct provider must read embedded bytes");
		final parsed = provider.parseFilteredSource(source, path);
		final declarations = HxModuleDecl.getClasses(parsed.getDecl());
		require(declarations.length == 1 && !HxClassDecl.getIsExtern(declarations[0]), "exception must be an authored class");
		require(provider.resolveModuleFile([root], "haxe.exception") == null, "lookup must preserve filename case");
		require(provider.readSource(root + "/haxe/Missing.hx") == null, "missing assets must remain missing");
		require(provider.readSource("/__hxhx_bundled_sources__/stale/cpp/_std/haxe/Exception.hx") == null,
			"stale bundle identities must not select current bytes");
		final copy = CompilerBundledSources.readBytes(path);
		require(copy != null, "bundled bytes must exist");
		copy.set(0, 0);
		require(provider.readSource(path) == source, "callers must not mutate the embedded snapshot");

		final cache = new CompilationServerSourceCache();
		for (run in 0...2) {
			final request = cache.openRequest();
			require(request.resolveModuleFile([root], "haxe.Exception") == path, "server lookup must match direct lookup");
			require(request.readSource(path) == source, "server bytes must match direct bytes");
			request.parseFilteredSource(source, path);
			if (run == 1)
				require(request.report().sourceHits == 1 && request.report().parserHits == 1 && request.report().resolutionHits == 1,
					"unchanged bundled sources must reuse exact server entries");
			request.prepareFinish(true);
			request.finish(true);
		}
		// User files keep precedence, and deleting a shadow restores the bundle
		// even after the server retained the earlier resolution.
		final temporary = haxe.io.Path.join([
			Sys.getCwd(),
			".tmp",
			"bundled-provider-" + Std.string(Sys.time()).split(".").join("-")
		]);
		final directory = temporary + "/haxe";
		sys.FileSystem.createDirectory(directory);
		final shadow = directory + "/Exception.hx";
		sys.io.File.saveContent(shadow, "package haxe; class Exception {}\n");
		final projectPaths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: [temporary],
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: "",
			targetDefine: "cpp"
		});
		final shadowed = cache.openRequest();
		require(shadowed.resolveModuleFile(projectPaths, "haxe.Exception") == shadow, "project source must precede the bundle");
		shadowed.prepareFinish(true);
		shadowed.finish(true);
		sys.FileSystem.deleteFile(shadow);
		final restored = cache.openRequest();
		require(restored.resolveModuleFile(projectPaths, "haxe.Exception") == path, "deleting a shadow must restore the provider");
		restored.finish(false);
		sys.FileSystem.deleteDirectory(directory);
		sys.FileSystem.deleteDirectory(temporary);
		cache.reset();
		final reset = cache.openRequest();
		require(reset.readSource(path) == source && reset.report().sourceHits == 0, "reset must discard cache entries, not source assets");
		reset.finish(false);
		Sys.println("BUNDLED_SOURCE_PROVIDER:PASS");
	}
}
