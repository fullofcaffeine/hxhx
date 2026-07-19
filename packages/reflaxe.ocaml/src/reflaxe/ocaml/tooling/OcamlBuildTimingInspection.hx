package reflaxe.ocaml.tooling;

import haxe.Json;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import reflaxe.ocaml.tooling.InspectionReport.InspectionBuildTiming;
import reflaxe.ocaml.tooling.InspectionReport.InspectionBuildTimingPhase;

using StringTools;

private enum BuildTimingJsonResult {
	Missing;
	Invalid(message:String);
	Loaded(value:Dynamic);
}

private enum GeneratedReceiptIdResult {
	ReceiptId(value:Int);
	ReceiptError(message:String);
}

/**
	Validates target-owned native timing without inferring unmeasured phases.

	Schema 1 deliberately treats Dune typechecking, compilation, and linking as
	one phase. It rejects claims about cache hits, loading, startup, or workload
	runtime because the current target does not measure those boundaries.
**/
class OcamlBuildTimingInspection {
	public static inline final FILE_NAME = "ocaml_build_timing_report.json";
	static inline final GENERATED_FILES = "_GeneratedFiles.json";

	/** Reads timing only when it belongs to the current generated output receipt. **/
	public static function inspectOutput(outputDirectory:String):InspectionBuildTiming {
		final timingPath = Path.join([outputDirectory, FILE_NAME]);
		if (!FileSystem.exists(timingPath)) {
			return inspect(timingPath, null);
		}
		return switch (readGeneratedReceiptId(outputDirectory)) {
			case ReceiptId(value): inspect(timingPath, value);
			case ReceiptError(message): failure("invalid", timingPath, message);
		};
	}

	/** Reads and validates one optional timing report against an expected receipt. **/
	public static function inspect(path:String, expectedReceiptId:Null<Int>):InspectionBuildTiming {
		return switch (readJson(path)) {
			case Missing:
				failure("not-enabled", path, "Native phase timing was not requested. Builds run through the authoring command enable it automatically.");
			case Invalid(message):
				failure("invalid", path, message);
			case Loaded(value):
				try {
					final version = requiredInt(value, "schemaVersion");
					if (version != 1) {
						throw 'Unsupported native timing report schema $version; expected 1.';
					}
					final receiptId = nonNegativeInt(value, "generatedFilesReceiptId");
					if (expectedReceiptId != null && receiptId != expectedReceiptId) {
						throw 'Native timing belongs to generated receipt $receiptId, but the current receipt is $expectedReceiptId. Rebuild before inspecting.';
					}
					final mode = requiredString(value, "mode");
					if (!["native", "byte", "bytecode"].contains(mode)) {
						throw 'Unsupported native timing mode "$mode".';
					}
					final duneLayout = requiredString(value, "duneLayout");
					if (!["executable", "library", "plugin"].contains(duneLayout)) {
						throw 'Unsupported native timing Dune layout "$duneLayout".';
					}
					final target = requiredString(value, "target");
					if (target != "@all" && !~/^\.\/[A-Za-z0-9_.-]+\.(?:exe|bc)$/.match(target)) {
						throw 'Native timing contains unsafe or unsupported Dune target "$target".';
					}
					validateTarget(mode, duneLayout, target);
					final strict = requiredBool(value, "strict");
					final requestedRun = requiredBool(value, "requestedRun");
					final mliMode = optionalString(value, "mliMode");
					final phases = readPhases(value);
					final boundaries = requiredObject(value, "boundaries");
					final duneBuildIncludes = requiredStringArray(boundaries, "duneBuildIncludes");
					if (duneBuildIncludes.join(",") != "typecheck,compile,link") {
						throw "Native timing must describe the combined Dune typecheck, compile, and link boundary.";
					}
					final duneCacheHitsMeasured = requiredBool(boundaries, "duneCacheHitsMeasured");
					final loadSeparated = requiredBool(boundaries, "loadSeparated");
					final startupSeparated = requiredBool(boundaries, "startupSeparated");
					final workloadRuntimeSeparated = requiredBool(boundaries, "workloadRuntimeSeparated");
					if (duneCacheHitsMeasured || loadSeparated || startupSeparated || workloadRuntimeSeparated) {
						throw "Native timing schema 1 must not claim cache-hit, load, startup, or workload-runtime separation.";
					}
					final summary = requiredObject(value, "summary");
					final buildStatus = requiredString(summary, "status");
					if (!["passed", "failed"].contains(buildStatus)) {
						throw 'Unsupported native timing status "$buildStatus".';
					}
					final buildExitCode = nonNegativeInt(summary, "exitCode");
					final nativeBuildRan = requiredBool(summary, "nativeBuildRan");
					final duneBuildMilliseconds = nullableNonNegativeInt(summary, "duneBuildMilliseconds");
					final interfaceMilliseconds = nonNegativeInt(summary, "interfaceMilliseconds");
					final targetRunMilliseconds = nullableNonNegativeInt(summary, "targetRunMilliseconds");
					validateSummary(phases, buildStatus, buildExitCode, nativeBuildRan, duneBuildMilliseconds, interfaceMilliseconds, targetRunMilliseconds,
						requestedRun);
					{
						status: "present",
						path: path,
						schemaVersion: version,
						generatedFilesReceiptId: receiptId,
						mode: mode,
						duneLayout: duneLayout,
						target: target,
						strict: strict,
						requestedRun: requestedRun,
						mliMode: mliMode,
						phases: phases,
						buildStatus: buildStatus,
						buildExitCode: buildExitCode,
						nativeBuildRan: nativeBuildRan,
						duneBuildMilliseconds: duneBuildMilliseconds,
						interfaceMilliseconds: interfaceMilliseconds,
						targetRunMilliseconds: targetRunMilliseconds,
						duneBuildIncludes: duneBuildIncludes,
						duneCacheHitsMeasured: duneCacheHitsMeasured,
						loadSeparated: loadSeparated,
						startupSeparated: startupSeparated,
						workloadRuntimeSeparated: workloadRuntimeSeparated,
						message: "Target-owned native timing report is valid; Dune typecheck, compile, and link remain combined."
					};
				} catch (error:Dynamic) {
					failure("invalid", path, Std.string(error));
				}
		};
	}

