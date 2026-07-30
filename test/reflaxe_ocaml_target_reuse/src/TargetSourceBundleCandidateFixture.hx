import haxe.crypto.Sha256;
import haxe.io.Bytes;
import haxe.io.Path;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactAuthority;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactEntry;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlSourceBundleSnapshot;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestSchema;
import reflaxe.ocaml.reuse.OcamlSourceBundleCandidate;
import sys.FileSystem;
import sys.io.File;

/** Proves that the packed reuse candidate is detached, exact, and fail-closed. **/
class TargetSourceBundleCandidateFixture {
	static inline final OUTPUT_DIRECTORY = "out_source_bundle_candidate_fixture";

	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function main():Void {
		deleteTree(OUTPUT_DIRECTORY);
		FileSystem.createDirectory(OUTPUT_DIRECTORY);
		try {
			runFixture();
		} catch (error:Dynamic) {
			deleteTree(OUTPUT_DIRECTORY);
			throw error;
		}
		deleteTree(OUTPUT_DIRECTORY);
	}

	static function runFixture():Void {
		final first = Bytes.ofString("let first = 1\n");
		final second = Bytes.ofString("let second = 2\n");
		File.saveBytes(Path.join([OUTPUT_DIRECTORY, "A.ml"]), first);
		FileSystem.createDirectory(Path.join([OUTPUT_DIRECTORY, "nested"]));
		File.saveBytes(Path.join([OUTPUT_DIRECTORY, "nested", "B.ml"]), second);
		final runtime = authority("fixture-runtime-v1", "runtime");
		final native = authority("fixture-native-v1", "native");
		final entries = [entry("A.ml", first), entry("nested/B.ml", second)];
		final sourceRevision = OcamlArtifactManifestSchema.calculateArtifactRevision(revision("program"), revision("configuration"), "portable", entries,
			runtime, native, "source-bundle");
		final snapshot:OcamlSourceBundleSnapshot = {
			schemaVersion: OcamlArtifactManifestSchema.SCHEMA_VERSION,
			model: OcamlArtifactManifestSchema.MODEL,
			programRevision: revision("program"),
			configurationRevision: revision("configuration"),
			profile: "portable",
			entries: entries,
			authorities: {
				semanticRuntime: runtime,
				nativeDependencies: native
			},
			sourceBundleRevision: sourceRevision,
			completeForSourceBundle: true,
			blockers: []
		};
		final requestRevision = revision("request");
		final candidate = OcamlSourceBundleCandidate.pack(OUTPUT_DIRECTORY, requestRevision, snapshot, true);
		assertTrue(candidate.targetRequestRevision == requestRevision
			&& candidate.sourceBundleRevision == sourceRevision
			&& candidate.entries.length == 2
			&& candidate.packedBytes == first.length + second.length
			&& candidate.indexBytes > 0
			&& candidate.payloadBytes > candidate.packedBytes + candidate.indexBytes,
			"candidate should record the exact request, bundle, index, and packed-byte sizes");
		assertTrue(candidate.copyFile(candidate.entries[0]).toString() == first.toString()
			&& candidate.copyFile(candidate.entries[1]).toString() == second.toString(),
			"decoded candidate should reproduce every verified file");
		expectFailure(() -> OcamlSourceBundleCandidate.pack(OUTPUT_DIRECTORY, requestRevision, snapshot, true, candidate.payloadBytes - 1), "entry cap");

		// The packed value must remain independent of later source-directory changes.
		File.saveContent(Path.join([OUTPUT_DIRECTORY, "A.ml"]), "changed after packing\n");
		assertTrue(candidate.copyFile(candidate.entries[0]).toString() == first.toString(), "candidate should own copied immutable bytes");

		final corrupted = candidate.copyPayload();
		corrupted.set(corrupted.length - 1, corrupted.get(corrupted.length - 1) ^ 0xff);
		expectFailure(() -> OcamlSourceBundleCandidate.decode(corrupted), "digest mismatch");
		Sys.println("REFLAXE_OCAML_SOURCE_BUNDLE_CANDIDATE:PASS");
	}

	static function entry(path:String, bytes:Bytes):OcamlArtifactEntry {
		return {
			path: path,
			kind: "haxe-module-source",
			owner: "ocaml-compiler",
			sourceKind: "generated",
			sourcePath: null,
			license: "generated-output",
			profileEligibility: ["portable"],
			stability: "stable",
			includeInSourceBundle: true,
			sha256: "sha256:" + Sha256.make(bytes).toHex(),
			bytes: bytes.length
		};
	}

	static function authority(model:String, value:String):OcamlArtifactAuthority {
		return {
			status: OcamlArtifactManifestSchema.AUTHORITY_COMPLETE,
			model: model,
			revision: revision(value),
			message: "fixture authority is complete"
		};
	}

	static function revision(value:String):String
		return "sha256:" + Sha256.encode(value);

	static function expectFailure(action:() -> Void, expected:String):Void {
		var failed = false;
		try {
			action();
		} catch (error:Dynamic) {
			failed = Std.string(error).toLowerCase().indexOf(expected.toLowerCase()) != -1;
		}
		assertTrue(failed, 'expected failure containing "$expected"');
	}

	static function deleteTree(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (!FileSystem.isDirectory(path)) {
			FileSystem.deleteFile(path);
			return;
		}
		for (entry in FileSystem.readDirectory(path))
			deleteTree(Path.join([path, entry]));
		FileSystem.deleteDirectory(path);
	}
}
