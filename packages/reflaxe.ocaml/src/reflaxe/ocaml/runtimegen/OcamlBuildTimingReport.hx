package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime)
import haxe.Json;
import haxe.io.Path;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestBuilder;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactKind;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactOwner;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactSourceKind;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactStability;
import sys.FileSystem;
import sys.io.File;

/** One subprocess or target-owned native build step measured at its execution boundary. **/
typedef OcamlBuildTimingPhase = {
	final id:String;
	final elapsedMilliseconds:Int;
	final exitCode:Int;
}

/** Stable summary of the target-owned Dune work performed after OCaml source emission. **/
typedef OcamlBuildTimingSummary = {
	final status:String;
	final exitCode:Int;
	final nativeBuildRan:Bool;
	final duneBuildMilliseconds:Null<Int>;
	final interfaceMilliseconds:Int;
	final targetRunMilliseconds:Null<Int>;
}

/**
	Machine-readable timing evidence for one target-owned native build attempt.

	The report deliberately does not call the Dune duration "compile time": its
	total may include both the initial typecheck/compile/link build and an
	interface-validation rebuild. It also does not infer cache hits from a short
	duration or split executable loading, startup, and workload time.
**/
typedef OcamlBuildTimingReport = {
	final schemaVersion:Int;
	final generatedFilesReceiptId:Int;
	final mode:String;
	final duneLayout:String;
	final target:String;
	final strict:Bool;
	final requestedRun:Bool;
	final mliMode:Null<String>;
	final phases:Array<OcamlBuildTimingPhase>;
	final boundaries:{
		final duneBuildIncludes:Array<String>;
		final duneCacheHitsMeasured:Bool;
		final loadSeparated:Bool;
		final startupSeparated:Bool;
		final workloadRuntimeSeparated:Bool;
	};
	final summary:OcamlBuildTimingSummary;
}

/** Writes native timing evidence next to the generated OCaml project. **/
class OcamlBuildTimingReportWriter {
	public static inline final FILE_NAME = "ocaml_build_timing_report.json";
	static inline final GENERATED_FILES = "_GeneratedFiles.json";

	/** Removes timing from an earlier output revision before a new build can replace it. **/
	public static function clear(outputDirectory:String):Void {
		for (name in [FILE_NAME, FILE_NAME + ".tmp"]) {
			final path = Path.join([outputDirectory, name]);
			if (FileSystem.exists(path)) {
				if (FileSystem.isDirectory(path)) {
					throw 'Cannot clear native timing evidence because "$path" is a directory.';
				}
				FileSystem.deleteFile(path);
			}
		}
	}

	/**
		Writes a report tied to the current Reflaxe generated-file receipt.

		A missing or malformed receipt is an internal error: without its monotonically
		changing ID, inspection could accidentally present timing from an older build.
	**/
	public static function write(outputDirectory:String, mode:String, duneLayout:String, target:String, strict:Bool, requestedRun:Bool, mliMode:Null<String>,
			phases:Array<OcamlBuildTimingPhase>, summary:OcamlBuildTimingSummary, artifacts:OcamlArtifactManifestBuilder):Void {
		final report:OcamlBuildTimingReport = {
			schemaVersion: 1,
			generatedFilesReceiptId: readGeneratedFilesReceiptId(outputDirectory),
			mode: mode,
			duneLayout: duneLayout,
			target: target,
			strict: strict,
			requestedRun: requestedRun,
			mliMode: mliMode,
			phases: phases.copy(),
			boundaries: {
				duneBuildIncludes: ["typecheck", "compile", "link"],
				duneCacheHitsMeasured: false,
				loadSeparated: false,
				startupSeparated: false,
				workloadRuntimeSeparated: false
			},
			summary: summary
		};
		writeAtomically(Path.join([outputDirectory, FILE_NAME]), Json.stringify(report, null, "  ") + "\n");
		artifacts.record({
			path: FILE_NAME,
			kind: OcamlArtifactKind.CompilerReport,
			owner: OcamlArtifactOwner.BuildTimingReport,
			sourceKind: OcamlArtifactSourceKind.Generated,
			sourcePath: null,
			license: "generated-output",
			profileEligibility: ["portable", "metal"],
			stability: OcamlArtifactStability.Volatile,
			includeInSourceBundle: false
		});
	}

	static function readGeneratedFilesReceiptId(outputDirectory:String):Int {
		final path = Path.join([outputDirectory, GENERATED_FILES]);
		if (!FileSystem.exists(path) || FileSystem.isDirectory(path)) {
			throw 'Cannot write native timing report because $GENERATED_FILES is missing.';
		}
		try {
			final value:Dynamic = Json.parse(File.getContent(path));
			final version:Dynamic = Reflect.field(value, "version");
			final id:Dynamic = Reflect.field(value, "id");
			if (!Std.isOfType(version, Int) || version != 1 || !Std.isOfType(id, Int) || id < 0) {
				throw 'expected version=1 and a non-negative integer id';
			}
			return cast id;
		} catch (error:Dynamic) {
			throw 'Cannot write native timing report because $GENERATED_FILES is invalid: ${Std.string(error)}';
		}
	}

	static function writeAtomically(path:String, contents:String):Void {
		final temporary = path + ".tmp";
		try {
			File.saveContent(temporary, contents);
			try {
				FileSystem.rename(temporary, path);
			} catch (_:Dynamic) {
				// Windows does not consistently replace an existing destination.
				if (FileSystem.exists(path) && !FileSystem.isDirectory(path)) {
					FileSystem.deleteFile(path);
				}
				FileSystem.rename(temporary, path);
			}
		} catch (error:Dynamic) {
			if (FileSystem.exists(temporary) && !FileSystem.isDirectory(temporary)) {
				try {
					FileSystem.deleteFile(temporary);
				} catch (_:Dynamic) {}
			}
			throw error;
		}
	}
}
#end
