import haxe.Json;
import haxe.crypto.Sha256;
import haxe.io.Path;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestBuilder;
import reflaxe.ocaml.artifacts.OcamlArtifactConfigurationRevision;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactAuthority;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactKind;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactOwner;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactSourceKind;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactStability;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestSchema;
import reflaxe.ocaml.artifacts.OcamlSourceBundleAuthority;
import reflaxe.ocaml.artifacts.OcamlSourceBundleAuthority.OcamlNativeSourceDeclaration;
import reflaxe.ocaml.runtimegen.RuntimeSourceManifestModel.RuntimeSourceManifestSnapshot;
import sys.FileSystem;
import sys.io.File;

using StringTools;

/** Focused executable checks for generated OCaml artifact ownership. **/
class ArtifactManifestFixture {
	static final PROGRAM_REVISION = "sha256:" + Sha256.encode("program");
	static final CONFIGURATION_REVISION = "sha256:" + Sha256.encode("configuration");

	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
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

	static function incompleteAuthority(model:String, message:String):OcamlArtifactAuthority {
		return {
			status: OcamlArtifactManifestSchema.AUTHORITY_INCOMPLETE,
			model: model,
			revision: null,
			message: message
		};
	}

	static function completeAuthority(model:String, seed:String):OcamlArtifactAuthority {
		return {
			status: OcamlArtifactManifestSchema.AUTHORITY_COMPLETE,
			model: model,
			revision: "sha256:" + Sha256.encode(seed),
			message: "$model is complete."
		};
	}

	static function createDirectory(path:String):Void {
		if (FileSystem.exists(path))
			return;
		final parent = Path.directory(path);
		if (parent != null && parent.length > 0 && parent != path)
			createDirectory(parent);
		FileSystem.createDirectory(path);
	}

