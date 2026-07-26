package reflaxe.ocaml.tooling;

import haxe.Json;
import haxe.crypto.Sha256;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import reflaxe.ocaml.tooling.InspectionReport.InspectionGeneratedFiles;
import reflaxe.ocaml.tooling.InspectionReport.InspectionArtifactManifest;
import reflaxe.ocaml.tooling.InspectionReport.InspectionCall;
import reflaxe.ocaml.tooling.InspectionReport.InspectionCallEvaluationStep;
import reflaxe.ocaml.tooling.InspectionReport.InspectionCallableBoundary;
import reflaxe.ocaml.tooling.InspectionReport.InspectionCallValue;
import reflaxe.ocaml.tooling.InspectionReport.InspectionLoweredPlan;
import reflaxe.ocaml.tooling.InspectionReport.InspectionLowering;
import reflaxe.ocaml.tooling.InspectionReport.InspectionLocalConversion;
import reflaxe.ocaml.tooling.InspectionReport.InspectionRepresentation;
import reflaxe.ocaml.tooling.InspectionReport.InspectionRepresentationDecision;
import reflaxe.ocaml.tooling.InspectionReport.InspectionProfile;
import reflaxe.ocaml.tooling.InspectionReport.InspectionRuntime;
import reflaxe.ocaml.tooling.InspectionReport.InspectionRuntimeReason;
import reflaxe.ocaml.tooling.InspectionReport.InspectionStaticStorageEntry;
import reflaxe.ocaml.tooling.InspectionReport.InspectionUnavailableCapability;
import reflaxe.ocaml.tooling.InspectionReport.InspectionUnsafeOperation;

using StringTools;

private enum InspectionJsonResult {
	Missing;
	Invalid(message:String);
	Loaded(value:Dynamic);
}

/**
	Reads and validates the reports emitted by one completed reflaxe.ocaml build.

	This aggregator is intentionally limited to the current report bundle and
	never scans generated OCaml or Dune text. Future typed manifests should keep
	their schema readers with their semantic owners and contribute typed summaries
	here instead of growing target-code inference in this module.
**/
class ReflaxeOcamlInspection {
	static inline final GENERATED_FILES = "_GeneratedFiles.json";
	static inline final PROFILE_REPORT = "ocaml_profile_report.json";
	static inline final RUNTIME_REPORT = "ocaml_runtime_plan_report.json";
	static inline final LOWERING_REPORT = "ocaml_lowering_report.json";

	/** Inspects one output directory without modifying or rebuilding the project. **/
	public static function inspect(projectRoot:String, outputDirectory:String, requireLowering:Bool):InspectionReport {
		final generated = inspectGenerated(Path.join([outputDirectory, GENERATED_FILES]));
		final artifactManifest = OcamlArtifactManifestInspection.inspect(outputDirectory);
		final buildTiming = OcamlBuildTimingInspection.inspect(Path.join([outputDirectory, OcamlBuildTimingInspection.FILE_NAME]), generated.receiptId);
		final profile = inspectProfile(Path.join([outputDirectory, PROFILE_REPORT]));
		final runtime = inspectRuntime(Path.join([outputDirectory, RUNTIME_REPORT]));
		final lowering = inspectLowering(Path.join([outputDirectory, LOWERING_REPORT]), requireLowering);
		final representation = lowering.representation;
		final consistencyErrors = artifactConsistencyErrors(profile, runtime, artifactManifest);
		var errorCount = 0;
		for (status in [generated.status, profile.status, runtime.status]) {
			if (status != "present") {
				errorCount++;
			}
		}
		if (artifactManifest.status != "present") {
			errorCount++;
		}
		if (lowering.status == "invalid" || (requireLowering && lowering.status != "present")) {
			errorCount++;
		}
		if (buildTiming.status == "invalid") {
			errorCount++;
		}
		errorCount += consistencyErrors.length;

		return {
			schemaVersion: 10,
			projectRoot: projectRoot,
			outputDirectory: outputDirectory,
			generatedFiles: generated,
			artifactManifest: artifactManifest,
			buildTiming: buildTiming,
			profile: profile,
			runtime: runtime,
			lowering: lowering,
			representation: representation,
			consistencyErrors: consistencyErrors,
			unavailable: unavailableCapabilities(lowering),
			summary: {
				valid: errorCount == 0,
				exitCode: errorCount == 0 ? 0 : 1,
				errorCount: errorCount,
				generatedFileCount: generated.files.length,
				artifactEntryCount: artifactManifest.entryCount,
				runtimeModuleCount: runtime.selectedModules.length,
				loweredPlanCount: lowering.plans.length,
				representationDecisionCount: representation.decisions.length,
				localConversionCount: lowering.localConversions.length,
				unsafeOperationCount: lowering.unsafeOperations.length,
				callCount: lowering.calls.length,
				callableBoundaryCount: lowering.callableBoundaries.length,
				staticStorageCount: lowering.staticStorage.length
			}
		};
	}

	/** Renders a concise, beginner-readable view of the owned artifacts. **/
	public static function renderHuman(report:InspectionReport):String {
		final lines = new Array<String>();
		lines.push('reflaxe.ocaml output inspection: ${report.summary.valid ? "VALID" : "INVALID"}');
		lines.push('Project: ${report.projectRoot}');
		lines.push('Output: ${report.outputDirectory}');
		lines.push("");
		lines.push(renderGenerated(report.generatedFiles));
		lines.push(OcamlArtifactManifestInspection.renderHuman(report.artifactManifest));
		lines.push(OcamlBuildTimingInspection.renderHuman(report.buildTiming));
		lines.push(renderProfile(report.profile));
		lines.push(renderRuntime(report.runtime));
		if (report.runtime.status == "present") {
			for (reason in report.runtime.inclusionReasons) {
				lines.push('  - ${reason.module}: ${reason.reasons.join(", ")}');
			}
		}
		lines.push(renderLowering(report.lowering));
		if (report.lowering.status == "present") {
			for (plan in report.lowering.plans) {
				final location = '${plan.sourceFile} bytes ${plan.sourceMin}-${plan.sourceMax}';
				lines.push('  - $location ${plan.nodeKind}: ${plan.semanticTypeId} -> ${plan.carrierTypeId}');
				if (plan.representationReason != null) {
					lines.push('    representation: ${plan.representationReason}');
				}
				lines.push('    schedule: ${plan.schedule.join(" -> ")}');
				if (plan.runtimeRequirementIds.length > 0) {
					lines.push('    runtime requirements: ${plan.runtimeRequirementIds.join(", ")}');
				}
			}
			lines.push('[PASS] Local carrier conversions: ${report.lowering.localConversions.length} occurrence${report.lowering.localConversions.length == 1 ? "" : "s"} sealed before syntax.');
			lines.push('[PARTIAL] Unsafe carrier proof ledger: ${report.lowering.unsafeOperations.length} admitted operation${report.lowering.unsafeOperations.length == 1 ? "" : "s"}; whole-program raw/unsafe coverage remains incomplete.');
			for (operation in report.lowering.unsafeOperations) {
				lines.push('  - ${operation.sourceFile} bytes ${operation.sourceMin}-${operation.sourceMax} ${operation.operation}: ${operation.inputSemanticTypeId}/${operation.inputCarrierTypeId} -> ${operation.outputSemanticTypeId}/${operation.outputCarrierTypeId}');
				lines.push('    proof ${operation.proofId}: ${operation.proofClaim}');
				lines.push('    profiles: ${operation.profileEligibility.join(", ")}; function=${operation.functionId}; body=${operation.bodyRevision}; pipeline=${operation.pipelineRevision}');
			}
			lines.push('[PASS] Typed direct calls: ${report.lowering.calls.length} call occurrence${report.lowering.calls.length == 1 ? "" : "s"} matched against ${report.lowering.callableBoundaries.length} independently sealed callable definition${report.lowering.callableBoundaries.length == 1 ? "" : "s"}.');
			for (call in report.lowering.calls) {
				lines.push('  - ${call.sourceFile} bytes ${call.sourceMin}-${call.sourceMax}: ${call.calleeId}');
				final schedule = call.evaluationSchedule.map(step -> step.argumentIndex == null ? step.kind : '${step.kind}:${step.argumentIndex}');
				final arguments = call.arguments.map(argument ->
					'${argument.inputSemanticTypeId}/${argument.inputCarrierTypeId} -${argument.conversion}-> ${argument.outputSemanticTypeId}/${argument.outputCarrierTypeId}')
					.join(", ");
				lines.push('    schedule: ${schedule.join(" -> ")}; ($arguments) -> ${call.result.outputSemanticTypeId}/${call.result.outputCarrierTypeId}');
			}
			lines.push('[PASS] Mutable static storage: ${report.lowering.staticStorage.length} cell${report.lowering.staticStorage.length == 1 ? "" : "s"} planned before type emission.');
			for (entry in report.lowering.staticStorage) {
				lines.push('  - ${entry.moduleId}.${entry.ownerTypeName}.${entry.fieldName}: ${entry.semanticTypeId} -> ${entry.carrierTypeId} (${entry.declarationSite})');
				if (entry.initializerDependencyKeys.length > 0)
					lines.push('    initializer dependencies: ${entry.initializerDependencyKeys.join(", ")}');
			}
		}
		lines.push(renderRepresentation(report.representation));
		if (report.representation.status == "present") {
			for (decision in report.representation.decisions) {
				lines.push('  - ${decision.semanticTypeId} in ${decision.domain}: ${decision.carrierTypeId}');
				lines.push('    reason: ${decision.reason}');
			}
		}
		if (report.consistencyErrors.length == 0) {
			lines.push("[PASS] Artifact consistency: compile profile and runtime selection agree.");
		} else {
			for (message in report.consistencyErrors) {
				lines.push('[FAIL] Artifact consistency: $message');
			}
		}
		lines.push("");
		lines.push("Incomplete or unavailable (never inferred from generated text):");
		for (capability in report.unavailable) {
			lines.push('  - ${capability.label} [${capability.status}]: ${capability.reason}');
		}
		lines.push("");
		lines.push(report.summary.valid ? 'REFLAXE_OCAML_INSPECT:PASS generated_files=${report.summary.generatedFileCount} artifacts=${report.summary.artifactEntryCount} runtime_modules=${report.summary.runtimeModuleCount} lowered_plans=${report.summary.loweredPlanCount}' : 'REFLAXE_OCAML_INSPECT:FAIL errors=${report.summary.errorCount}');
		return lines.join("\n") + "\n";
	}