	/** Renders one concise line without turning an honest failed attempt into invalid JSON. **/
	public static function renderHuman(value:InspectionBuildTiming):String {
		return switch (value.status) {
			case "present":
				if (value.nativeBuildRan == true) {
					final label = value.buildStatus == "passed" ? "[PASS]" : "[INFO]";
					'$label Native Dune timing: ${value.duneBuildMilliseconds}ms for typecheck + compile + link combined; cache hits are not inferred.';
				} else {
					'[INFO] Native Dune timing: no Dune build ran; target result=${value.buildStatus} exit=${value.buildExitCode}.';
				}
			case "not-enabled":
				'[SKIP] Native Dune timing: ${value.message}';
			case _:
				'[FAIL] Native Dune timing: ${value.message}';
		};
	}

	static function readGeneratedReceiptId(outputDirectory:String):GeneratedReceiptIdResult {
		final path = Path.join([outputDirectory, GENERATED_FILES]);
		return switch (readJson(path)) {
			case Missing: ReceiptError("Generated-file receipt is missing; native timing cannot be correlated safely.");
			case Invalid(message): ReceiptError(message);
			case Loaded(value):
				try {
					final version = requiredInt(value, "version");
					if (version != 1) {
						throw 'Unsupported generated-file receipt schema $version; expected 1.';
					}
					ReceiptId(nonNegativeInt(value, "id"));
				} catch (error:Dynamic) {
					ReceiptError(Std.string(error));
				}
		};
	}

	static function readPhases(value:Dynamic):Array<InspectionBuildTimingPhase> {
		final allowed = [
			"native_toolchain_probe",
			"mli_toolchain_probe",
			"dune_build",
			"mli_ensure",
			"mli_infer",
			"mli_rebuild",
			"dune_exec"
		];
		final seen:Map<String, Bool> = [];
		final result = new Array<InspectionBuildTimingPhase>();
		for (entry in requiredArray(value, "phases")) {
			final id = requiredString(entry, "id");
			if (!allowed.contains(id)) {
				throw 'Native timing contains unknown phase "$id".';
			}
			if (seen.exists(id)) {
				throw 'Native timing contains duplicate phase "$id".';
			}
			seen.set(id, true);
			result.push({id: id, elapsedMilliseconds: nonNegativeInt(entry, "elapsedMilliseconds"), exitCode: nonNegativeInt(entry, "exitCode")});
		}
		return result;
	}

	static function validateTarget(mode:String, duneLayout:String, target:String):Void {
		if (duneLayout == "library") {
			if (target != "@all") {
				throw 'Library timing must use the Dune target "@all".';
			}
			return;
		}
		final extension = mode == "byte" || mode == "bytecode" ? ".bc" : ".exe";
		if (target == "@all" || !target.endsWith(extension)) {
			throw 'Native timing target "$target" does not match $mode $duneLayout output.';
		}
	}

