import haxe.Json;
import haxe.io.Path;
import reflaxe.ocaml.runtimegen.RuntimeSourceManifest;
import reflaxe.ocaml.runtimegen.RuntimeSourceManifestModel.RuntimeSourceManifestSnapshot;
import sys.FileSystem;
import sys.io.File;

using StringTools;

/** Proves that runtime source ownership is complete, deterministic, and fail-closed. **/
class RuntimeSourceManifestFixture {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function assertArrayEquals(expected:Array<String>, actual:Array<String>, message:String):Void {
		if (Json.stringify(expected) != Json.stringify(actual))
			throw '$message: expected ${Json.stringify(expected)}, found ${Json.stringify(actual)}';
	}

	static function expectFailure(label:String, expectedMessage:String, action:Void->Void):Void {
		var failed = false;
		try {
			action();
		} catch (error:Dynamic) {
			failed = true;
			final message = Std.string(error);
			if (!message.contains(expectedMessage))
				throw '$label failed with an unexpected message: $message';
		}
		if (!failed)
			throw '$label should have failed.';
	}

	static function createDirectory(path:String):Void {
		if (FileSystem.exists(path))
			return;
		final parent = Path.directory(path);
		if (parent != null && parent.length > 0 && parent != path)
			createDirectory(parent);
		FileSystem.createDirectory(path);
	}

	static function removeTree(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (!FileSystem.isDirectory(path)) {
			FileSystem.deleteFile(path);
			return;
		}
		for (name in FileSystem.readDirectory(path))
			removeTree(Path.join([path, name]));
		FileSystem.deleteDirectory(path);
	}

	static function copyRuntime(source:String, destination:String):Void {
		createDirectory(destination);
		for (name in FileSystem.readDirectory(source)) {
			final sourcePath = Path.join([source, name]);
			if (FileSystem.isDirectory(sourcePath))
				continue;
			if (name == RuntimeSourceManifest.FILE_NAME || name.endsWith(".ml") || name.endsWith(".mli"))
				File.copy(sourcePath, Path.join([destination, name]));
		}
	}

	static function withRuntimeCopy(source:String, root:String, label:String, action:String->Void):Void {
		final destination = Path.join([root, label]);
		copyRuntime(source, destination);
		try {
			action(destination);
		} catch (error:Dynamic) {
			removeTree(destination);
			throw error;
		}
		removeTree(destination);
	}

	static function readManifest(path:String):Dynamic {
		return Json.parse(File.getContent(Path.join([path, RuntimeSourceManifest.FILE_NAME])));
	}

	static function writeManifest(path:String, value:Dynamic):Void {
		File.saveContent(Path.join([path, RuntimeSourceManifest.FILE_NAME]), Json.stringify(value, null, "  ") + "\n");
	}

	static function moduleNames(snapshot:RuntimeSourceManifestSnapshot):Array<String> {
		return [for (entry in snapshot.modules) entry.module];
	}

	static function testValidManifest(runtimeDirectory:String):Void {
		final first = RuntimeSourceManifest.load(runtimeDirectory);
		final second = RuntimeSourceManifest.load(runtimeDirectory);
		assertTrue(first.modules.length == 34, "the locked catalog should own all 34 runtime modules");
		assertTrue(first.revision == second.revision, "unchanged runtime sources should have one deterministic revision");
		assertTrue(first.revision.startsWith("sha256:"), "the runtime revision should identify its digest algorithm");
		final reflectClosure = RuntimeSourceManifest.resolveClosure(first, ["HxReflect"], "portable", false);
		assertArrayEquals([
			"HxAnon",
			"HxArray",
			"HxEnum",
			"HxIterator",
			"HxReflect",
			"HxRuntime",
			"HxString",
			"HxType"
		], [for (entry in reflectClosure) entry.module],
			"the checked dependency closure should be stable and complete");
		final dynamicClosure = RuntimeSourceManifest.resolveClosure(first, ["HxDynamic"], "portable", false);
		assertArrayEquals([
			"HxAnon",
			"HxArray",
			"HxDynamic",
			"HxEnum",
			"HxIterator",
			"HxRuntime",
			"HxString",
			"HxType"
		],
			[for (entry in dynamicClosure) entry.module],
			"Dynamic text behavior should receive the anonymous-value and class-registry runtime owners it calls");
		assertTrue(RuntimeSourceManifest.fullRoots(first, "portable", false).length == 26,
			"application builds should include the new Dynamic owner and exclude the eight compiler-tooling modules");
	}