	/** Renders the stable JSON schema consumed by CI and editor tooling. **/
	public static function renderJson(report:InspectionReport):String {
		return Json.stringify(report, null, "  ") + "\n";
	}

	static function inspectGenerated(path:String):InspectionGeneratedFiles {
		return switch (readJson(path)) {
			case Missing:
				generatedFailure("missing", path, "Generated-file receipt is missing. Run a successful reflaxe.ocaml build first.");
			case Invalid(message):
				generatedFailure("invalid", path, message);
			case Loaded(value):
				try {
					final version = requiredInt(value, "version");
					if (version != 1) {
						throw 'Unsupported generated-file receipt schema $version; expected 1.';
					}
					final receiptId = requiredInt(value, "id");
					if (receiptId < 0) {
						throw "Generated-file receipt id must be non-negative.";
					}
					final files = requiredStringArray(value, "filesGenerated");
					files.sort(compareStrings);
					validateGeneratedFiles(path, files);
					{
						status: "present",
						path: path,
						schemaVersion: version,
						receiptId: receiptId,
						files: files,
						wasCached: requiredBool(value, "wasCached"),
						message: 'Reflaxe recorded ${files.length} generated OCaml source file${files.length == 1 ? "" : "s"}.'
					};
				} catch (error:Dynamic) {
					generatedFailure("invalid", path, Std.string(error));
				}
		};
	}

	static function inspectProfile(path:String):InspectionProfile {
		return switch (readJson(path)) {
			case Missing:
				profileFailure("missing", path, "Compile profile report is missing. Run a successful reflaxe.ocaml build first.");
			case Invalid(message):
				profileFailure("invalid", path, message);
			case Loaded(value):
				try {
					final version = requiredInt(value, "schemaVersion");
					if (version != 2) {
						throw 'Unsupported profile report schema $version; expected 2.';
					}
					final verifier = requiredObject(value, "verifier");
					{
						status: "present",
						path: path,
						schemaVersion: version,
						profile: requiredString(value, "normalizedProfile"),
						atomicSemantics: requiredString(value, "atomicSemantics"),
						runtimeMode: requiredString(value, "runtimeMode"),
						strictUserBoundaries: requiredBool(value, "strictUserBoundaries"),
						verifierResult: requiredString(verifier, "result"),
						violationCount: requiredInt(verifier, "violationCount"),
						message: "Compiler-owned profile report is valid."
					};
				} catch (error:Dynamic) {
					profileFailure("invalid", path, Std.string(error));
				}
		};
	}

	static function inspectRuntime(path:String):InspectionRuntime {
		return switch (readJson(path)) {
			case Missing:
				runtimeFailure("missing", path, "Runtime selection report is missing. Run a successful reflaxe.ocaml build first.");
			case Invalid(message):
				runtimeFailure("invalid", path, message);
			case Loaded(value):
				try {
					final version = requiredInt(value, "schemaVersion");
					if (version != 2) {
						throw 'Unsupported runtime report schema $version; expected 2.';
					}
					final modules = requiredStringArray(value, "selectedModules");
					modules.sort(compareStrings);
					final reasons = runtimeReasons(value);
					validateRuntimeSelection(path, modules, reasons);
					{
						status: "present",
						path: path,
						schemaVersion: version,
						profile: requiredString(value, "profile"),
						runtimeMode: requiredString(value, "runtimeMode"),
						selectionMode: requiredString(value, "selectionMode"),
						selectedModules: modules,
						inclusionReasons: reasons,
						tokenScanFallbackEnabled: requiredBool(value, "tokenScanFallbackEnabled"),
						authority: "current-compiler-runtime-selection-report",
						semanticManifest: false,
						message: "Current compiler/runtime selection report; the separate requirement report explains core packaging, the generated type registry, declared static native boundaries, and typed assignments/updates, but not the whole program."
					};
				} catch (error:Dynamic) {
					runtimeFailure("invalid", path, Std.string(error));
				}
		};
	}