	static function validateSummary(phases:Array<InspectionBuildTimingPhase>, status:String, exitCode:Int, nativeBuildRan:Bool,
			duneBuildMilliseconds:Null<Int>, interfaceMilliseconds:Int, targetRunMilliseconds:Null<Int>, requestedRun:Bool):Void {
		var measuredDune = 0;
		var measuredNativeBuild = false;
		var measuredInterfaces = 0;
		var measuredRun:Null<Int> = null;
		var failedPhase = false;
		for (phase in phases) {
			if (phase.exitCode != 0) {
				failedPhase = true;
			}
			if (phase.id == "dune_build" || phase.id == "mli_rebuild") {
				measuredNativeBuild = true;
				measuredDune += phase.elapsedMilliseconds;
			} else if (phase.id.indexOf("mli_") == 0) {
				measuredInterfaces += phase.elapsedMilliseconds;
			} else if (phase.id == "dune_exec") {
				measuredRun = phase.elapsedMilliseconds;
			}
		}
		if (nativeBuildRan != measuredNativeBuild || duneBuildMilliseconds != (measuredNativeBuild ? measuredDune : null)) {
			throw "Native timing summary disagrees with its Dune build phase.";
		}
		if (interfaceMilliseconds != measuredInterfaces) {
			throw "Native timing summary disagrees with its interface phases.";
		}
		if (targetRunMilliseconds != measuredRun) {
			throw "Native timing summary disagrees with its Dune execution phase.";
		}
		if ((status == "passed") != (exitCode == 0)) {
			throw "Native timing status and exit code disagree.";
		}
		if (status == "passed" && (failedPhase || !measuredNativeBuild)) {
			throw "A passed native timing report requires a successful Dune build and successful recorded phases.";
		}
		if ((status == "passed" && requestedRun && measuredRun == null) || (!requestedRun && measuredRun != null)) {
			throw "Native timing execution phases disagree with requestedRun and the final status.";
		}
	}

	static function readJson(path:String):BuildTimingJsonResult {
		if (!FileSystem.exists(path)) {
			return Missing;
		}
		if (FileSystem.isDirectory(path)) {
			return Invalid('Expected ${Path.withoutDirectory(path)} to be a file, but found a directory.');
		}
		try {
			return Loaded(Json.parse(File.getContent(path)));
		} catch (error:Dynamic) {
			return Invalid('Could not parse ${Path.withoutDirectory(path)}: ${Std.string(error)}');
		}
	}

	static function requiredObject(value:Dynamic, name:String):Dynamic {
		final result = Reflect.field(value, name);
		if (result == null || !Reflect.isObject(result) || Std.isOfType(result, Array)) {
			throw 'Expected object field "$name".';
		}
		return result;
	}

	static function requiredArray(value:Dynamic, name:String):Array<Dynamic> {
		final result:Dynamic = Reflect.field(value, name);
		if (!Std.isOfType(result, Array)) {
			throw 'Expected array field "$name".';
		}
		return cast result;
	}

	static function requiredStringArray(value:Dynamic, name:String):Array<String> {
		final result = new Array<String>();
		for (entry in requiredArray(value, name)) {
			if (!Std.isOfType(entry, String)) {
				throw 'Expected every "$name" entry to be a string.';
			}
			result.push(cast entry);
		}
		return result;
	}

	static function requiredString(value:Dynamic, name:String):String {
		final result:Dynamic = Reflect.field(value, name);
		if (!Std.isOfType(result, String)) {
			throw 'Expected string field "$name".';
		}
		return cast result;
	}

	static function optionalString(value:Dynamic, name:String):Null<String> {
		final result:Dynamic = Reflect.field(value, name);
		if (result == null) {
			return null;
		}
		if (!Std.isOfType(result, String)) {
			throw 'Expected optional string field "$name".';
		}
		return cast result;
	}

	static function requiredInt(value:Dynamic, name:String):Int {
		final result:Dynamic = Reflect.field(value, name);
		if (!Std.isOfType(result, Int)) {
			throw 'Expected integer field "$name".';
		}
		return cast result;
	}

	static function nonNegativeInt(value:Dynamic, name:String):Int {
		final result = requiredInt(value, name);
		if (result < 0) {
			throw 'Expected "$name" to be non-negative.';
		}
		return result;
	}

	static function nullableNonNegativeInt(value:Dynamic, name:String):Null<Int> {
		if (!Reflect.hasField(value, name)) {
			throw 'Expected nullable integer field "$name".';
		}
		final result:Dynamic = Reflect.field(value, name);
		if (result == null) {
			return null;
		}
		if (!Std.isOfType(result, Int) || result < 0) {
			throw 'Expected nullable non-negative integer field "$name".';
		}
		return cast result;
	}

	static function requiredBool(value:Dynamic, name:String):Bool {
		final result:Dynamic = Reflect.field(value, name);
		if (!Std.isOfType(result, Bool)) {
			throw 'Expected Boolean field "$name".';
		}
		return cast result;
	}

	static function failure(status:String, path:String, message:String):InspectionBuildTiming {
		return {
			status: status,
			path: path,
			schemaVersion: null,
			generatedFilesReceiptId: null,
			mode: null,
			duneLayout: null,
			target: null,
			strict: null,
			requestedRun: null,
			mliMode: null,
			phases: [],
			buildStatus: null,
			buildExitCode: null,
			nativeBuildRan: null,
			duneBuildMilliseconds: null,
			interfaceMilliseconds: null,
			targetRunMilliseconds: null,
			duneBuildIncludes: [],
			duneCacheHitsMeasured: false,
			loadSeparated: false,
			startupSeparated: false,
			workloadRuntimeSeparated: false,
			message: message
		};
	}
}