	static function testChangedSource(runtimeDirectory:String, root:String):Void {
		withRuntimeCopy(runtimeDirectory, root, "changed", copy -> {
			final path = Path.join([copy, "HxRuntime.ml"]);
			File.saveContent(path, File.getContent(path) + "\n(* changed by fixture *)\n");
			expectFailure("changed source", "changed: expected", () -> RuntimeSourceManifest.load(copy));
		});
	}

	static function testMissingAndUnlistedSources(runtimeDirectory:String, root:String):Void {
		withRuntimeCopy(runtimeDirectory, root, "missing", copy -> {
			FileSystem.deleteFile(Path.join([copy, "HxRuntime.ml"]));
			expectFailure("missing source", "is missing", () -> RuntimeSourceManifest.load(copy));
		});
		withRuntimeCopy(runtimeDirectory, root, "unlisted", copy -> {
			File.saveContent(Path.join([copy, "Extra.ml"]), "let value = 1\n");
			expectFailure("unlisted source", "is not declared", () -> RuntimeSourceManifest.load(copy));
		});
	}

	static function testInvalidCatalog(runtimeDirectory:String, root:String):Void {
		withRuntimeCopy(runtimeDirectory, root, "unknown-dependency", copy -> {
			final manifest = readManifest(copy);
			manifest.entries[0].dependencies.push("DoesNotExist");
			writeManifest(copy, manifest);
			expectFailure("unknown dependency", "names unknown dependency", () -> RuntimeSourceManifest.load(copy));
		});
		withRuntimeCopy(runtimeDirectory, root, "unexpected-field", copy -> {
			final manifest = readManifest(copy);
			Reflect.setField(manifest, "unreviewedSetting", true);
			writeManifest(copy, manifest);
			expectFailure("unexpected field", "fields do not match the schema", () -> RuntimeSourceManifest.load(copy));
		});
		withRuntimeCopy(runtimeDirectory, root, "cycle", copy -> {
			final manifest = readManifest(copy);
			for (entry in cast(manifest.entries, Array<Dynamic>))
				if (entry.module == "HxRuntime")
					entry.dependencies.push("HxArray");
			writeManifest(copy, manifest);
			expectFailure("dependency cycle", "dependency cycle", () -> RuntimeSourceManifest.load(copy));
		});
		withRuntimeCopy(runtimeDirectory, root, "profile-mismatch", copy -> {
			final manifest = readManifest(copy);
			for (entry in cast(manifest.entries, Array<Dynamic>))
				if (entry.module == "HxRuntime")
					entry.profiles = ["portable"];
			writeManifest(copy, manifest);
			expectFailure("profile mismatch", "not allowed in the \"metal\" profile", () -> RuntimeSourceManifest.load(copy));
		});
	}

	static function testRequestFailures(runtimeDirectory:String):Void {
		final snapshot = RuntimeSourceManifest.load(runtimeDirectory);
		expectFailure("unknown root", "Unknown OCaml runtime module",
			() -> RuntimeSourceManifest.resolveClosure(snapshot, ["DoesNotExist"], "portable", false));
		expectFailure("tooling in application", "tooling-only", () -> RuntimeSourceManifest.resolveClosure(snapshot, ["HxHxNativeLexer"], "portable", false));
		expectFailure("tooling in metal", "not allowed in the \"metal\" profile",
			() -> RuntimeSourceManifest.resolveClosure(snapshot, ["HxHxNativeLexer"], "metal", true));
		assertArrayEquals(["HxHxNativeLexer", "HxHxNativeParser"], [
			for (entry in RuntimeSourceManifest.resolveClosure(snapshot, ["HxHxNativeParser"], "portable", true))
				entry.module
		],
			"an explicitly authorized portable compiler tool should receive its checked dependency");
	}

	static function main():Void {
		final runtimeDirectory = FileSystem.absolutePath("packages/reflaxe.ocaml/std/runtime");
		final root = ".tmp/reflaxe_ocaml_runtime_manifest_"
			+ Std.string(Std.int(Date.now().getTime()))
			+ "_"
			+ Std.string(Std.random(1000000));
		createDirectory(root);
		try {
			testValidManifest(runtimeDirectory);
			testChangedSource(runtimeDirectory, root);
			testMissingAndUnlistedSources(runtimeDirectory, root);
			testInvalidCatalog(runtimeDirectory, root);
			testRequestFailures(runtimeDirectory);
		} catch (error:Dynamic) {
			removeTree(root);
			throw error;
		}
		removeTree(root);
		Sys.println("REFLAXE_OCAML_RUNTIME_MANIFEST_FIXTURE:PASS");
	}
}