	static function inspectLowering(path:String, required:Bool):InspectionLowering {
		return switch (readJson(path)) {
			case Missing:
				{
					status: "not-enabled",
					required: required,
					path: path,
					schemaVersion: null,
					model: null,
					admittedInputRevision: null,
					plans: [],
					representation: representationFailure("not-enabled", path,
						"The representation registry is reported with typed lowering. Add -D ocaml_lowering_report and rebuild."),
					localConversionRevision: null,
					localConversions: [],
					unsafeOperationCompleteness: null,
					unsafeOperationRevision: null,
					unsafeOperations: [],
					callRevision: null,
					calls: [],
					callableBoundaries: [],
					staticStorageRevision: null,
					staticStorage: [],
					scope: "typed-place-and-first-direct-call-families",
					message: "Typed place lowering was not requested. Add -D ocaml_lowering_report to the project HXML and rebuild."
				};
			case Invalid(message):
				loweringFailure(path, message, required);
			case Loaded(value):
				try {
					final version = requiredInt(value, "schemaVersion");
					if (version != 16) {
						throw 'Unsupported lowering report schema $version; expected 16.';
					}
					final model = requiredString(value, "model");
					if (model != "typed-ocaml-lowered-place") {
						throw 'Unsupported lowering report model "$model".';
					}
					final rawPlans = requiredArray(value, "plans");
					final expectedCount = requiredInt(value, "planCount");
					if (rawPlans.length != expectedCount) {
						throw 'Lowering report planCount is $expectedCount but plans contains ${rawPlans.length} entries.';
					}
					final plans = [for (plan in rawPlans) loweredPlan(plan)];
					plans.sort((left, right) -> compareStrings(left.id, right.id));
					final representation = inspectRepresentations(value, path, version, plans);
					final localConversions = inspectLocalConversions(value);
					final unsafeOperations = inspectUnsafeOperations(value, localConversions);
					final callInventory = inspectCalls(value, representation);
					final staticStorage = inspectStaticStorage(value, representation);
					final runtimeRequirementCount = validateLoweredRuntimeRequirements(value, plans);
					{
						status: "present",
						required: required,
						path: path,
						schemaVersion: version,
						model: model,
						admittedInputRevision: requiredSha256Revision(value, "admittedInputRevision"),
						plans: plans,
						representation: representation,
						localConversionRevision: requiredSha256Revision(value, "localConversionRevision"),
						localConversions: localConversions,
						unsafeOperationCompleteness: requiredString(value, "unsafeOperationCompleteness"),
						unsafeOperationRevision: requiredSha256Revision(value, "unsafeOperationRevision"),
						unsafeOperations: unsafeOperations,
						callRevision: requiredSha256Revision(value, "callRevision"),
						calls: callInventory.calls,
						callableBoundaries: callInventory.boundaries,
						staticStorageRevision: requiredSha256Revision(value, "staticStorageRevision"),
						staticStorage: staticStorage,
						scope: "typed-place-and-first-direct-call-families",
						message: 'Typed lowering report contains ${plans.length} sealed place operation${plans.length == 1 ? "" : "s"}, ${localConversions.length} occurrence-bound local conversion${localConversions.length == 1 ? "" : "s"}, ${unsafeOperations.length} proof-backed unsafe operation${unsafeOperations.length == 1 ? "" : "s"}, ${callInventory.calls.length} typed direct call${callInventory.calls.length == 1 ? "" : "s"}, ${staticStorage.length} pre-emission static cell${staticStorage.length == 1 ? "" : "s"}, and $runtimeRequirementCount runtime explanation${runtimeRequirementCount == 1 ? "" : "s"}; it is not a whole-program IR.'
					};
				} catch (error:Dynamic) {
					loweringFailure(path, Std.string(error), required);
				}
		};
	}

	static function inspectCalls(value:Dynamic,
			representation:InspectionRepresentation):{calls:Array<InspectionCall>, boundaries:Array<InspectionCallableBoundary>} {
		if (requiredString(value, "callModel") != "typed-ocaml-directional-call-boundary-v3")
			throw "Unsupported call-boundary report model.";
		final rawCalls = requiredArray(value, "calls");
		final rawBoundaries = requiredArray(value, "callableBoundaries");
		if (rawCalls.length != requiredInt(value, "callCount"))
			throw "Call count does not match its inventory.";
		if (rawBoundaries.length != requiredInt(value, "callableBoundaryCount"))
			throw "Callable-boundary count does not match its inventory.";

		final representationById:Map<String, InspectionRepresentationDecision> = [];
		for (decision in representation.decisions)
			representationById.set(decision.id, decision);
		final boundaries = [for (entry in rawBoundaries) callableBoundary(entry)];
		final boundaryByCallee:Map<String, InspectionCallableBoundary> = [];
		final boundaryIds:Map<String, Bool> = [];
		for (boundary in boundaries) {
			if (boundaryIds.exists(boundary.id))
				throw 'Callable-boundary report contains duplicate identity "${boundary.id}".';
			if (boundaryByCallee.exists(boundary.calleeId))
				throw 'Callable-boundary report contains duplicate callee "${boundary.calleeId}".';
			for (index in 0...boundary.arguments.length)
				validateCallValue(boundary.arguments[index], representationById, 'Callable boundary "${boundary.id}" argument $index');
			validateCallValue(boundary.result, representationById, 'Callable boundary "${boundary.id}" result');
			validateCallFamily(boundary.arguments, boundary.result, boundary.proofId, true, 'Callable boundary "${boundary.id}"');
			boundaryIds.set(boundary.id, true);
			boundaryByCallee.set(boundary.calleeId, boundary);
		}
		final calls = [for (entry in rawCalls) callDecision(entry)];
		final callIds:Map<String, Bool> = [];
		for (call in calls) {
			if (callIds.exists(call.id))
				throw 'Call report contains duplicate identity "${call.id}".';
			if (call.sourceMin < 0 || call.sourceMax < call.sourceMin)
				throw 'Call "${call.id}" has an invalid source span.';
			for (index in 0...call.arguments.length)
				validateCallValue(call.arguments[index], representationById, 'Call "${call.id}" argument $index');
			validateCallValue(call.result, representationById, 'Call "${call.id}" result');
			validateCallFamily(call.arguments, call.result, call.proofId, false, 'Call "${call.id}"');
			final boundary = boundaryByCallee.get(call.calleeId);
			if (boundary == null)
				throw 'Call "${call.id}" refers to missing callable boundary "${call.calleeId}".';
			if (boundary.kind != call.kind
				|| boundary.sourceModuleId != call.sourceModuleId
				|| boundary.sourceTypeName != call.sourceTypeName
				|| boundary.sourceFieldName != call.sourceFieldName
				|| boundary.arguments.length != call.arguments.length
				|| !sameCallableBoundary(call.result, boundary.result, true)) {
				throw 'Call "${call.id}" disagrees with callable boundary "${boundary.id}".';
			}
			for (index in 0...call.arguments.length) {
				if (!sameCallableBoundary(call.arguments[index], boundary.arguments[index], false))
					throw 'Call "${call.id}" argument $index disagrees with callable boundary "${boundary.id}".';
			}
			callIds.set(call.id, true);
		}
		calls.sort((left, right) -> compareStrings(left.id, right.id));
		boundaries.sort((left, right) -> compareStrings(left.calleeId, right.calleeId));
		return {calls: calls, boundaries: boundaries};
	}

	static function callValue(value:Dynamic):InspectionCallValue {
		final conversion = requiredString(value, "conversion");
		if (conversion != "identity" && conversion != "preserve-nullable-int-carrier" && conversion != "box-exact-int-to-nullable-int")
			throw 'Unsupported typed-call carrier conversion "$conversion".';
		return {
			index: requiredInt(value, "index"),
			inputSemanticTypeId: requiredString(value, "inputSemanticTypeId"),
			inputCarrierTypeId: requiredString(value, "inputCarrierTypeId"),
			inputRepresentationId: requiredString(value, "inputRepresentationId"),
			outputSemanticTypeId: requiredString(value, "outputSemanticTypeId"),
			outputCarrierTypeId: requiredString(value, "outputCarrierTypeId"),
			outputRepresentationId: requiredString(value, "outputRepresentationId"),
			conversion: conversion,
			proofId: requiredString(value, "proofId"),
			proofClaim: requiredString(value, "proofClaim")
		};
	}

	static function callValues(value:Dynamic, field:String):Array<InspectionCallValue> {
		final values = [for (entry in requiredArray(value, field)) callValue(entry)];
		if (values.length < 1 || values.length > 2)
			throw 'Typed-call field "$field" has ${values.length} values outside the admitted arities 1 and 2.';
		for (index in 0...values.length) {
			if (values[index].index != index)
				throw 'Typed-call field "$field" has value index ${values[index].index} at position $index.';
		}
		return values;
	}

	static function callResult(value:Dynamic):InspectionCallValue {
		final result = callValue(requiredObject(value, "result"));
		if (result.index != -1)
			throw 'Typed-call result has index ${result.index} instead of -1.';
		return result;
	}