	static function write(path:String, contents:String):Void {
		createDirectory(Path.directory(path));
		File.saveContent(path, contents);
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

	static function prepareOutput(root:String, frameworkFiles:Array<String>):Void {
		createDirectory(root);
		for (path in frameworkFiles)
			write(Path.join([root, path]), '(* $path *)\n');
		write(Path.join([root, OcamlArtifactManifestSchema.FRAMEWORK_RECEIPT]), Json.stringify({
			version: 1,
			id: 7,
			wasCached: false,
			filesGenerated: frameworkFiles
		}, null, "  ") + "\n");
	}

	static function recordGenerated(builder:OcamlArtifactManifestBuilder, path:String, kind:OcamlArtifactKind, owner:OcamlArtifactOwner,
			includeInSourceBundle:Bool = true, stability:OcamlArtifactStability = Stable):Void {
		builder.record({
			path: path,
			kind: kind,
			owner: owner,
			sourceKind: OcamlArtifactSourceKind.Generated,
			sourcePath: null,
			license: "generated-output",
			profileEligibility: ["portable", "metal"],
			stability: stability,
			includeInSourceBundle: includeInSourceBundle
		});
	}

	static function buildNormalManifest(root:String, timingContents:String) {
		write(Path.join([root, "dune-project"]), "(lang dune 3.10)\n");
		write(Path.join([root, "ocaml_build_timing_report.json"]), timingContents);
		final builder = new OcamlArtifactManifestBuilder(root, PROGRAM_REVISION, CONFIGURATION_REVISION, "portable");
		builder.recordFrameworkModules();
		recordGenerated(builder, "dune-project", OcamlArtifactKind.DuneProject, OcamlArtifactOwner.DuneScaffold);
		recordGenerated(builder, "ocaml_build_timing_report.json", OcamlArtifactKind.CompilerReport, OcamlArtifactOwner.BuildTimingReport, false,
			OcamlArtifactStability.Volatile);
		return builder.seal(incompleteAuthority("semantic-runtime-requirements-v0", "Semantic runtime ownership is not complete."),
			incompleteAuthority("native-dependency-manifest-v0", "Native dependency ownership is not complete."));
	}

	static function testStableAndVolatileRevisions(root:String):Void {
		final output = Path.join([root, "normal"]);
		prepareOutput(output, ["Main.ml", "nested/Thing.ml"]);
		final first = buildNormalManifest(output, "{\"elapsed\":1}\n");
		assertTrue(first.entries.length == 4, "all producer-owned files should be present exactly once");
		assertTrue(first.entries[0].path == "Main.ml" && first.entries[3].path == "ocaml_build_timing_report.json",
			"manifest entries should be sorted by path");
		assertTrue(!first.summary.completeForSourceBundle, "incomplete prerequisite authorities must block source bundling");
		assertTrue(first.summary.blockers.length == 2, "both incomplete prerequisite authorities should be explained");
		OcamlArtifactManifestSchema.loadAndValidate(output, PROGRAM_REVISION, CONFIGURATION_REVISION);

		final second = buildNormalManifest(output, "{\"elapsed\":999}\n");
		assertTrue(first.summary.sourceBundleRevision == second.summary.sourceBundleRevision,
			"volatile timing evidence must not change the reproducible source-bundle revision");
		assertTrue(first.summary.artifactSetRevision != second.summary.artifactSetRevision,
			"the complete artifact-set revision must reflect changed timing evidence");
	}

	static function testCompleteAuthorities(root:String):Void {
		final output = Path.join([root, "complete"]);
		prepareOutput(output, ["Main.ml"]);
		final builder = new OcamlArtifactManifestBuilder(output, PROGRAM_REVISION, CONFIGURATION_REVISION, "metal");
		builder.recordFrameworkModules();
		final report = builder.seal(completeAuthority("semantic-runtime-requirements-v1", "runtime"),
			completeAuthority("native-dependency-manifest-v1", "dependencies"));
		assertTrue(report.summary.completeForSourceBundle, "complete revisioned authorities should allow source bundling");
		assertTrue(report.summary.blockers.length == 0, "a complete manifest should not report prerequisite blockers");
	}

	static function testSourceBundleAuthorities():Void {
		final executableConfig:OcamlNativeSourceDeclaration = {
			projectName: "fixture",
			exeName: "fixture",
			mainModuleId: "Main",
			pluginMainModuleId: null,
			pluginRegisterPluginId: null,
			pluginRegisterProviderType: null,
			pluginLoadMarker: null,
			duneLibraries: ["unix", "str"],
			duneLayout: "exe",
			executables: null
		};
		final native = OcamlSourceBundleAuthority.nativeDeclarations(executableConfig);
		assertTrue(native.status == OcamlArtifactManifestSchema.AUTHORITY_COMPLETE,
			"normalized native source declarations should be complete for source replay");
		assertTrue(native.revision == OcamlSourceBundleAuthority.nativeDeclarations(executableConfig).revision,
			"equivalent native source declarations should have one revision");
		final reorderedConfig:OcamlNativeSourceDeclaration = {
			projectName: executableConfig.projectName,
			exeName: executableConfig.exeName,
			mainModuleId: executableConfig.mainModuleId,
			pluginMainModuleId: executableConfig.pluginMainModuleId,
			pluginRegisterPluginId: executableConfig.pluginRegisterPluginId,
			pluginRegisterProviderType: executableConfig.pluginRegisterProviderType,
			pluginLoadMarker: executableConfig.pluginLoadMarker,
			duneLibraries: ["str", "unix"],
			duneLayout: executableConfig.duneLayout,
			executables: executableConfig.executables
		};
		assertTrue(native.revision != OcamlSourceBundleAuthority.nativeDeclarations(reorderedConfig).revision,
			"native library emission order should participate in source declaration identity");

		final runtimeManifest:RuntimeSourceManifestSnapshot = {
			schemaVersion: 1,
			model: "fixture-runtime",
			runtimeVersion: "fixture-v1",
			revision: "sha256:" + Sha256.encode("runtime-manifest"),
			modules: [
				{
					module: "HxRuntime",
					scope: "application",
					files: [
						{
							path: "HxRuntime.ml",
							sha256: "sha256:" + Sha256.encode("runtime-file"),
							bytes: 14
						}
					],
					dependencies: [],
					duneLibraries: ["unix"],
					profiles: ["portable"],
					license: "MIT"
				}
			]
		};
		final requirementRevision = "sha256:" + Sha256.encode("requirements");
		final runtime = OcamlSourceBundleAuthority.semanticRuntime(runtimeManifest, requirementRevision, "portable", "selective", "recorded", false,
			runtimeManifest.modules);
		assertTrue(runtime.status == OcamlArtifactManifestSchema.AUTHORITY_COMPLETE,
			"a checked runtime manifest plus exact selected closure should be complete for source replay");
		assertTrue(runtime.revision != OcamlSourceBundleAuthority.semanticRuntime(runtimeManifest, "sha256:" + Sha256.encode("changed"), "portable",
			"selective", "recorded", false, runtimeManifest.modules)
			.revision,
			"runtime requirement changes should invalidate semantic runtime authority");
		assertTrue(OcamlSourceBundleAuthority.semanticRuntimeDisabled().status == OcamlArtifactManifestSchema.AUTHORITY_COMPLETE,
			"an explicitly disabled runtime should own its empty source selection");
		assertTrue(OcamlSourceBundleAuthority.nativeDeclarationsDisabled().status == OcamlArtifactManifestSchema.AUTHORITY_COMPLETE,
			"explicitly disabled Dune scaffolding should own its empty native source declaration");
	}

	static function testRegistrationFailures(root:String):Void {
		final unsafeOutput = Path.join([root, "unsafe"]);
		prepareOutput(unsafeOutput, []);
		final unsafeBuilder = new OcamlArtifactManifestBuilder(unsafeOutput, PROGRAM_REVISION, CONFIGURATION_REVISION, "portable");
		expectFailure("unsafe path", "not a safe output-relative path",
			() -> recordGenerated(unsafeBuilder, "../escape.ml", OcamlArtifactKind.EntrySource, OcamlArtifactOwner.CompilerCore));

		final ownerOutput = Path.join([root, "owner"]);
		prepareOutput(ownerOutput, []);
		write(Path.join([ownerOutput, "Mystery.ml"]), "let value = 1\n");
		final ownerBuilder = new OcamlArtifactManifestBuilder(ownerOutput, PROGRAM_REVISION, CONFIGURATION_REVISION, "portable");
		expectFailure("unknown owner", "unknown owner",
			() -> recordGenerated(ownerBuilder, "Mystery.ml", OcamlArtifactKind.EntrySource, cast "mystery-producer"));

		final duplicateOutput = Path.join([root, "duplicate"]);
		prepareOutput(duplicateOutput, []);
		write(Path.join([duplicateOutput, "Main.ml"]), "let value = 1\n");
		final duplicateBuilder = new OcamlArtifactManifestBuilder(duplicateOutput, PROGRAM_REVISION, CONFIGURATION_REVISION, "portable");
		recordGenerated(duplicateBuilder, "Main.ml", OcamlArtifactKind.EntrySource, OcamlArtifactOwner.CompilerCore);
		expectFailure("duplicate claim", "registered more than once",
			() -> recordGenerated(duplicateBuilder, "Main.ml", OcamlArtifactKind.EntrySource, OcamlArtifactOwner.CompilerCore));

		final missingOutput = Path.join([root, "missing"]);
		prepareOutput(missingOutput, []);
		final missingBuilder = new OcamlArtifactManifestBuilder(missingOutput, PROGRAM_REVISION, CONFIGURATION_REVISION, "portable");
		recordGenerated(missingBuilder, "Missing.ml", OcamlArtifactKind.EntrySource, OcamlArtifactOwner.CompilerCore);
		expectFailure("missing file", "is missing or is not a file",
			() -> missingBuilder.seal(incompleteAuthority("runtime-v0", "runtime incomplete"),
				incompleteAuthority("dependencies-v0", "dependencies incomplete")));

		final extraOutput = Path.join([root, "extra"]);
		prepareOutput(extraOutput, []);
		write(Path.join([extraOutput, "unclaimed.ml"]), "let value = 1\n");
		final extraBuilder = new OcamlArtifactManifestBuilder(extraOutput, PROGRAM_REVISION, CONFIGURATION_REVISION, "portable");
		extraBuilder.recordFrameworkModules();
		expectFailure("unregistered file", "unregistered non-cache file",
			() -> extraBuilder.seal(incompleteAuthority("runtime-v0", "runtime incomplete"),
				incompleteAuthority("dependencies-v0", "dependencies incomplete")));
	}

	static function testStaleCleanup(root:String):Void {
		final cleanOutput = Path.join([root, "stale-clean"]);
		prepareOutput(cleanOutput, []);
		write(Path.join([cleanOutput, "old/Generated.ml"]), "let old = true\n");
		var builder = new OcamlArtifactManifestBuilder(cleanOutput, PROGRAM_REVISION, CONFIGURATION_REVISION, "portable");
		builder.recordFrameworkModules();
		recordGenerated(builder, "old/Generated.ml", OcamlArtifactKind.EntrySource, OcamlArtifactOwner.CompilerCore);
		builder.seal(incompleteAuthority("runtime-v0", "runtime incomplete"), incompleteAuthority("dependencies-v0", "dependencies incomplete"));
		builder = new OcamlArtifactManifestBuilder(cleanOutput, PROGRAM_REVISION, CONFIGURATION_REVISION, "portable");
		builder.recordFrameworkModules();
		builder.seal(incompleteAuthority("runtime-v0", "runtime incomplete"), incompleteAuthority("dependencies-v0", "dependencies incomplete"));
		assertTrue(!FileSystem.exists(Path.join([cleanOutput, "old/Generated.ml"])),
			"an obsolete compiler-owned file should be removed when its prior digest still matches");

		final modifiedOutput = Path.join([root, "stale-modified"]);
		prepareOutput(modifiedOutput, []);
		write(Path.join([modifiedOutput, "old/Generated.ml"]), "let old = true\n");
		builder = new OcamlArtifactManifestBuilder(modifiedOutput, PROGRAM_REVISION, CONFIGURATION_REVISION, "portable");
		builder.recordFrameworkModules();
		recordGenerated(builder, "old/Generated.ml", OcamlArtifactKind.EntrySource, OcamlArtifactOwner.CompilerCore);
		builder.seal(incompleteAuthority("runtime-v0", "runtime incomplete"), incompleteAuthority("dependencies-v0", "dependencies incomplete"));
		write(Path.join([modifiedOutput, "old/Generated.ml"]), "let user_edit = true\n");
		builder = new OcamlArtifactManifestBuilder(modifiedOutput, PROGRAM_REVISION, CONFIGURATION_REVISION, "portable");
		builder.recordFrameworkModules();
		expectFailure("modified obsolete file", "Refusing to delete modified obsolete",
			() -> builder.seal(incompleteAuthority("runtime-v0", "runtime incomplete"), incompleteAuthority("dependencies-v0", "dependencies incomplete")));
		assertTrue(FileSystem.exists(Path.join([modifiedOutput, "old/Generated.ml"])), "a modified obsolete file must be preserved");
	}

	static function testSealedValidation(root:String):Void {
		final output = Path.join([root, "validate"]);
		prepareOutput(output, ["Main.ml"]);
		buildNormalManifest(output, "{\"elapsed\":1}\n");
		expectFailure("stale program revision", "stale program revision",
			() -> OcamlArtifactManifestSchema.loadAndValidate(output, "sha256:" + Sha256.encode("other-program"), CONFIGURATION_REVISION));
		write(Path.join([output, "Main.ml"]), "(* modified *)\n");
		expectFailure("digest mismatch", "digest mismatch",
			() -> OcamlArtifactManifestSchema.loadAndValidate(output, PROGRAM_REVISION, CONFIGURATION_REVISION));
	}

	static function testWorkingDirectoryIndependence(root:String):Void {
		final output = Path.join([root, "working-directory"]);
		prepareOutput(output, []);
		write(Path.join([output, "Generated.mli"]), "val answer : int\n");
		var builder = new OcamlArtifactManifestBuilder(output, PROGRAM_REVISION, CONFIGURATION_REVISION, "portable");
		builder.recordFrameworkModules();
		recordGenerated(builder, "Generated.mli", OcamlArtifactKind.InferredInterface, OcamlArtifactOwner.MliInference);
		builder.seal(incompleteAuthority("runtime-v0", "runtime incomplete"), incompleteAuthority("dependencies-v0", "dependencies incomplete"));

		builder = new OcamlArtifactManifestBuilder(output, PROGRAM_REVISION, CONFIGURATION_REVISION, "portable");
		final previousDirectory = Sys.getCwd();
		try {
			Sys.setCwd(output);
			assertTrue(builder.isUnchangedPrevious("Generated.mli"),
				"prior generated files should remain identifiable while a build tool changes the working directory");
		} catch (error:Dynamic) {
			Sys.setCwd(previousDirectory);
			throw error;
		}
		Sys.setCwd(previousDirectory);
	}

	static function testConfigurationRevision():Void {
		final left:Map<String, String> = [
			"ocaml_profile" => "Portable",
			"ocaml_runtime_modules" => "HxString,HxRuntime,HxString"
		];
		final right:Map<String, String> = ["ocaml_runtime_modules" => "HxRuntime, HxString", "ocaml_profile" => "portable"];
		final leftRevision = OcamlArtifactConfigurationRevision.fromValues("target-pipeline-v1", "example_project", left);
		final rightRevision = OcamlArtifactConfigurationRevision.fromValues("target-pipeline-v1", "example_project", right);
		assertTrue(leftRevision == rightRevision, "equivalent normalized source settings should have one configuration revision");
		assertTrue(leftRevision != OcamlArtifactConfigurationRevision.fromValues("target-pipeline-v2", "example_project", right),
			"a target-pipeline change should invalidate the source configuration");
		assertTrue(leftRevision != OcamlArtifactConfigurationRevision.fromValues("target-pipeline-v1", "other_project", right),
			"a generated Dune project-name change should invalidate the source configuration");
		expectFailure("unknown source setting", "Unknown OCaml source-configuration setting",
			() -> OcamlArtifactConfigurationRevision.fromValues("target-pipeline-v1", "example_project", ["ocaml_build_timing_report" => "1"]));
	}

	static function main():Void {
		final root = ".tmp/reflaxe_ocaml_artifact_manifest_"
			+ Std.string(Std.int(Date.now().getTime()))
			+ "_"
			+ Std.string(Std.random(1000000));
		createDirectory(root);
		try {
			testStableAndVolatileRevisions(root);
			testCompleteAuthorities(root);
			testSourceBundleAuthorities();
			testRegistrationFailures(root);
			testStaleCleanup(root);
			testSealedValidation(root);
			testWorkingDirectoryIndependence(root);
			testConfigurationRevision();
		} catch (error:Dynamic) {
			removeTree(root);
			throw error;
		}
		removeTree(root);
		Sys.println("REFLAXE_OCAML_ARTIFACT_MANIFEST_FIXTURE:PASS");
	}
}
