import haxe.crypto.Sha256;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/**
	Checks the generated-artifact ownership contract in existing integration tests.

	The production schema owns the detailed vocabulary and revision algorithm.
	This independent fixture helper proves that real compiler outputs contain one
	claim per non-cache file and that each recorded digest still matches the bytes
	on disk.
**/
class OcamlArtifactManifestTestHelper {
	public static function validate(outputDirectory:String, expectedProfile:String):Dynamic {
		final manifestPath = Path.join([outputDirectory, "ocaml_artifact_manifest.json"]);
		assertTrue(FileSystem.exists(manifestPath) && !FileSystem.isDirectory(manifestPath), 'missing artifact manifest: $manifestPath');
		final manifest:Dynamic = haxe.Json.parse(File.getContent(manifestPath));
		assertTrue(Reflect.field(manifest, "schemaVersion") == 1, "artifact manifest uses an unexpected schema");
		assertTrue(Reflect.field(manifest, "model") == "reflaxe-ocaml-artifact-manifest", "artifact manifest uses an unexpected model");
		assertTrue(Reflect.field(manifest, "profile") == expectedProfile,
			'artifact manifest profile mismatch: expected $expectedProfile, found ${Reflect.field(manifest, "profile")}');

		final entries:Array<Dynamic> = cast Reflect.field(manifest, "entries");
		assertTrue(entries != null && entries.length > 0, "artifact manifest must contain entries");
		final claimed:Map<String, Bool> = [];
		var previous:Null<String> = null;
		for (entry in entries) {
			final path:String = Reflect.field(entry, "path");
			assertSafeRelativePath(path);
			assertTrue(previous == null || previous < path, 'artifact entries are not in stable path order at "$path"');
			assertTrue(!claimed.exists(path), 'artifact path "$path" is claimed more than once');
			previous = path;
			claimed.set(path, true);
			final absolute = Path.join([outputDirectory, path]);
			assertTrue(FileSystem.exists(absolute) && !FileSystem.isDirectory(absolute), 'claimed artifact "$path" is missing');
			final bytes = File.getBytes(absolute);
			assertTrue(Reflect.field(entry, "bytes") == bytes.length, 'artifact byte count changed for "$path"');
			assertTrue(Reflect.field(entry, "sha256") == "sha256:" + Sha256.make(bytes).toHex(), 'artifact digest changed for "$path"');
			assertTrue(nonEmptyString(Reflect.field(entry, "owner")), 'artifact "$path" has no owner');
			assertTrue(nonEmptyString(Reflect.field(entry, "kind")), 'artifact "$path" has no role');
		}

		final actualFiles = new Array<String>();
		collectOwnedFiles(outputDirectory, "", actualFiles);
		actualFiles.sort(compareStrings);
		final claimedFiles = [for (path in claimed.keys()) path];
		claimedFiles.sort(compareStrings);
		assertArrayEquals(actualFiles, claimedFiles, "artifact manifest does not exactly cover the non-cache output");

		final summary:Dynamic = Reflect.field(manifest, "summary");
		assertTrue(summary != null, "artifact manifest is missing its summary");
		assertTrue(Reflect.field(summary, "entryCount") == entries.length, "artifact manifest entry count is stale");
		assertTrue(Reflect.field(summary, "completeForSourceBundle") == true,
			"current integration outputs must close every generated-source authority before replay");
		final blockers:Array<Dynamic> = cast Reflect.field(summary, "blockers");
		assertTrue(blockers != null && blockers.length == 0, "complete generated-source authorities must leave no replay blocker");
		return manifest;
	}

	public static function assertEntry(manifest:Dynamic, path:String, owner:String, kind:String, includeInSourceBundle:Bool):Void {
		final entries:Array<Dynamic> = cast Reflect.field(manifest, "entries");
		for (entry in entries) {
			if (Reflect.field(entry, "path") != path)
				continue;
			assertTrue(Reflect.field(entry, "owner") == owner, 'artifact "$path" owner mismatch');
			assertTrue(Reflect.field(entry, "kind") == kind, 'artifact "$path" role mismatch');
			assertTrue(Reflect.field(entry, "includeInSourceBundle") == includeInSourceBundle, 'artifact "$path" source-bundle membership mismatch');
			return;
		}
		throw 'artifact manifest does not contain "$path"';
	}

	public static function assertMissingEntry(manifest:Dynamic, path:String):Void {
		final entries:Array<Dynamic> = cast Reflect.field(manifest, "entries");
		for (entry in entries) {
			if (Reflect.field(entry, "path") == path)
				throw 'artifact manifest unexpectedly contains "$path"';
		}
	}

	static function collectOwnedFiles(absoluteDirectory:String, relativeDirectory:String, out:Array<String>):Void {
		final names = FileSystem.readDirectory(absoluteDirectory);
		names.sort(compareStrings);
		for (name in names) {
			final relative = relativeDirectory.length == 0 ? name : relativeDirectory + "/" + name;
			if (relative == "_build" || StringTools.startsWith(relative, "_build/"))
				continue;
			final absolute = Path.join([absoluteDirectory, name]);
			if (FileSystem.isDirectory(absolute)) {
				collectOwnedFiles(absolute, relative, out);
			} else if (relative != "_GeneratedFiles.json"
				&& relative != "ocaml_artifact_manifest.json"
				&& !StringTools.endsWith(relative, ".install")) {
				out.push(relative);
			}
		}
	}

	static function assertSafeRelativePath(path:String):Void {
		final normalized = path == null ? "" : StringTools.replace(path, "\\", "/");
		final parts = normalized.split("/");
		assertTrue(normalized.length > 0 && !Path.isAbsolute(normalized) && !parts.contains("") && !parts.contains(".") && !parts.contains(".."),
			'unsafe artifact path "$path"');
	}

	static function assertArrayEquals(expected:Array<String>, actual:Array<String>, message:String):Void {
		assertTrue(expected.length == actual.length, '$message: expected ${expected.length} paths, found ${actual.length}');
		for (index in 0...expected.length)
			assertTrue(expected[index] == actual[index], '$message at index $index: expected ${expected[index]}, found ${actual[index]}');
	}

	static function nonEmptyString(value:Dynamic):Bool {
		return Std.isOfType(value, String) && StringTools.trim(cast value).length > 0;
	}

	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}
}