	static function requireDirectCallKind(value:Dynamic):String {
		final kind = requiredString(value, "kind");
		if (kind != "direct-static-haxe-method")
			throw 'Unsupported typed-call kind "$kind".';
		return kind;
	}

	static function callDecision(value:Dynamic):InspectionCall {
		final source = requiredObject(value, "source");
		final id = requiredString(value, "id");
		final arguments = callValues(value, "arguments");
		final schedule = callEvaluationSchedule(value, id, arguments.length);
		return {
			id: id,
			sourceFile: requiredString(source, "file"),
			sourceMin: requiredInt(source, "min"),
			sourceMax: requiredInt(source, "max"),
			calleeId: requiredString(value, "calleeId"),
			sourceModuleId: requiredString(value, "sourceModuleId"),
			sourceTypeName: requiredString(value, "sourceTypeName"),
			sourceFieldName: requiredString(value, "sourceFieldName"),
			kind: requireDirectCallKind(value),
			arguments: arguments,
			result: callResult(value),
			evaluationSchedule: schedule,
			profileEligibility: requiredStringArray(value, "profileEligibility"),
			reason: requiredString(value, "reason"),
			proofId: requiredString(value, "proofId"),
			proofClaim: requiredString(value, "proofClaim"),
			functionId: requiredString(value, "functionId"),
			programRevision: requiredString(value, "programRevision"),
			bodyRevision: requiredString(value, "bodyRevision"),
			pipelineRevision: requiredString(value, "pipelineRevision")
		};
	}

	static function callEvaluationSchedule(value:Dynamic, callId:String, argumentCount:Int):Array<InspectionCallEvaluationStep> {
		final schedule = [
			for (entry in requiredArray(value, "evaluationSchedule"))
				{
					kind: requiredString(entry, "kind"),
					argumentIndex: optionalInt(entry, "argumentIndex"),
					slotId: optionalString(entry, "slotId")
				}
		];
		if (schedule.length != argumentCount + 1)
			throw 'Call "$callId" has an unsupported evaluation-schedule length.';
		for (index in 0...argumentCount) {
			final step = schedule[index];
			final expectedSlot = "call-argument-slot:" + Sha256.encode(callId + "|" + index).substr(0, 24);
			if (step.kind != "materialize-argument" || step.argumentIndex != index || step.slotId != expectedSlot)
				throw 'Call "$callId" has an invalid materialization at schedule index $index.';
		}
		final invocation = schedule[schedule.length - 1];
		if (invocation.kind != "invoke-callee" || invocation.argumentIndex != null || invocation.slotId != null)
			throw 'Call "$callId" has an invalid invocation step.';
		return schedule;
	}

	static function callableBoundary(value:Dynamic):InspectionCallableBoundary {
		return {
			id: requiredString(value, "id"),
			calleeId: requiredString(value, "calleeId"),
			sourceModuleId: requiredString(value, "sourceModuleId"),
			sourceTypeName: requiredString(value, "sourceTypeName"),
			sourceFieldName: requiredString(value, "sourceFieldName"),
			kind: requireDirectCallKind(value),
			arguments: callValues(value, "arguments"),
			result: callResult(value),
			profileEligibility: requiredStringArray(value, "profileEligibility"),
			reason: requiredString(value, "reason"),
			proofId: requiredString(value, "proofId"),
			proofClaim: requiredString(value, "proofClaim"),
			functionId: requiredString(value, "functionId"),
			programRevision: requiredString(value, "programRevision"),
			bodyRevision: requiredString(value, "bodyRevision"),
			pipelineRevision: requiredString(value, "pipelineRevision")
		};
	}

	static function validateCallValue(value:InspectionCallValue, representations:Map<String, InspectionRepresentationDecision>, owner:String):Void {
		validateCallValueSide(value.inputRepresentationId, value.inputSemanticTypeId, value.inputCarrierTypeId, representations, owner + " input");
		validateCallValueSide(value.outputRepresentationId, value.outputSemanticTypeId, value.outputCarrierTypeId, representations, owner + " output");
		final sameSides = value.inputSemanticTypeId == value.outputSemanticTypeId
			&& value.inputCarrierTypeId == value.outputCarrierTypeId
			&& value.inputRepresentationId == value.outputRepresentationId;
		switch (value.conversion) {
			case "identity":
				if (!sameSides || value.proofId != "identity-call-carrier-v1")
					throw '$owner has an invalid identity crossing.';
			case "preserve-nullable-int-carrier":
				if (!sameSides
					|| value.inputSemanticTypeId != "Null<Int>"
					|| value.inputCarrierTypeId != "Obj.t"
					|| value.proofId != "nullable-int-call-carrier-preserve-v1")
					throw '$owner has an invalid exact Null<Int> carrier-preserving crossing.';
			case "box-exact-int-to-nullable-int":
				if (value.inputSemanticTypeId != "Int"
					|| value.inputCarrierTypeId != "int"
					|| value.outputSemanticTypeId != "Null<Int>"
					|| value.outputCarrierTypeId != "Obj.t"
					|| value.proofId != "nullable-int-call-box-v1")
					throw '$owner has an invalid exact Int-to-Null<Int> boxing crossing.';
			case _:
				throw '$owner has unsupported conversion "${value.conversion}".';
		}
	}

	static function validateCallFamily(arguments:Array<InspectionCallValue>, result:InspectionCallValue, proofId:String, requiresIdentityBoundary:Bool,
			owner:String):Void {
		final exactIntFamily = Lambda.foreach(arguments,
			value -> value.conversion == "identity"
				&& isCallValueSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId, "Int", "int")
				&& isCallValueSide(value.outputSemanticTypeId, value.outputCarrierTypeId, value.outputRepresentationId, "Int", "int"))
			&& result.conversion == "identity"
			&& isCallValueSide(result.inputSemanticTypeId, result.inputCarrierTypeId, result.inputRepresentationId, "Int", "int")
			&& isCallValueSide(result.outputSemanticTypeId, result.outputCarrierTypeId, result.outputRepresentationId, "Int", "int");
		if (exactIntFamily) {
			final expectedProofId = arguments.length == 1 ? "direct-one-int-static-call-v1" : "direct-two-int-static-call-v1";
			if (proofId != expectedProofId)
				throw '$owner has proof "$proofId" instead of "$expectedProofId".';
			return;
		}

		final nullableIntFamily = arguments.length == 1
			&& isCallValueSide(arguments[0].outputSemanticTypeId, arguments[0].outputCarrierTypeId, arguments[0].outputRepresentationId, "Null<Int>", "Obj.t")
			&& result.conversion == "identity"
			&& isCallValueSide(result.inputSemanticTypeId, result.inputCarrierTypeId, result.inputRepresentationId, "Null<Int>", "Obj.t")
			&& isCallValueSide(result.outputSemanticTypeId, result.outputCarrierTypeId, result.outputRepresentationId, "Null<Int>", "Obj.t");
		if (!nullableIntFamily || proofId != "direct-one-nullable-int-static-call-v1")
			throw '$owner does not match an admitted exact Int or Null<Int> direct-call family.';
		if (requiresIdentityBoundary) {
			if (arguments[0].conversion != "identity")
				throw '$owner must describe an identity carrier value.';
		} else if (arguments[0].conversion != "preserve-nullable-int-carrier"
			&& arguments[0].conversion != "box-exact-int-to-nullable-int") {
			throw '$owner must explicitly preserve an existing Null<Int> carrier or box one exact Int.';
		}
	}

	static function isCallValueSide(semanticTypeId:String, carrierTypeId:String, representationId:String, expectedSemanticTypeId:String,
			expectedCarrierTypeId:String):Bool {
		return semanticTypeId == expectedSemanticTypeId
			&& carrierTypeId == expectedCarrierTypeId
			&& representationId == 'representation:$expectedSemanticTypeId:internal-value';
	}

	static function validateCallValueSide(representationId:String, semanticTypeId:String, carrierTypeId:String,
			representations:Map<String, InspectionRepresentationDecision>, owner:String):Void {
		final representation = representations.get(representationId);
		if (representation == null)
			throw '$owner refers to missing representation "$representationId".';
		if (representation.semanticTypeId != semanticTypeId
			|| representation.carrierTypeId != carrierTypeId
			|| representation.domain != "internal-value") {
			throw '$owner expects $semanticTypeId -> $carrierTypeId in internal-value, but representation ${representation.id} selects ${representation.semanticTypeId} -> ${representation.carrierTypeId} in ${representation.domain}.';
		}
	}

	static function sameCallableBoundary(callValue:InspectionCallValue, boundaryValue:InspectionCallValue, isResult:Bool):Bool {
		return callValue.index == boundaryValue.index
			&& (isResult ? (callValue.inputSemanticTypeId == boundaryValue.inputSemanticTypeId
				&& callValue.inputCarrierTypeId == boundaryValue.inputCarrierTypeId
				&& callValue.inputRepresentationId == boundaryValue.inputRepresentationId) : (callValue.outputSemanticTypeId == boundaryValue.outputSemanticTypeId
					&& callValue.outputCarrierTypeId == boundaryValue.outputCarrierTypeId
					&& callValue.outputRepresentationId == boundaryValue.outputRepresentationId));
	}

	static function inspectStaticStorage(value:Dynamic, representation:InspectionRepresentation):Array<InspectionStaticStorageEntry> {
		final model = requiredString(value, "staticStorageModel");
		if (model != "typed-ocaml-static-storage")
			throw 'Unsupported static storage report model "$model".';
		final rawEntries = requiredArray(value, "staticStorage");
		final expectedCount = requiredInt(value, "staticStorageCount");
		if (rawEntries.length != expectedCount)
			throw 'Static storage report staticStorageCount is $expectedCount but staticStorage contains ${rawEntries.length} entries.';
		final representationById:Map<String, InspectionRepresentationDecision> = [];
		for (decision in representation.decisions)
			representationById.set(decision.id, decision);
		final seenIds:Map<String, Bool> = [];
		final seenKeys:Map<String, Bool> = [];
		final entries = [
			for (rawEntry in rawEntries) {
				final entry = staticStorageEntry(rawEntry);
				if (seenIds.exists(entry.id)) throw 'Static storage report contains duplicate identity "${entry.id}".';
				if (seenKeys.exists(entry.key)) throw 'Static storage report contains duplicate key "${entry.key}".';
				seenIds.set(entry.id, true);
				seenKeys.set(entry.key, true);
				if (entry.representationId != null) {
					final decision = representationById.get(entry.representationId);
					if (decision == null)
						throw 'Static storage entry "${entry.id}" refers to missing program representation "${entry.representationId}".';
					if (decision.semanticTypeId != entry.semanticTypeId
						|| decision.carrierTypeId != entry.carrierTypeId
						|| decision.domain != "static-field")
						throw 'Static storage entry "${entry.id}" expects ${entry.semanticTypeId} -> ${entry.carrierTypeId} in static-field, but representation ${decision.id} selects ${decision.semanticTypeId} -> ${decision.carrierTypeId} in ${decision.domain}.';
				}
				entry;
			}
		];
		entries.sort((left, right) -> compareStrings(left.key, right.key));
		return entries;
	}

	static function staticStorageEntry(value:Dynamic):InspectionStaticStorageEntry {
		final declarationSite = requiredString(value, "declarationSite");
		if (declarationSite != "owner-binding" && declarationSite != "module-prelude" && declarationSite != "type-prelude")
			throw 'Unsupported static storage declaration site "$declarationSite".';
		final kind = requiredString(value, "kind");
		if (kind != "variable" && kind != "dynamic-method")
			throw 'Unsupported static storage kind "$kind".';
		return {
			id: requiredString(value, "id"),
			key: requiredString(value, "key"),
			initializationId: requiredString(value, "initializationId"),
			programRevision: requiredString(value, "programRevision"),
			revision: requiredSha256Revision(value, "revision"),
			moduleId: requiredString(value, "moduleId"),
			ownerTypeName: requiredString(value, "ownerTypeName"),
			fieldName: requiredString(value, "fieldName"),
			targetValueName: requiredString(value, "targetValueName"),
			semanticTypeId: requiredString(value, "semanticTypeId"),
			carrierTypeId: requiredString(value, "carrierTypeId"),
			kind: kind,
			declarationSite: declarationSite,
			declarationTypeName: optionalString(value, "declarationTypeName"),
			declarationTypeOrder: requiredInt(value, "declarationTypeOrder"),
			ownerTypeOrder: requiredInt(value, "ownerTypeOrder"),
			declarationOrder: requiredInt(value, "declarationOrder"),
			initializationOrder: requiredInt(value, "initializationOrder"),
			hasInitializer: requiredBool(value, "hasInitializer"),
			initializerDependencyKeys: requiredStringArray(value, "initializerDependencyKeys"),
			representationId: optionalString(value, "representationId")
		};
	}

	static function inspectRepresentations(value:Dynamic, path:String, schemaVersion:Int, plans:Array<InspectionLoweredPlan>):InspectionRepresentation {
		final model = requiredString(value, "representationModel");
		if (model != "typed-ocaml-program-representation")
			throw 'Unsupported representation report model "$model".';
		final scope = requiredString(value, "representationScope");
		if (scope != "exact-int-bool-nullable-field-defaults-direct-simple-assignment-array-int-locals-v9")
			throw 'Unsupported representation report scope "$scope".';
		final rawDecisions = requiredArray(value, "representations");
		final expectedCount = requiredInt(value, "representationCount");
		if (rawDecisions.length != expectedCount)
			throw 'Representation report representationCount is $expectedCount but representations contains ${rawDecisions.length} entries.';
		final decisions = [for (decision in rawDecisions) representationDecision(decision)];
		decisions.sort((left, right) -> compareStrings(left.id, right.id));
		final byId:Map<String, InspectionRepresentationDecision> = [];
		final byKey:Map<String, Bool> = [];
		for (decision in decisions) {
			if (byId.exists(decision.id))
				throw 'Representation report contains duplicate identity "${decision.id}".';
			if (byKey.exists(decision.key))
				throw 'Representation report contains duplicate key "${decision.key}".';
			byId.set(decision.id, decision);
			byKey.set(decision.key, true);
		}
		for (plan in plans) {
			final representationId = plan.representationId;
			if (representationId == null || !byId.exists(representationId))
				throw 'Typed place plan "${plan.id}" refers to missing program representation "$representationId".';
			final decision:InspectionRepresentationDecision = cast byId.get(representationId);
			final expectedDomain = switch (plan.placeKind) {
				case "instance-field": "instance-field";
				case "static-field": "static-field";
				case "array-element": "array-element";
				case other: throw 'Typed place plan "${plan.id}" has unsupported place kind "$other".';
			}
			if (decision.semanticTypeId != plan.semanticTypeId
				|| decision.carrierTypeId != plan.carrierTypeId
				|| decision.domain != expectedDomain) {
				throw 'Typed place plan "${plan.id}" expects ${plan.semanticTypeId} -> ${plan.carrierTypeId} in $expectedDomain, but representation ${decision.id} selects ${decision.semanticTypeId} -> ${decision.carrierTypeId} in ${decision.domain}.';
			}
			final indexRepresentationId = plan.indexRepresentationId;
			if (indexRepresentationId != null) {
				if (!byId.exists(indexRepresentationId))
					throw 'Typed place plan "${plan.id}" refers to missing index representation "$indexRepresentationId".';
				final indexDecision:InspectionRepresentationDecision = cast byId.get(indexRepresentationId);
				if (indexDecision.semanticTypeId != plan.indexSemanticTypeId
					|| indexDecision.carrierTypeId != plan.indexCarrierTypeId
					|| indexDecision.domain != "internal-value") {
					throw 'Typed place plan "${plan.id}" index expects ${plan.indexSemanticTypeId} -> ${plan.indexCarrierTypeId} in internal-value, but representation ${indexDecision.id} selects ${indexDecision.semanticTypeId} -> ${indexDecision.carrierTypeId} in ${indexDecision.domain}.';
				}
			}
			final receiverRepresentationId = plan.receiverRepresentationId;
			if (plan.placeKind == "array-element") {
				if (receiverRepresentationId == null)
					throw 'Typed array place plan "${plan.id}" has no receiver representation.';
				if (!byId.exists(receiverRepresentationId))
					throw 'Typed place plan "${plan.id}" refers to missing receiver representation "$receiverRepresentationId".';
				final receiverDecision:InspectionRepresentationDecision = cast byId.get(receiverRepresentationId);
				if (receiverDecision.semanticTypeId != plan.receiverSemanticTypeId
					|| receiverDecision.carrierTypeId != plan.receiverCarrierTypeId
					|| receiverDecision.domain != "internal-value") {
					throw 'Typed place plan "${plan.id}" receiver expects ${plan.receiverSemanticTypeId} -> ${plan.receiverCarrierTypeId} in internal-value, but representation ${receiverDecision.id} selects ${receiverDecision.semanticTypeId} -> ${receiverDecision.carrierTypeId} in ${receiverDecision.domain}.';
				}
			}
		}
		return {
			status: "present",
			path: path,
			schemaVersion: schemaVersion,
			model: model,
			revision: requiredSha256Revision(value, "representationRevision"),
			decisions: decisions,
			scope: scope,
			message: 'The compiler reported ${decisions.length} program-owned exact-Int, direct Array<Int>, or exact local Bool/Null<Int>/Null<Bool> carrier decision${decisions.length == 1 ? "" : "s"}. Exact-Int instance/static fields also carry their implicit-zero policy; generic, other nullable, abstract, Dynamic, broader field, and ABI domains remain outside this slice.'
		};
	}

	static function inspectLocalConversions(value:Dynamic):Array<InspectionLocalConversion> {
		if (requiredString(value, "localConversionModel") != "typed-ocaml-local-carrier-conversions-v1")
			throw "Unsupported local conversion report model.";
		final raw = requiredArray(value, "localConversions");
		if (raw.length != requiredInt(value, "localConversionCount"))
			throw "Local conversion count does not match its inventory.";
		final seen:Map<String, Bool> = [];
		final conversions = [
			for (entry in raw) {
				final source = requiredObject(entry, "source");
				final unsafe = Reflect.field(entry, "unsafeOperation");
				final result:InspectionLocalConversion = {
					id: requiredString(entry, "id"),
					localId: requiredInt(entry, "localId"),
					role: requiredString(entry, "role"),
					sourceFile: requiredString(source, "file"),
					sourceMin: requiredInt(source, "min"),
					sourceMax: requiredInt(source, "max"),
					inputSemanticTypeId: requiredString(entry, "inputSemanticTypeId"),
					inputCarrierTypeId: requiredString(entry, "inputCarrierTypeId"),
					outputSemanticTypeId: requiredString(entry, "outputSemanticTypeId"),
					outputCarrierTypeId: requiredString(entry, "outputCarrierTypeId"),
					conversion: requiredString(entry, "conversion"),
					reason: requiredString(entry, "reason"),
					proofId: requiredString(entry, "proofId"),
					proofClaim: requiredString(entry, "proofClaim"),
					profileEligibility: requiredStringArray(entry, "profileEligibility"),
					functionId: requiredString(entry, "functionId"),
					programRevision: requiredString(entry, "programRevision"),
					bodyRevision: requiredString(entry, "bodyRevision"),
					pipelineRevision: requiredString(entry, "pipelineRevision"),
					unsafeOperationId: unsafe == null ? null : requiredString(unsafe, "id")
				};
				if (seen.exists(result.id)) throw 'Local conversion report contains duplicate identity "${result.id}".';
				if (result.sourceMin < 0 || result.sourceMax < result.sourceMin) throw 'Local conversion "${result.id}" has an invalid source span.';
				if (result.profileEligibility.length == 0) throw 'Local conversion "${result.id}" has no eligible profile.';
				seen.set(result.id, true);
				result;
			}
		];
		conversions.sort((left, right) -> compareStrings(left.id, right.id));
		return conversions;
	}

	static function inspectUnsafeOperations(value:Dynamic, conversions:Array<InspectionLocalConversion>):Array<InspectionUnsafeOperation> {
		if (requiredString(value, "unsafeOperationModel") != "proof-backed-admitted-unsafe-operations-v1")
			throw "Unsupported unsafe-operation report model.";
		if (requiredString(value, "unsafeOperationCompleteness") != "exact-null-int-and-null-bool-local-slices-only")
			throw "Unsupported unsafe-operation completeness claim.";
		final raw = requiredArray(value, "unsafeOperations");
		if (raw.length != requiredInt(value, "unsafeOperationCount"))
			throw "Unsafe-operation count does not match its inventory.";
		final conversionById:Map<String, InspectionLocalConversion> = [];
		for (conversion in conversions)
			conversionById.set(conversion.id, conversion);
		final seen:Map<String, Bool> = [];
		final operations = [
			for (entry in raw) {
				final source = requiredObject(entry, "source");
				final result:InspectionUnsafeOperation = {
					id: requiredString(entry, "id"),
					conversionId: requiredString(entry, "conversionId"),
					operation: requiredString(entry, "operation"),
					sourceFile: requiredString(source, "file"),
					sourceMin: requiredInt(source, "min"),
					sourceMax: requiredInt(source, "max"),
					inputSemanticTypeId: requiredString(entry, "inputSemanticTypeId"),
					inputCarrierTypeId: requiredString(entry, "inputCarrierTypeId"),
					outputSemanticTypeId: requiredString(entry, "outputSemanticTypeId"),
					outputCarrierTypeId: requiredString(entry, "outputCarrierTypeId"),
					reason: requiredString(entry, "reason"),
					proofId: requiredString(entry, "proofId"),
					proofClaim: requiredString(entry, "proofClaim"),
					profileEligibility: requiredStringArray(entry, "profileEligibility"),
					functionId: requiredString(entry, "functionId"),
					programRevision: requiredString(entry, "programRevision"),
					bodyRevision: requiredString(entry, "bodyRevision"),
					pipelineRevision: requiredString(entry, "pipelineRevision")
				};
				final conversion = conversionById.get(result.conversionId);
				if (conversion == null
					|| conversion.unsafeOperationId != result.id) throw 'Unsafe operation "${result.id}" is not owned by its sealed local conversion.';
				if (seen.exists(result.id)) throw 'Unsafe-operation report contains duplicate identity "${result.id}".';
				if (result.sourceMin < 0 || result.sourceMax < result.sourceMin) throw 'Unsafe operation "${result.id}" has an invalid source span.';
				if (result.profileEligibility.length == 0) throw 'Unsafe operation "${result.id}" has no eligible profile.';
				seen.set(result.id, true);
				result;
			}
		];
		for (conversion in conversions)
			if (conversion.unsafeOperationId != null && !seen.exists(conversion.unsafeOperationId))
				throw 'Local conversion "${conversion.id}" refers to a missing unsafe operation.';
		operations.sort((left, right) -> compareStrings(left.id, right.id));
		return operations;
	}

	static function representationDecision(value:Dynamic):InspectionRepresentationDecision {
		final proof = requiredObject(value, "proof");
		final profiles = requiredStringArray(value, "profileEligibility");
		if (profiles.length == 0)
			throw 'Representation decision "${requiredString(value, "id")}" has no eligible profile.';
		return {
			id: requiredString(value, "id"),
			key: requiredString(value, "key"),
			programRevision: requiredString(value, "programRevision"),
			revision: requiredSha256Revision(value, "revision"),
			semanticTypeId: requiredString(value, "semanticTypeId"),
			domain: requiredString(value, "domain"),
			carrierTypeId: requiredString(value, "carrierTypeId"),
			nullPolicy: requiredString(value, "nullPolicy"),
			identityPolicy: requiredString(value, "identityPolicy"),
			aliasingPolicy: requiredString(value, "aliasingPolicy"),
			storageMutationPolicy: requiredString(value, "storageMutationPolicy"),
			valueMutationPolicy: requiredString(value, "valueMutationPolicy"),
			boxingPolicy: requiredString(value, "boxingPolicy"),
			implicitDefaultPolicy: requiredString(value, "implicitDefaultPolicy"),
			reason: requiredString(value, "reason"),
			proofId: requiredString(proof, "id"),
			proofClaim: requiredString(proof, "claim"),
			profileEligibility: profiles
		};
	}

	static function loweredPlan(value:Dynamic):InspectionLoweredPlan {
		final source = requiredObject(value, "source");
		final place = requiredObject(value, "place");
		final scheduleValues = requiredArray(value, "schedule");
		final schedule = [for (entry in scheduleValues) requiredString(entry, "role")];
		return {
			id: requiredString(value, "id"),
			nodeKind: requiredString(value, "nodeKind"),
			sourceFile: requiredString(source, "file"),
			sourceMin: requiredInt(source, "min"),
			sourceMax: requiredInt(source, "max"),
			sourceOffsetUnit: "byte-offset",
			placeKind: requiredString(place, "kind"),
			semanticTypeId: requiredString(value, "semanticTypeId"),
			carrierTypeId: requiredString(value, "carrierTypeId"),
			representationId: requiredString(place, "representationId"),
			representationReason: requiredString(place, "representationReason"),
			receiverSemanticTypeId: optionalString(place, "receiverSemanticTypeId"),
			receiverCarrierTypeId: optionalString(place, "receiverCarrierTypeId"),
			receiverRepresentationId: optionalString(place, "receiverRepresentationId"),
			indexSemanticTypeId: optionalString(place, "indexSemanticTypeId"),
			indexCarrierTypeId: optionalString(place, "indexCarrierTypeId"),
			indexRepresentationId: optionalString(place, "indexRepresentationId"),
			sourceOperator: optionalString(value, "sourceOperator"),
			fixity: optionalString(value, "fixity"),
			conversion: optionalString(value, "conversion"),
			result: optionalString(value, "result"),
			effects: requiredStringArray(value, "effects"),
			schedule: schedule,
			runtimeRequirementIds: requiredStringArray(value, "runtimeRequirementIds")
		};
	}

	static function validateLoweredRuntimeRequirements(value:Dynamic, plans:Array<InspectionLoweredPlan>):Int {
		requiredSha256Revision(value, "runtimeRequirementRevision");
		final requirementValues = requiredArray(value, "runtimeRequirements");
		final expectedCount = requiredInt(value, "runtimeRequirementCount");
		if (requirementValues.length != expectedCount) {
			throw 'Lowering report runtimeRequirementCount is $expectedCount but runtimeRequirements contains ${requirementValues.length} entries.';
		}
		final requirements:Map<String, Bool> = [];
		for (requirement in requirementValues) {
			final id = requiredString(requirement, "id");
			if (requirements.exists(id))
				throw 'Lowering report contains duplicate runtime requirement "$id".';
			requirements.set(id, true);
			requiredString(requirement, "sourceKind");
			requiredString(requirement, "sourceId");
			final source = requiredObject(requirement, "source");
			requiredString(source, "file");
			final sourceMin = requiredInt(source, "min");
			final sourceMax = requiredInt(source, "max");
			if (sourceMin < 0 || sourceMax < sourceMin)
				throw 'Lowering report runtime requirement "$id" has an invalid source span.';
			requiredString(requirement, "semanticCapability");
			requiredString(requirement, "cause");
			requiredString(requirement, "decisionId");
			final subject = requiredObject(requirement, "subject");
			requiredString(subject, "kind");
			requiredString(subject, "id");
			requiredString(requirement, "implementationFeature");
			requiredString(requirement, "explanation");
			final roots = requiredStringArray(requirement, "rootModules");
			if (roots.length == 0)
				throw 'Lowering report runtime requirement "$id" has no implementation root.';
			for (root in roots)
				if (!~/^[A-Za-z][A-Za-z0-9_]*$/.match(root))
					throw 'Lowering report runtime requirement "$id" has invalid root module "$root".';
			if (requiredStringArray(requirement, "profileEligibility").length == 0)
				throw 'Lowering report runtime requirement "$id" has no eligible profile.';
		}
		final referenced:Map<String, Bool> = [];
		for (plan in plans) {
			for (requirementId in plan.runtimeRequirementIds) {
				if (!requirements.exists(requirementId))
					throw 'Lowered plan "${plan.id}" refers to missing runtime requirement "$requirementId".';
				referenced.set(requirementId, true);
			}
		}
		for (requirementId in requirements.keys())
			if (!referenced.exists(requirementId))
				throw 'Lowering report contains unreferenced runtime requirement "$requirementId".';
		return expectedCount;
	}

	static function runtimeReasons(value:Dynamic):Array<InspectionRuntimeReason> {
		final result = new Array<InspectionRuntimeReason>();
		for (entry in requiredArray(value, "inclusionReasons")) {
			final reasons = requiredStringArray(entry, "reasons");
			reasons.sort(compareStrings);
			result.push({module: requiredString(entry, "module"), reasons: reasons});
		}
		result.sort((left, right) -> compareStrings(left.module, right.module));
		return result;
	}

	static function artifactConsistencyErrors(profile:InspectionProfile, runtime:InspectionRuntime, artifactManifest:InspectionArtifactManifest):Array<String> {
		final errors = new Array<String>();
		if (profile.status != "present" || runtime.status != "present") {
			return errors;
		}
		if (profile.profile != runtime.profile) {
			errors.push('Profile report says "${profile.profile}" while runtime selection says "${runtime.profile}". Rebuild from a clean output directory.');
		}
		if (profile.runtimeMode != runtime.runtimeMode) {
			errors.push('Profile report says runtime mode "${profile.runtimeMode}" while runtime selection says "${runtime.runtimeMode}". Rebuild from a clean output directory.');
		}
		if (artifactManifest.status == "present" && artifactManifest.profile != profile.profile) {
			errors.push('Artifact manifest says profile "${artifactManifest.profile}" while the compile profile says "${profile.profile}". Rebuild from a clean output directory.');
		}
		return errors;
	}

	static function validateGeneratedFiles(receiptPath:String, files:Array<String>):Void {
		final seen:Map<String, Bool> = [];
		final outputDirectory = Path.directory(receiptPath);
		for (file in files) {
			final normalized = file.replace("\\", "/");
			final parts = normalized.split("/");
			if (normalized.length == 0 || Path.isAbsolute(normalized) || ~/^[A-Za-z]:\//.match(normalized) || parts.contains("") || parts.contains(".")
				|| parts.contains("..")) {
				throw 'Generated-file receipt contains an unsafe relative path: "$file".';
			}
			if (seen.exists(normalized)) {
				throw 'Generated-file receipt contains duplicate path "$file".';
			}
			seen.set(normalized, true);
			final actual = Path.join([outputDirectory, normalized]);
			if (!FileSystem.exists(actual) || FileSystem.isDirectory(actual)) {
				throw 'Generated-file receipt names a missing file: "$file".';
			}
		}
	}

	static function validateRuntimeSelection(reportPath:String, modules:Array<String>, reasons:Array<InspectionRuntimeReason>):Void {
		final selected:Map<String, Bool> = [];
		for (moduleName in modules) {
			if (!~/^[A-Za-z_][A-Za-z0-9_]*$/.match(moduleName)) {
				throw 'Runtime selection contains an unsafe module name "$moduleName".';
			}
			if (selected.exists(moduleName)) {
				throw 'Runtime selection contains duplicate module "$moduleName".';
			}
			selected.set(moduleName, true);
			final runtimeRoot = Path.join([Path.directory(reportPath), "runtime"]);
			final implementation = Path.join([runtimeRoot, moduleName + ".ml"]);
			final signature = Path.join([runtimeRoot, moduleName + ".mli"]);
			if ((!FileSystem.exists(implementation) || FileSystem.isDirectory(implementation))
				&& (!FileSystem.exists(signature) || FileSystem.isDirectory(signature))) {
				throw 'Runtime selection names module "$moduleName", but no copied .ml or .mli file exists.';
			}
		}
		final explained:Map<String, Bool> = [];
		for (reason in reasons) {
			if (!selected.exists(reason.module)) {
				throw 'Runtime inclusion reasons contain unselected module "${reason.module}".';
			}
			if (explained.exists(reason.module)) {
				throw 'Runtime inclusion reasons contain duplicate module "${reason.module}".';
			}
			if (reason.reasons.length == 0) {
				throw 'Runtime module "${reason.module}" has no inclusion reason.';
			}
			explained.set(reason.module, true);
		}
		for (moduleName in modules) {
			if (!explained.exists(moduleName)) {
				throw 'Runtime module "$moduleName" has no inclusion-reason entry.';
			}
		}
	}

	static function unavailableCapabilities(lowering:InspectionLowering):Array<InspectionUnavailableCapability> {
		return [
			unavailable("semantic-runtime-manifest", "Whole-program runtime requirement ledger",
				"A checked partial report now covers core packaging, the generated type registry, declared static native boundaries, and typed assignments/updates; other compiler paths still need explicit explanations."),
			unavailable("native-dependencies", "Native package and source dependencies", "Structured Dune/opam/native-source ownership has not landed."),
			{
				id: "raw-unsafe",
				label: "Whole-program raw and unsafe operation inventory",
				status: lowering.status == "present" ? "partial" : "unavailable",
				reason: lowering.status == "present" ? 'The compiler reports ${lowering.unsafeOperations.length} proof-backed operation${lowering.unsafeOperations.length == 1 ? "" : "s"} for admitted exact Null<Int> and Null<Bool> locals; other raw, Obj, and Obj.magic uses are not yet inventoried.' : "The lowering report that owns the exact nullable-primitive local slices is not available."
			},
			unavailable("bindings", "Typed imported OCaml bindings", "The typed .mli binding manifest has not landed."),
			unavailable("export-abi", "Curated public OCaml export ABI", "Inferred .mli files are not a stable export contract.")
		];
	}

	static function unavailable(id:String, label:String, reason:String):InspectionUnavailableCapability {
		return {
			id: id,
			label: label,
			status: "unavailable",
			reason: reason
		};
	}

	static function renderGenerated(value:InspectionGeneratedFiles):String {
		return
			value.status == "present" ? '[PASS] Generated OCaml: ${value.files.length} source file${value.files.length == 1 ? "" : "s"} (${value.wasCached == true ? "cached receipt" : "fresh receipt"}).' : '[FAIL] Generated OCaml: ${value.message}';
	}

	static function renderProfile(value:InspectionProfile):String {
		return
			value.status == "present" ? '[PASS] Compile profile: ${value.profile}; runtime=${value.runtimeMode}; atomics=${value.atomicSemantics}; verifier=${value.verifierResult} (${value.violationCount} violations).' : '[FAIL] Compile profile: ${value.message}';
	}

	static function renderRuntime(value:InspectionRuntime):String {
		return
			value.status == "present" ? '[PASS] Runtime selection: ${value.selectionMode}; ${value.selectedModules.length} module${value.selectedModules.length == 1 ? "" : "s"}; explicit requirement coverage is still partial.' : '[FAIL] Runtime selection: ${value.message}';
	}

	static function renderLowering(value:InspectionLowering):String {
		return switch (value.status) {
			case "present":
				'[PASS] Typed place lowering: ${value.plans.length} operation${value.plans.length == 1 ? "" : "s"} (assignment/update family only).';
			case "not-enabled":
				'${value.required ? "[FAIL]" : "[SKIP]"} Typed place lowering: ${value.message}${value.required ? " This report is required by --require-lowering." : ""}';
			case _:
				'[FAIL] Typed place lowering: ${value.message}';
		};
	}

	static function renderRepresentation(value:InspectionRepresentation):String {
		return switch (value.status) {
			case "present":
				'[PASS] Program representation registry: ${value.decisions.length} decision${value.decisions.length == 1 ? "" : "s"} (${value.scope}).';
			case "not-enabled":
				'[SKIP] Program representation registry: ${value.message}';
			case _:
				'[FAIL] Program representation registry: ${value.message}';
		}
	}

	static function readJson(path:String):InspectionJsonResult {
		if (!FileSystem.exists(path) || FileSystem.isDirectory(path)) {
			return Missing;
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

	static function optionalInt(value:Dynamic, name:String):Null<Int> {
		final result:Dynamic = Reflect.field(value, name);
		if (result == null)
			return null;
		if (!Std.isOfType(result, Int))
			throw 'Expected optional integer field "$name".';
		return cast result;
	}

	static function requiredSha256Revision(value:Dynamic, name:String):String {
		final result = requiredString(value, name);
		if (!~/^sha256:[0-9a-f]{64}$/.match(result)) {
			throw 'Expected "$name" to be a sha256: revision.';
		}
		return result;
	}

	static function requiredInt(value:Dynamic, name:String):Int {
		final result:Dynamic = Reflect.field(value, name);
		if (!Std.isOfType(result, Int)) {
			throw 'Expected integer field "$name".';
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

	static function generatedFailure(status:String, path:String, message:String):InspectionGeneratedFiles {
		return {
			status: status,
			path: path,
			schemaVersion: null,
			receiptId: null,
			files: [],
			wasCached: null,
			message: message
		};
	}

	static function profileFailure(status:String, path:String, message:String):InspectionProfile {
		return {
			status: status,
			path: path,
			schemaVersion: null,
			profile: null,
			atomicSemantics: null,
			runtimeMode: null,
			strictUserBoundaries: null,
			verifierResult: null,
			violationCount: null,
			message: message
		};
	}

	static function runtimeFailure(status:String, path:String, message:String):InspectionRuntime {
		return {
			status: status,
			path: path,
			schemaVersion: null,
			profile: null,
			runtimeMode: null,
			selectionMode: null,
			selectedModules: [],
			inclusionReasons: [],
			tokenScanFallbackEnabled: null,
			authority: "current-compiler-runtime-selection-report",
			semanticManifest: false,
			message: message
		};
	}

	static function loweringFailure(path:String, message:String, required:Bool):InspectionLowering {
		return {
			status: "invalid",
			required: required,
			path: path,
			schemaVersion: null,
			model: null,
			admittedInputRevision: null,
			plans: [],
			representation: representationFailure("invalid", path, message),
			localConversionRevision: null,
			localConversions: [],
			unsafeOperationCompleteness: null,
			unsafeOperationRevision: null,
			unsafeOperations: [],
			callRevision: null,
			calls: [],
			callableBoundaries: [],
			staticStorageRevision: null,
			staticStorage: [],
			scope: "typed-place-and-first-direct-call-families",
			message: message
		};
	}

	static function representationFailure(status:String, path:String, message:String):InspectionRepresentation {
		return {
			status: status,
			path: path,
			schemaVersion: null,
			model: null,
			revision: null,
			decisions: [],
			scope: "exact-int-bool-nullable-field-defaults-direct-simple-assignment-array-int-locals-v9",
			message: message
		};
	}

	static function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}
}
