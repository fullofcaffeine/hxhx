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
import reflaxe.ocaml.tooling.InspectionReport.InspectionControl;
import reflaxe.ocaml.tooling.InspectionReport.InspectionControlCatchChain;
import reflaxe.ocaml.tooling.InspectionReport.InspectionControlCatchClause;
import reflaxe.ocaml.tooling.InspectionReport.InspectionControlLoopTarget;
import reflaxe.ocaml.tooling.InspectionReport.InspectionControlPayload;
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
	static inline final DIRECT_STATIC_SIGNATURE_PROOF_ID = "direct-static-representation-signature-v3";
	static inline final DIRECT_INSTANCE_SIGNATURE_PROOF_ID = "direct-instance-receiver-signature-v1";
	static inline final DIRECT_CONSTRUCTOR_SIGNATURE_PROOF_ID = "direct-constructor-nominal-result-v1";
	static inline final FUNCTION_VALUE_SIGNATURE_PROOF_ID_PREFIX = "typed-function-value-signature-matrix-v1:";

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
			schemaVersion: 18,
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
				controlCount: lowering.controls.length,
				controlCatchCount: lowering.controlCatches.length,
				controlTargetCount: lowering.controlTargets.length,
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
			lines.push('[PASS] Typed calls: ${report.lowering.calls.length} call occurrence${report.lowering.calls.length == 1 ? "" : "s"} sealed before syntax; direct-static calls match ${report.lowering.callableBoundaries.length} independently sealed callable definition${report.lowering.callableBoundaries.length == 1 ? "" : "s"}.');
			for (call in report.lowering.calls) {
				lines.push('  - ${call.sourceFile} bytes ${call.sourceMin}-${call.sourceMax}: ${call.calleeId}');
				final schedule = call.evaluationSchedule.map(step -> step.argumentIndex == null ? step.kind : '${step.kind}:${step.argumentIndex}');
				final arguments = call.arguments.map(argument ->
					'${argument.inputSemanticTypeId}/${argument.inputCarrierTypeId} -${argument.conversion}-> ${argument.outputSemanticTypeId}/${argument.outputCarrierTypeId}')
					.join(", ");
				final result = call.result == null ? call.resultKind : '${call.result.outputSemanticTypeId}/${call.result.outputCarrierTypeId}';
				lines.push('    schedule: ${schedule.join(" -> ")}; ($arguments) -> $result');
			}
			lines.push('[PASS] Typed control: ${report.lowering.controls.length} transfer${report.lowering.controls.length == 1 ? "" : "s"} and ${report.lowering.controlTargets.length} lexical loop target${report.lowering.controlTargets.length == 1 ? "" : "s"} sealed before syntax.');
			for (control in report.lowering.controls) {
				lines.push('  - ${control.sourceFile} bytes ${control.sourceMin}-${control.sourceMax}: ${control.kind} -> ${control.targetKind} ${control.targetId}');
				final payload = control.payload;
				if (payload != null)
					lines.push('    payload: ${payload.inputSemanticTypeId}/${payload.inputCarrierTypeId} -${payload.conversion}-> ${payload.signalCarrierTypeId} -> ${payload.outputSemanticTypeId}/${payload.outputCarrierTypeId}');
				if (control.runtimeTags.length > 0)
					lines.push('    runtime tags: ${control.runtimeTags.join(", ")}');
				lines.push('    runtime tag policy: ${control.runtimeTagPolicy}');
				lines.push('    mechanism: ${control.mechanism}; runtime capability: ${control.runtimeCapabilityId}');
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
					controlRevision: null,
					controls: [],
					controlCatchRevision: null,
					controlCatches: [],
					controlTargetRevision: null,
					controlTargets: [],
					staticStorageRevision: null,
					staticStorage: [],
					scope: "typed-place-call-and-function-loop-throw-catch-control-families",
					message: "Typed place lowering was not requested. Add -D ocaml_lowering_report to the project HXML and rebuild."
				};
			case Invalid(message):
				loweringFailure(path, message, required);
			case Loaded(value):
				try {
					final version = requiredInt(value, "schemaVersion");
					if (version != 33) {
						throw 'Unsupported lowering report schema $version; expected 33.';
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
					final controlTargets = inspectControlTargets(value);
					final controls = inspectControls(value, representation, controlTargets);
					final controlCatches = inspectControlCatches(value, representation);
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
						controlRevision: requiredSha256Revision(value, "controlRevision"),
						controls: controls,
						controlCatchRevision: requiredSha256Revision(value, "controlCatchRevision"),
						controlCatches: controlCatches,
						controlTargetRevision: requiredSha256Revision(value, "controlTargetRevision"),
						controlTargets: controlTargets,
						staticStorageRevision: requiredSha256Revision(value, "staticStorageRevision"),
						staticStorage: staticStorage,
						scope: "typed-place-call-and-function-loop-throw-catch-control-families",
						message: 'Typed lowering report contains ${plans.length} sealed place operation${plans.length == 1 ? "" : "s"}, ${localConversions.length} occurrence-bound local conversion${localConversions.length == 1 ? "" : "s"}, ${unsafeOperations.length} proof-backed unsafe operation${unsafeOperations.length == 1 ? "" : "s"}, ${callInventory.calls.length} typed call${callInventory.calls.length == 1 ? "" : "s"}, ${controls.length} function, loop, or Haxe-exception transfer${controls.length == 1 ? "" : "s"}, ${controlCatches.length} exact primitive/Dynamic catch chain${controlCatches.length == 1 ? "" : "s"}, ${controlTargets.length} lexical loop target${controlTargets.length == 1 ? "" : "s"}, ${staticStorage.length} pre-emission static cell${staticStorage.length == 1 ? "" : "s"}, and $runtimeRequirementCount runtime explanation${runtimeRequirementCount == 1 ? "" : "s"}; it is not a whole-program IR.'
					};
				} catch (error:Dynamic) {
					loweringFailure(path, Std.string(error), required);
				}
		};
	}

	static function inspectControlTargets(value:Dynamic):Array<InspectionControlLoopTarget> {
		if (requiredString(value, "controlTargetModel") != "typed-ocaml-lexical-loop-target-v1")
			throw "Unsupported control-target report model.";
		final rawTargets = requiredArray(value, "controlTargets");
		if (rawTargets.length != requiredInt(value, "controlTargetCount"))
			throw "Control-target count does not match its inventory.";
		final targets = [for (entry in rawTargets) controlLoopTarget(entry)];
		final ids:Map<String, Bool> = [];
		for (target in targets) {
			if (ids.exists(target.id))
				throw 'Control-target report contains duplicate identity "${target.id}".';
			if (target.sourceFile.length == 0
				|| target.sourceMin < 0
				|| target.sourceMax < target.sourceMin
				|| (target.kind != "while" && target.kind != "do-while")
				|| target.functionId.length == 0
				|| target.programRevision.length == 0
				|| target.bodyRevision.length == 0
				|| target.pipelineRevision.length == 0
				|| target.proofId != "lexical-loop-control-v1"
				|| target.proofClaim.length == 0) {
				throw 'Control loop target "${target.id}" has incomplete identity, source, proof, or revision metadata.';
			}
			ids.set(target.id, true);
		}
		targets.sort((left, right) -> compareStrings(left.id, right.id));
		return targets;
	}

	static function inspectControls(value:Dynamic, representation:InspectionRepresentation,
			targets:Array<InspectionControlLoopTarget>):Array<InspectionControl> {
		if (requiredString(value, "controlModel") != "typed-ocaml-function-loop-throw-and-catch-control-v9")
			throw "Unsupported control report model.";
		final rawControls = requiredArray(value, "controls");
		if (rawControls.length != requiredInt(value, "controlCount"))
			throw "Control count does not match its inventory.";
		final representationById:Map<String, InspectionRepresentationDecision> = [];
		for (decision in representation.decisions)
			representationById.set(decision.id, decision);
		final targetById:Map<String, InspectionControlLoopTarget> = [];
		for (target in targets)
			targetById.set(target.id, target);
		final controls = [for (entry in rawControls) controlDecision(entry)];
		final ids:Map<String, Bool> = [];
		for (control in controls) {
			if (ids.exists(control.id))
				throw 'Control report contains duplicate identity "${control.id}".';
			if (control.sourceFile.length == 0 || control.sourceMin < 0 || control.sourceMax < control.sourceMin)
				throw 'Control decision "${control.id}" has an invalid source span.';
			final payload = control.payload;
			switch (control.kind) {
				case "return":
					if (control.effect != "exit-function"
						|| control.targetKind != "function"
						|| control.targetId != control.functionId
						|| control.runtimeTags.length != 0
						|| control.runtimeTagPolicy != "no-runtime-tags") {
						throw 'Control decision "${control.id}" has an invalid return target, effect, or tag policy.';
					}
					switch (control.mechanism) {
						case "runtime-void-return-signal":
							if (control.runtimeCapabilityId != "hxhx-runtime:function-void-return-signal-v1"
								|| payload != null
								|| control.proofId != "effect-only-void-early-return-control-v1") {
								throw 'Control decision "${control.id}" has an invalid effect-only Void return contract.';
							}
						case "runtime-return-signal":
							if (control.runtimeCapabilityId != "hxhx-runtime:function-return-signal-v1" || payload == null)
								throw 'Control decision "${control.id}" has an invalid exact-value return capability or payload.';
							validateCallValueSide(payload.inputRepresentationId, payload.inputSemanticTypeId, payload.inputCarrierTypeId, representationById,
								'Control decision "${control.id}" input');
							validateCallValueSide(payload.outputRepresentationId, payload.outputSemanticTypeId, payload.outputCarrierTypeId,
								representationById, 'Control decision "${control.id}" output');
							final admittedExactInput = (payload.inputSemanticTypeId == "Int"
								&& payload.inputCarrierTypeId == "int"
								&& payload.inputRepresentationId == "representation:Int:internal-value")
								|| (payload.inputSemanticTypeId == "Bool"
									&& payload.inputCarrierTypeId == "bool"
									&& payload.inputRepresentationId == "representation:Bool:internal-value")
								|| (payload.inputSemanticTypeId == "String"
									&& payload.inputCarrierTypeId == "string"
									&& payload.inputRepresentationId == "representation:String:internal-value");
							final admittedNullableInput = (payload.inputSemanticTypeId == "Null<Int>"
								&& payload.inputCarrierTypeId == "Obj.t"
								&& payload.inputRepresentationId == "representation:Null<Int>:internal-value")
								|| (payload.inputSemanticTypeId == "Null<Bool>"
									&& payload.inputCarrierTypeId == "Obj.t"
									&& payload.inputRepresentationId == "representation:Null<Bool>:internal-value");
							final commonPayloadValid = payload.signalCarrierTypeId == "Obj.t";
							final sameSides = payload.outputSemanticTypeId == payload.inputSemanticTypeId
								&& payload.outputCarrierTypeId == payload.inputCarrierTypeId
								&& payload.outputRepresentationId == payload.inputRepresentationId;
							final exactPayloadValid = admittedExactInput
								&& sameSides
								&& payload.nominalRepresentation == null
								&& payload.conversion == "box-and-recover-exact-value"
								&& payload.proofId == "exact-value-early-return-control-v2"
								&& control.proofId == "exact-value-early-return-control-v2";
							final nullablePayloadValid = admittedNullableInput
								&& sameSides
								&& payload.nominalRepresentation == null
								&& payload.conversion == "preserve-nullable-carrier"
								&& payload.proofId == "exact-nullable-carrier-early-return-control-v1"
								&& control.proofId == "exact-nullable-carrier-early-return-control-v1";
							final nullableIntConversionValid = payload.inputSemanticTypeId == "Int"
								&& payload.inputCarrierTypeId == "int"
								&& payload.inputRepresentationId == "representation:Int:internal-value"
								&& payload.outputSemanticTypeId == "Null<Int>"
								&& payload.outputCarrierTypeId == "Obj.t"
								&& payload.outputRepresentationId == "representation:Null<Int>:internal-value"
								&& payload.nominalRepresentation == null
								&& payload.conversion == "box-exact-int-to-nullable-carrier"
								&& payload.proofId == "exact-int-to-nullable-early-return-control-v1"
								&& control.proofId == "exact-int-to-nullable-early-return-control-v1";
							final nullableBoolConversionValid = payload.inputSemanticTypeId == "Bool"
								&& payload.inputCarrierTypeId == "bool"
								&& payload.inputRepresentationId == "representation:Bool:internal-value"
								&& payload.outputSemanticTypeId == "Null<Bool>"
								&& payload.outputCarrierTypeId == "Obj.t"
								&& payload.outputRepresentationId == "representation:Null<Bool>:internal-value"
								&& payload.nominalRepresentation == null
								&& payload.conversion == "box-exact-bool-to-nullable-carrier"
								&& payload.proofId == "exact-bool-to-nullable-early-return-control-v1"
								&& control.proofId == "exact-bool-to-nullable-early-return-control-v1";
							final nominalDecision = representationById.get(payload.inputRepresentationId);
							final nominal = payload.nominalRepresentation;
							final nominalPayloadValid = nominalDecision != null
								&& nominal != null
								&& sameSides
								&& nominalDecision.semanticTypeId == payload.inputSemanticTypeId
								&& nominalDecision.carrierTypeId == payload.inputCarrierTypeId
								&& nominalDecision.domain == "internal-value"
								&& nominalDecision.boxingPolicy == "nullable-nominal-record-carrier"
								&& nominalDecision.nominalTargetModuleName == nominal.targetModuleName
								&& nominalDecision.nominalTargetTypeName == nominal.targetTypeName
								&& nominalDecision.nominalLayoutRevision == nominal.layoutRevision
								&& nominalDecision.proofId == nominal.representationProofId
								&& payload.conversion == "box-and-recover-nominal-value"
								&& payload.proofId == "exact-monomorphic-class-early-return-control-v1"
								&& control.proofId == "exact-monomorphic-class-early-return-control-v1";
							if (!commonPayloadValid
								|| payload.proofClaim.length == 0
								|| (!exactPayloadValid && !nominalPayloadValid && !nullablePayloadValid && !nullableIntConversionValid
									&& !nullableBoolConversionValid)) {
								throw 'Control decision "${control.id}" has an invalid exact-value, nominal, nullable-carrier, or primitive-to-nullable payload crossing.';
							}
						case _:
							throw 'Control decision "${control.id}" has unsupported return mechanism "${control.mechanism}".';
					}
				case "break", "continue":
					final isBreak = control.kind == "break";
					final target = targetById.get(control.targetId);
					if (target == null)
						throw 'Control decision "${control.id}" refers to missing loop target "${control.targetId}".';
					if (control.targetKind != "loop"
						|| control.effect != (isBreak ? "exit-loop" : "next-loop-iteration")
						|| control.mechanism != (isBreak ? "runtime-break-signal" : "runtime-continue-signal")
						|| control.runtimeCapabilityId != (isBreak ? "hxhx-runtime:loop-break-signal-v1" : "hxhx-runtime:loop-continue-signal-v1")
						|| payload != null
						|| control.proofId != "lexical-loop-control-v1"
						|| control.runtimeTags.length != 0
						|| control.runtimeTagPolicy != "no-runtime-tags"
						|| target.functionId != control.functionId
						|| target.programRevision != control.programRevision
						|| target.bodyRevision != control.bodyRevision
						|| target.pipelineRevision != control.pipelineRevision) {
						throw 'Control decision "${control.id}" has an invalid loop target, effect, mechanism, capability, payload, or revision.';
					}
				case "throw":
					if (control.effect != "raise-haxe-value"
						|| control.targetKind != "haxe-exception-channel"
						|| control.targetId != "control-target:haxe-exception-channel:v1"
						|| control.mechanism != "runtime-typed-haxe-exception-signal"
						|| control.runtimeCapabilityId != "hxhx-runtime:typed-haxe-exception-signal-v1"
						|| payload == null) {
						throw 'Control decision "${control.id}" has an invalid Haxe exception target, effect, mechanism, capability, or payload.';
					}
					validateCallValueSide(payload.inputRepresentationId, payload.inputSemanticTypeId, payload.inputCarrierTypeId, representationById,
						'Control decision "${control.id}" input');
					validateCallValueSide(payload.outputRepresentationId, payload.outputSemanticTypeId, payload.outputCarrierTypeId, representationById,
						'Control decision "${control.id}" output');
					final expectedConversion = switch (payload.inputSemanticTypeId) {
						case "Int", "String": "repr-and-recover-exact-value";
						case "Bool": "box-bool-and-recover-exact-value";
						case _: null;
					};
					final expectedTags = switch (payload.inputSemanticTypeId) {
						case "Int", "Bool", "String": ["Dynamic"];
						case _: [];
					};
					if (expectedConversion == null
						|| payload.signalCarrierTypeId != "Obj.t"
						|| payload.outputSemanticTypeId != payload.inputSemanticTypeId
						|| payload.outputCarrierTypeId != payload.inputCarrierTypeId
						|| payload.outputRepresentationId != payload.inputRepresentationId
						|| payload.conversion != expectedConversion
						|| payload.proofId != "exact-value-throw-control-v1"
						|| payload.proofClaim.length == 0
						|| control.proofId != "exact-value-throw-control-v1"
						|| !sameStrings(control.runtimeTags, expectedTags)
						|| control.runtimeTagPolicy != "merge-dynamic-with-exact-runtime-value") {
						throw 'Control decision "${control.id}" has an invalid exact-value Haxe exception crossing.';
					}
				case _:
					throw 'Control decision "${control.id}" has unsupported transfer kind "${control.kind}".';
			}
			if (control.proofClaim.length == 0
				|| control.reason.length == 0
				|| control.functionId.length == 0
				|| control.programRevision.length == 0
				|| control.bodyRevision.length == 0
				|| control.pipelineRevision.length == 0
				|| control.profileEligibility.length != 2
				|| control.profileEligibility[0] != "metal"
				|| control.profileEligibility[1] != "portable") {
				throw 'Control decision "${control.id}" has incomplete proof, revision, or profile metadata.';
			}
			ids.set(control.id, true);
		}
		controls.sort((left, right) -> compareStrings(left.id, right.id));
		return controls;
	}

	static function inspectControlCatches(value:Dynamic, representation:InspectionRepresentation):Array<InspectionControlCatchChain> {
		if (requiredString(value, "controlCatchModel") != "typed-ocaml-exact-primitive-catch-chain-v1")
			throw "Unsupported control catch-chain report model.";
		final rawChains = requiredArray(value, "controlCatches");
		if (rawChains.length != requiredInt(value, "controlCatchCount"))
			throw "Control catch-chain count does not match its inventory.";
		final representationById:Map<String, InspectionRepresentationDecision> = [];
		for (decision in representation.decisions)
			representationById.set(decision.id, decision);

		final chains = [for (entry in rawChains) controlCatchChain(entry)];
		final chainIds:Map<String, Bool> = [];
		final clauseIds:Map<String, Bool> = [];
		for (chain in chains) {
			if (chainIds.exists(chain.id))
				throw 'Control catch-chain report contains duplicate identity "${chain.id}".';
			if (chain.sourceFile.length == 0
				|| chain.sourceMin < 0
				|| chain.sourceMax < chain.sourceMin
				|| chain.clauses.length == 0
				|| !isControlCatchBranchResultPolicy(chain.tryBodyResultPolicy)
				|| !sameStrings(chain.inputChannels, ["haxe-exception-signal", "target-native-exception"])
				|| !sameStrings(chain.targetNativeRuntimeTags, ["OcamlExn"])
				|| chain.haxeUnmatchedPolicy != "rethrow-haxe-exception-signal"
				|| chain.targetNativeUnmatchedPolicy != "reraise-target-native-exception"
				|| chain.privateControlPolicy != "propagate-private-control-signals"
				|| chain.runtimeCapabilityId != "hxhx-runtime:typed-haxe-catch-chain-v1"
				|| !sameStrings(chain.profileEligibility, ["metal", "portable"])
				|| chain.reason.length == 0
				|| chain.proofId != "exact-primitive-catch-control-v1"
				|| chain.proofClaim.length == 0
				|| chain.functionId.length == 0
				|| chain.programRevision.length == 0
				|| chain.bodyRevision.length == 0
				|| chain.pipelineRevision.length == 0) {
				throw 'Control catch chain "${chain.id}" has incomplete channels, fallback behavior, proof, profile, or revision metadata.';
			}
			for (index in 0...chain.clauses.length) {
				final clause = chain.clauses[index];
				if (clauseIds.exists(clause.id))
					throw 'Control catch-chain report contains duplicate clause identity "${clause.id}".';
				if (clause.sourceFile.length == 0
					|| clause.sourceMin < 0
					|| clause.sourceMax < clause.sourceMin
					|| clause.order != index
					|| clause.variableName.length == 0
					|| clause.signalCarrierTypeId != "Obj.t"
					|| !isControlCatchBranchResultPolicy(clause.bodyResultPolicy)
					|| !sameStrings(clause.effects, ["select-first-matching-clause", "bind-catch-variable", "execute-catch-body"])
					|| clause.proofId != "exact-primitive-catch-control-v1"
					|| clause.proofClaim.length == 0
					|| clause.functionId != chain.functionId
					|| clause.programRevision != chain.programRevision
					|| clause.bodyRevision != chain.bodyRevision
					|| clause.pipelineRevision != chain.pipelineRevision) {
					throw 'Control catch clause "${clause.id}" has incomplete order, payload, effects, proof, or revision metadata.';
				}
				switch (clause.semanticTypeId) {
					case "Int":
						validateControlCatchExactSide(clause, "int", "representation:Int:internal-value", "Int", "recover-exact-value", representationById);
					case "Bool":
						validateControlCatchExactSide(clause, "bool", "representation:Bool:internal-value", "Bool", "recover-checked-bool", representationById);
					case "String":
						validateControlCatchExactSide(clause, "string", "representation:String:internal-value", "String", "recover-exact-value",
							representationById);
					case "Dynamic":
						if (clause.outputCarrierTypeId != "Obj.t"
							|| clause.outputRepresentationId != "control-representation:Dynamic:runtime-obj-v1"
							|| clause.matchPolicy != "match-all"
							|| clause.runtimeTag != null
							|| clause.conversion != "preserve-dynamic-carrier"
							|| index != chain.clauses.length - 1) {
							throw 'Dynamic control catch clause "${clause.id}" has an invalid match-all, order, or carrier-preserving contract.';
						}
					case _:
						throw 'Control catch clause "${clause.id}" has unsupported semantic type "${clause.semanticTypeId}".';
				}
				clauseIds.set(clause.id, true);
			}
			chainIds.set(chain.id, true);
		}
		chains.sort((left, right) -> compareStrings(left.id, right.id));
		return chains;
	}

	static function isControlCatchBranchResultPolicy(policy:String):Bool {
		return policy == "preserve-typed-result" || policy == "discard-completed-value-to-unit";
	}

	static function validateControlCatchExactSide(clause:InspectionControlCatchClause, carrierTypeId:String, representationId:String, runtimeTag:String,
			conversion:String, representationById:Map<String, InspectionRepresentationDecision>):Void {
		if (clause.outputCarrierTypeId != carrierTypeId
			|| clause.outputRepresentationId != representationId
			|| clause.matchPolicy != "exact-runtime-tag"
			|| clause.runtimeTag != runtimeTag
			|| clause.conversion != conversion) {
			throw 'Exact ${clause.semanticTypeId} control catch clause "${clause.id}" has an invalid tag, carrier, representation, or conversion.';
		}
		validateCallValueSide(clause.outputRepresentationId, clause.semanticTypeId, clause.outputCarrierTypeId, representationById,
			'Control catch clause "${clause.id}" output');
	}

	static function controlCatchChain(value:Dynamic):InspectionControlCatchChain {
		final source = requiredObject(value, "source");
		return {
			id: requiredString(value, "id"),
			sourceFile: requiredString(source, "file"),
			sourceMin: requiredInt(source, "min"),
			sourceMax: requiredInt(source, "max"),
			clauses: [for (entry in requiredArray(value, "clauses")) controlCatchClause(entry)],
			tryBodyResultPolicy: requiredString(value, "tryBodyResultPolicy"),
			inputChannels: requiredStringArray(value, "inputChannels"),
			targetNativeRuntimeTags: requiredStringArray(value, "targetNativeRuntimeTags"),
			haxeUnmatchedPolicy: requiredString(value, "haxeUnmatchedPolicy"),
			targetNativeUnmatchedPolicy: requiredString(value, "targetNativeUnmatchedPolicy"),
			privateControlPolicy: requiredString(value, "privateControlPolicy"),
			runtimeCapabilityId: requiredString(value, "runtimeCapabilityId"),
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

	static function controlCatchClause(value:Dynamic):InspectionControlCatchClause {
		final source = requiredObject(value, "source");
		return {
			id: requiredString(value, "id"),
			sourceFile: requiredString(source, "file"),
			sourceMin: requiredInt(source, "min"),
			sourceMax: requiredInt(source, "max"),
			order: requiredInt(value, "order"),
			variableName: requiredString(value, "variableName"),
			semanticTypeId: requiredString(value, "semanticTypeId"),
			signalCarrierTypeId: requiredString(value, "signalCarrierTypeId"),
			outputCarrierTypeId: requiredString(value, "outputCarrierTypeId"),
			outputRepresentationId: requiredString(value, "outputRepresentationId"),
			matchPolicy: requiredString(value, "matchPolicy"),
			runtimeTag: optionalString(value, "runtimeTag"),
			conversion: requiredString(value, "conversion"),
			bodyResultPolicy: requiredString(value, "bodyResultPolicy"),
			effects: requiredStringArray(value, "effects"),
			proofId: requiredString(value, "proofId"),
			proofClaim: requiredString(value, "proofClaim"),
			functionId: requiredString(value, "functionId"),
			programRevision: requiredString(value, "programRevision"),
			bodyRevision: requiredString(value, "bodyRevision"),
			pipelineRevision: requiredString(value, "pipelineRevision")
		};
	}

	static function controlDecision(value:Dynamic):InspectionControl {
		final source = requiredObject(value, "source");
		return {
			id: requiredString(value, "id"),
			sourceFile: requiredString(source, "file"),
			sourceMin: requiredInt(source, "min"),
			sourceMax: requiredInt(source, "max"),
			kind: requiredString(value, "kind"),
			effect: requiredString(value, "effect"),
			targetKind: requiredString(value, "targetKind"),
			targetId: requiredString(value, "targetId"),
			payload: Reflect.field(value, "payload") == null ? null : controlPayload(requiredObject(value, "payload")),
			runtimeTags: requiredStringArray(value, "runtimeTags"),
			runtimeTagPolicy: requiredString(value, "runtimeTagPolicy"),
			mechanism: requiredString(value, "mechanism"),
			runtimeCapabilityId: requiredString(value, "runtimeCapabilityId"),
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

	static function controlLoopTarget(value:Dynamic):InspectionControlLoopTarget {
		final source = requiredObject(value, "source");
		return {
			id: requiredString(value, "id"),
			sourceFile: requiredString(source, "file"),
			sourceMin: requiredInt(source, "min"),
			sourceMax: requiredInt(source, "max"),
			kind: requiredString(value, "kind"),
			functionId: requiredString(value, "functionId"),
			programRevision: requiredString(value, "programRevision"),
			bodyRevision: requiredString(value, "bodyRevision"),
			pipelineRevision: requiredString(value, "pipelineRevision"),
			proofId: requiredString(value, "proofId"),
			proofClaim: requiredString(value, "proofClaim")
		};
	}

	static function controlPayload(value:Dynamic):InspectionControlPayload {
		final nominalValue = Reflect.field(value, "nominalRepresentation");
		return {
			inputSemanticTypeId: requiredString(value, "inputSemanticTypeId"),
			inputCarrierTypeId: requiredString(value, "inputCarrierTypeId"),
			inputRepresentationId: requiredString(value, "inputRepresentationId"),
			signalCarrierTypeId: requiredString(value, "signalCarrierTypeId"),
			outputSemanticTypeId: requiredString(value, "outputSemanticTypeId"),
			outputCarrierTypeId: requiredString(value, "outputCarrierTypeId"),
			outputRepresentationId: requiredString(value, "outputRepresentationId"),
			conversion: requiredString(value, "conversion"),
			nominalRepresentation: nominalValue == null ? null : {
				targetModuleName: requiredString(nominalValue, "targetModuleName"),
				targetTypeName: requiredString(nominalValue, "targetTypeName"),
				layoutRevision: requiredString(nominalValue, "layoutRevision"),
				representationProofId: requiredString(nominalValue, "representationProofId")
			},
			proofId: requiredString(value, "proofId"),
			proofClaim: requiredString(value, "proofClaim")
		};
	}

	static function inspectCalls(value:Dynamic,
			representation:InspectionRepresentation):{calls:Array<InspectionCall>, boundaries:Array<InspectionCallableBoundary>} {
		if (requiredString(value, "callModel") != "typed-ocaml-directional-call-boundary-v16")
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
			if (boundary.receiver != null)
				validateCallValue(boundary.receiver, representationById, 'Callable boundary "${boundary.id}" receiver');
			for (index in 0...boundary.arguments.length)
				validateCallValue(boundary.arguments[index], representationById, 'Callable boundary "${boundary.id}" argument $index');
			if (boundary.result != null)
				validateCallValue(boundary.result, representationById, 'Callable boundary "${boundary.id}" result');
			validateDeclaredCallIdentity(boundary.kind, boundary.sourceModuleId, boundary.sourceTypeName, boundary.sourceFieldName,
				'Callable boundary "${boundary.id}"');
			validateCallSignature(boundary.kind, boundary.receiver, boundary.arguments, boundary.resultKind, boundary.result, boundary.proofId,
				representationById, true, 'Callable boundary "${boundary.id}"');
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
			if (call.receiver != null)
				validateCallValue(call.receiver, representationById, 'Call "${call.id}" receiver');
			for (index in 0...call.arguments.length)
				validateCallValue(call.arguments[index], representationById, 'Call "${call.id}" argument $index');
			if (call.result != null)
				validateCallValue(call.result, representationById, 'Call "${call.id}" result');
			validateDeclaredCallIdentity(call.kind, call.sourceModuleId, call.sourceTypeName, call.sourceFieldName, 'Call "${call.id}"');
			validateCallSignature(call.kind, call.receiver, call.arguments, call.resultKind, call.result, call.proofId, representationById, false,
				'Call "${call.id}"');
			if (call.kind == "typed-function-value") {
				if (call.sourceModuleId.length != 0 || call.sourceTypeName.length != 0 || call.sourceFieldName.length != 0)
					throw 'Function-value call "${call.id}" must not report a declaration identity.';
				callIds.set(call.id, true);
				continue;
			}
			final boundary = boundaryByCallee.get(call.calleeId);
			if (boundary == null)
				throw 'Call "${call.id}" refers to missing callable boundary "${call.calleeId}".';
			if (boundary.kind != call.kind
				|| boundary.sourceModuleId != call.sourceModuleId
				|| boundary.sourceTypeName != call.sourceTypeName
				|| boundary.sourceFieldName != call.sourceFieldName
				|| boundary.arguments.length != call.arguments.length
				|| !sameCallResult(call.resultKind, call.result, boundary.resultKind, boundary.result)
				|| !sameOptionalBoundary(call.receiver, boundary.receiver)) {
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
		return {
			index: requiredInt(value, "index"),
			parameterOptional: requiredBool(value, "parameterOptional"),
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
		for (index in 0...values.length) {
			if (values[index].index != index)
				throw 'Typed-call field "$field" has value index ${values[index].index} at position $index.';
		}
		return values;
	}

	static function callResultKind(value:Dynamic):String {
		final kind = requiredString(value, "resultKind");
		if (kind != "value" && kind != "effect-only-void")
			throw 'Unsupported typed-call result kind "$kind".';
		return kind;
	}

	static function callResult(value:Dynamic, resultKind:String):Null<InspectionCallValue> {
		if (!Reflect.hasField(value, "result"))
			throw 'Expected typed-call field "result".';
		final rawResult = Reflect.field(value, "result");
		if (resultKind == "effect-only-void") {
			if (rawResult != null)
				throw "Effect-only Void call results cannot carry a value crossing.";
			return null;
		}
		final result = callValue(requiredObject(value, "result"));
		if (result.index != -1)
			throw 'Typed-call result has index ${result.index} instead of -1.';
		if (result.parameterOptional)
			throw "Typed-call result cannot be an optional parameter.";
		return result;
	}

	static function callReceiver(value:Dynamic, kind:String):Null<InspectionCallValue> {
		if (!Reflect.hasField(value, "receiver"))
			throw 'Expected typed-call field "receiver".';
		final rawReceiver = Reflect.field(value, "receiver");
		if (kind != "direct-instance-haxe-method") {
			if (rawReceiver != null)
				throw 'Typed-call kind "$kind" cannot carry an instance receiver.';
			return null;
		}
		final receiver = callValue(requiredObject(value, "receiver"));
		if (receiver.index != -2 || receiver.parameterOptional || receiver.conversion != "identity")
			throw "Direct instance receiver must use index -2 and one required identity crossing.";
		return receiver;
	}

	static function requireCallKind(value:Dynamic):String {
		final kind = requiredString(value, "kind");
		if (kind != "direct-static-haxe-method"
			&& kind != "direct-instance-haxe-method"
			&& kind != "direct-haxe-constructor"
			&& kind != "typed-function-value")
			throw 'Unsupported typed-call kind "$kind".';
		return kind;
	}

	static function callDecision(value:Dynamic):InspectionCall {
		final source = requiredObject(value, "source");
		final id = requiredString(value, "id");
		final kind = requireCallKind(value);
		final receiver = callReceiver(value, kind);
		final arguments = callValues(value, "arguments");
		final schedule = callEvaluationSchedule(value, id, kind, arguments);
		final resultKind = callResultKind(value);
		return {
			id: id,
			sourceFile: requiredString(source, "file"),
			sourceMin: requiredInt(source, "min"),
			sourceMax: requiredInt(source, "max"),
			calleeId: requiredString(value, "calleeId"),
			sourceModuleId: requiredString(value, "sourceModuleId"),
			sourceTypeName: requiredString(value, "sourceTypeName"),
			sourceFieldName: requiredString(value, "sourceFieldName"),
			kind: kind,
			receiver: receiver,
			arguments: arguments,
			resultKind: resultKind,
			result: callResult(value, resultKind),
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

	static function callEvaluationSchedule(value:Dynamic, callId:String, kind:String,
			arguments:Array<InspectionCallValue>):Array<InspectionCallEvaluationStep> {
		final schedule = [
			for (entry in requiredArray(value, "evaluationSchedule"))
				{
					kind: requiredString(entry, "kind"),
					argumentIndex: optionalInt(entry, "argumentIndex"),
					sourceArgumentIndex: optionalInt(entry, "sourceArgumentIndex"),
					slotId: optionalString(entry, "slotId")
				}
		];
		final materializesCallee = kind == "typed-function-value";
		final materializesReceiver = kind == "direct-instance-haxe-method";
		final scheduleOffset = (materializesCallee ? 1 : 0) + (materializesReceiver ? 1 : 0);
		if (schedule.length != arguments.length + scheduleOffset + 1)
			throw 'Call "$callId" has an unsupported evaluation-schedule length.';
		if (materializesCallee) {
			final callee = schedule[0];
			final expectedCalleeSlot = "call-callee-slot:" + Sha256.encode(callId).substr(0, 24);
			if (callee.kind != "materialize-callee" || callee.argumentIndex != null || callee.sourceArgumentIndex != null
				|| callee.slotId != expectedCalleeSlot)
				throw 'Call "$callId" has an invalid callee materialization.';
		}
		if (materializesReceiver) {
			final receiver = schedule[0];
			final expectedReceiverSlot = "call-receiver-slot:" + Sha256.encode(callId).substr(0, 24);
			if (receiver.kind != "materialize-receiver"
				|| receiver.argumentIndex != null
				|| receiver.sourceArgumentIndex != null
				|| receiver.slotId != expectedReceiverSlot)
				throw 'Call "$callId" has an invalid receiver materialization.';
		}
		var sourceArgumentIndex = 0;
		for (index in 0...arguments.length) {
			final step = schedule[index + scheduleOffset];
			final omitted = isOmittedConversion(arguments[index].conversion);
			final expectedKind = omitted ? "materialize-omitted-argument" : "materialize-argument";
			final expectedSourceIndex:Null<Int> = omitted ? null : sourceArgumentIndex++;
			final expectedSlot = "call-argument-slot:" + Sha256.encode(callId + "|" + index).substr(0, 24);
			if (step.kind != expectedKind
				|| step.argumentIndex != index
				|| step.sourceArgumentIndex != expectedSourceIndex
				|| step.slotId != expectedSlot)
				throw 'Call "$callId" has an invalid materialization at schedule index $index.';
		}
		final invocation = schedule[schedule.length - 1];
		if (invocation.kind != "invoke-callee"
			|| invocation.argumentIndex != null
			|| invocation.sourceArgumentIndex != null
			|| invocation.slotId != null)
			throw 'Call "$callId" has an invalid invocation step.';
		return schedule;
	}

	static function callableBoundary(value:Dynamic):InspectionCallableBoundary {
		final resultKind = callResultKind(value);
		final kind = requireCallKind(value);
		if (kind != "direct-static-haxe-method" && kind != "direct-instance-haxe-method" && kind != "direct-haxe-constructor")
			throw 'Unsupported callable-boundary kind "$kind".';
		final receiver = callReceiver(value, kind);
		return {
			id: requiredString(value, "id"),
			calleeId: requiredString(value, "calleeId"),
			sourceModuleId: requiredString(value, "sourceModuleId"),
			sourceTypeName: requiredString(value, "sourceTypeName"),
			sourceFieldName: requiredString(value, "sourceFieldName"),
			kind: kind,
			receiver: receiver,
			arguments: callValues(value, "arguments"),
			resultKind: resultKind,
			result: callResult(value, resultKind),
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
			case "preserve-nullable-bool-carrier":
				if (!sameSides
					|| value.inputSemanticTypeId != "Null<Bool>"
					|| value.inputCarrierTypeId != "Obj.t"
					|| value.proofId != "nullable-bool-call-carrier-preserve-v1")
					throw '$owner has an invalid exact Null<Bool> carrier-preserving crossing.';
			case "box-exact-bool-to-nullable-bool":
				if (value.inputSemanticTypeId != "Bool"
					|| value.inputCarrierTypeId != "bool"
					|| value.outputSemanticTypeId != "Null<Bool>"
					|| value.outputCarrierTypeId != "Obj.t"
					|| value.proofId != "nullable-bool-call-box-v1")
					throw '$owner has an invalid exact Bool-to-Null<Bool> boxing crossing.';
			case "materialize-omitted-nullable-int":
				if (!value.parameterOptional
					|| !sameSides
					|| value.inputSemanticTypeId != "Null<Int>"
					|| value.inputCarrierTypeId != "Obj.t"
					|| value.proofId != "omitted-nullable-int-call-materialization-v1")
					throw '$owner has an invalid omitted optional Null<Int> materialization.';
			case "materialize-omitted-nullable-bool":
				if (!value.parameterOptional
					|| !sameSides
					|| value.inputSemanticTypeId != "Null<Bool>"
					|| value.inputCarrierTypeId != "Obj.t"
					|| value.proofId != "omitted-nullable-bool-call-materialization-v1")
					throw '$owner has an invalid omitted optional Null<Bool> materialization.';
			case "materialize-omitted-string":
				if (!value.parameterOptional
					|| !sameSides
					|| value.inputSemanticTypeId != "String"
					|| value.inputCarrierTypeId != "string"
					|| value.proofId != "omitted-string-call-materialization-v1")
					throw '$owner has an invalid omitted optional String materialization.';
			case "materialize-explicit-null-string":
				if (!value.parameterOptional
					|| !sameSides
					|| value.inputSemanticTypeId != "String"
					|| value.inputCarrierTypeId != "string"
					|| value.proofId != "explicit-null-string-call-materialization-v1")
					throw '$owner has an invalid explicitly supplied null String materialization.';
			case _:
				throw '$owner has unsupported conversion "${value.conversion}".';
		}
	}

	/** Rejects report entries whose source declaration identity contradicts their call kind. */
	static function validateDeclaredCallIdentity(kind:String, sourceModuleId:String, sourceTypeName:String, sourceFieldName:String, owner:String):Void {
		if (kind == "typed-function-value") {
			if (sourceModuleId.length != 0 || sourceTypeName.length != 0 || sourceFieldName.length != 0)
				throw '$owner assigns a declaration identity to a computed function value.';
			return;
		}
		if (sourceModuleId.length == 0 || sourceTypeName.length == 0 || sourceFieldName.length == 0)
			throw '$owner has an incomplete Haxe declaration identity.';
		if (kind == "direct-haxe-constructor" && sourceFieldName != "new")
			throw '$owner identifies constructor field "$sourceFieldName" instead of "new".';
	}

	static function validateCallSignature(kind:String, receiver:Null<InspectionCallValue>, arguments:Array<InspectionCallValue>, resultKind:String,
			result:Null<InspectionCallValue>, proofId:String, representations:Map<String, InspectionRepresentationDecision>, isCallableBoundary:Bool,
			owner:String):Void {
		if (kind == "direct-static-haxe-method" && proofId != DIRECT_STATIC_SIGNATURE_PROOF_ID)
			throw '$owner has proof "$proofId" instead of "$DIRECT_STATIC_SIGNATURE_PROOF_ID".';
		if (kind == "direct-instance-haxe-method") {
			if (proofId != DIRECT_INSTANCE_SIGNATURE_PROOF_ID)
				throw '$owner has proof "$proofId" instead of "$DIRECT_INSTANCE_SIGNATURE_PROOF_ID".';
			if (receiver == null)
				throw '$owner has no sealed instance receiver.';
			if (!isAdmittedNominalSide(receiver.inputSemanticTypeId, receiver.inputCarrierTypeId, receiver.inputRepresentationId, representations)
				|| !isAdmittedNominalSide(receiver.outputSemanticTypeId, receiver.outputCarrierTypeId, receiver.outputRepresentationId, representations)) {
				throw '$owner has an instance receiver outside the sealed nominal carrier family.';
			}
		} else if (receiver != null) {
			throw '$owner unexpectedly owns an instance receiver.';
		}
		if (kind == "direct-haxe-constructor") {
			if (proofId != DIRECT_CONSTRUCTOR_SIGNATURE_PROOF_ID)
				throw '$owner has proof "$proofId" instead of "$DIRECT_CONSTRUCTOR_SIGNATURE_PROOF_ID".';
			if (arguments.length != 1 || arguments[0].parameterOptional)
				throw '$owner is outside the one-required-argument constructor slice.';
			if (!isCallValueSide(arguments[0].inputSemanticTypeId, arguments[0].inputCarrierTypeId, arguments[0].inputRepresentationId, "Int", "int")
				|| !isCallValueSide(arguments[0].outputSemanticTypeId, arguments[0].outputCarrierTypeId, arguments[0].outputRepresentationId, "Int", "int")) {
				throw '$owner is outside the first exact Int constructor-argument slice.';
			}
			if (resultKind != "value" || result == null)
				throw '$owner has no sealed nominal constructor result.';
			final constructorResult:InspectionCallValue = result;
			if (!isAdmittedNominalSide(constructorResult.inputSemanticTypeId, constructorResult.inputCarrierTypeId, constructorResult.inputRepresentationId,
				representations)
				|| !isAdmittedNominalSide(constructorResult.outputSemanticTypeId, constructorResult.outputCarrierTypeId,
					constructorResult.outputRepresentationId, representations)) {
				throw '$owner has no sealed nominal constructor result.';
			}
		}
		if (kind == "typed-function-value") {
			if (isCallableBoundary)
				throw '$owner cannot describe a computed function value.';
			if (proofId.indexOf(FUNCTION_VALUE_SIGNATURE_PROOF_ID_PREFIX) != 0)
				throw '$owner has unsupported function-value proof "$proofId".';
			validateFunctionValueSignatureMatrix(arguments, resultKind, result, proofId, owner);
		}
		switch (resultKind) {
			case "value":
				if (result == null)
					throw '$owner has a value result kind without a value crossing.';
				if (!isAdmittedDirectResultSide(kind, result.inputSemanticTypeId, result.inputCarrierTypeId, result.inputRepresentationId, representations)
					|| !isAdmittedDirectResultSide(kind, result.outputSemanticTypeId, result.outputCarrierTypeId, result.outputRepresentationId,
						representations)) {
					throw '$owner contains a result outside the closed typed-call representation matrix.';
				}
				if (!isCallableBoundary && result.conversion != "identity")
					throw '$owner must preserve the exact exported result carrier at the call occurrence.';
				if (result.parameterOptional)
					throw '$owner result cannot be an optional parameter.';
			case "effect-only-void":
				if (result != null)
					throw '$owner effect-only Void result cannot carry a value crossing.';
			case _:
				throw '$owner has unsupported result kind "$resultKind".';
		}
		var optionalCount = 0;
		for (index in 0...arguments.length) {
			final argument = arguments[index];
			if (!isAdmittedCallValueSide(argument.inputSemanticTypeId, argument.inputCarrierTypeId, argument.inputRepresentationId)
				|| !isAdmittedCallValueSide(argument.outputSemanticTypeId, argument.outputCarrierTypeId, argument.outputRepresentationId)) {
				throw '$owner contains an argument outside the closed typed-call representation matrix.';
			}
			if (isCallableBoundary && argument.conversion != "identity")
				throw '$owner must describe identity carrier values at the callable boundary.';
			if (!isCallableBoundary
				&& (argument.outputSemanticTypeId == "Null<Int>" || argument.outputSemanticTypeId == "Null<Bool>")
				&& argument.conversion == "identity") {
				throw '$owner must explicitly preserve an existing ${argument.outputSemanticTypeId} carrier or box its exact primitive.';
			}
			if (argument.parameterOptional) {
				optionalCount += 1;
				if (optionalCount > 1
					|| index != arguments.length - 1
					|| (argument.outputSemanticTypeId != "Null<Int>"
						&& argument.outputSemanticTypeId != "Null<Bool>"
						&& argument.outputSemanticTypeId != "String")) {
					throw '$owner has an unsupported optional-parameter shape.';
				}
			}
		}
	}

	/** Validates computed callbacks through the same represented-call matrix. */
	static function validateFunctionValueSignatureMatrix(arguments:Array<InspectionCallValue>, resultKind:String, result:Null<InspectionCallValue>,
			proofId:String, owner:String):Void {
		for (argument in arguments) {
			if (!isAdmittedCallValueSide(argument.inputSemanticTypeId, argument.inputCarrierTypeId, argument.inputRepresentationId)
				|| !isAdmittedCallValueSide(argument.outputSemanticTypeId, argument.outputCarrierTypeId, argument.outputRepresentationId)) {
				throw '$owner contains an argument outside the function-value signature matrix.';
			}
		}
		if (resultKind == "value") {
			if (result == null)
				throw '$owner has no represented result in the function-value signature matrix.';
			final functionResult:InspectionCallValue = result;
			if (!isAdmittedCallValueSide(functionResult.inputSemanticTypeId, functionResult.inputCarrierTypeId, functionResult.inputRepresentationId)
				|| !isAdmittedCallValueSide(functionResult.outputSemanticTypeId, functionResult.outputCarrierTypeId, functionResult.outputRepresentationId)
				|| functionResult.inputSemanticTypeId != functionResult.outputSemanticTypeId
				|| functionResult.inputCarrierTypeId != functionResult.outputCarrierTypeId
				|| functionResult.inputRepresentationId != functionResult.outputRepresentationId
				|| functionResult.conversion != "identity") {
				throw '$owner contains a result outside the function-value signature matrix.';
			}
		}
		final parameterIds = arguments.map(argument -> (argument.parameterOptional ? "?" : "") + argument.outputSemanticTypeId);
		final resultId = resultKind == "effect-only-void" ? "Void" : (result == null ? "" : result.outputSemanticTypeId);
		final expectedProofId = FUNCTION_VALUE_SIGNATURE_PROOF_ID_PREFIX + '(${parameterIds.join(",")})->$resultId';
		if (proofId != expectedProofId)
			throw '$owner binds proof "$proofId" to the wrong canonical function-value signature; expected "$expectedProofId".';
	}

	static function isOmittedConversion(conversion:String):Bool {
		return conversion == "materialize-omitted-nullable-int"
			|| conversion == "materialize-omitted-nullable-bool"
			|| conversion == "materialize-omitted-string";
	}

	static function isAdmittedCallValueSide(semanticTypeId:String, carrierTypeId:String, representationId:String):Bool {
		return isCallValueSide(semanticTypeId, carrierTypeId, representationId, "Int", "int")
			|| isCallValueSide(semanticTypeId, carrierTypeId, representationId, "Bool", "bool")
			|| isCallValueSide(semanticTypeId, carrierTypeId, representationId, "String", "string")
			|| isCallValueSide(semanticTypeId, carrierTypeId, representationId, "Null<Int>", "Obj.t")
			|| isCallValueSide(semanticTypeId, carrierTypeId, representationId, "Null<Bool>", "Obj.t");
	}

	static function isAdmittedDirectResultSide(kind:String, semanticTypeId:String, carrierTypeId:String, representationId:String,
			representations:Map<String, InspectionRepresentationDecision>):Bool {
		if (isAdmittedCallValueSide(semanticTypeId, carrierTypeId, representationId))
			return true;
		return (kind == "direct-static-haxe-method" || kind == "direct-instance-haxe-method" || kind == "direct-haxe-constructor")
			&& isAdmittedNominalSide(semanticTypeId, carrierTypeId, representationId, representations);
	}

	/**
		Returns whether one reported call side is backed by a sealed nominal
		representation, rather than merely using a nominal-looking identity.
	**/
	static function isAdmittedNominalSide(semanticTypeId:String, carrierTypeId:String, representationId:String,
			representations:Map<String, InspectionRepresentationDecision>):Bool {
		final representation = representations.get(representationId);
		return representation != null
			&& representation.semanticTypeId == semanticTypeId
			&& representation.carrierTypeId == carrierTypeId
			&& representation.domain == "internal-value"
			&& representation.boxingPolicy == "nullable-nominal-record-carrier"
			&& representation.nominalTargetModuleName != null
			&& representation.nominalTargetTypeName == carrierTypeId
			&& representation.nominalLayoutRevision != null
			&& representationId == 'representation:$semanticTypeId:internal-value';
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
			&& callValue.parameterOptional == boundaryValue.parameterOptional
			&& (isResult ? (callValue.inputSemanticTypeId == boundaryValue.outputSemanticTypeId
				&& callValue.inputCarrierTypeId == boundaryValue.outputCarrierTypeId
				&& callValue.inputRepresentationId == boundaryValue.outputRepresentationId) : (callValue.outputSemanticTypeId == boundaryValue.inputSemanticTypeId
					&& callValue.outputCarrierTypeId == boundaryValue.inputCarrierTypeId
					&& callValue.outputRepresentationId == boundaryValue.inputRepresentationId));
	}

	static function sameOptionalBoundary(left:Null<InspectionCallValue>, right:Null<InspectionCallValue>):Bool {
		if (left == null || right == null)
			return left == null && right == null;
		return sameCallableBoundary(left, right, false);
	}

	static function sameCallResult(callKind:String, callValue:Null<InspectionCallValue>, boundaryKind:String, boundaryValue:Null<InspectionCallValue>):Bool {
		if (callKind != boundaryKind)
			return false;
		return switch (callKind) {
			case "effect-only-void": callValue == null && boundaryValue == null;
			case "value": callValue != null && boundaryValue != null && sameCallableBoundary(callValue, boundaryValue, true);
			case _:
				false;
		}
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
		if (scope != "exact-int-bool-nullable-string-field-defaults-direct-simple-assignment-array-int-locals-monomorphic-class-v12")
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
			} else if (receiverRepresentationId != null && StringTools.startsWith(receiverRepresentationId, "representation:")) {
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
			message: 'The compiler reported ${decisions.length} program-owned carrier decision${decisions.length == 1 ? "" : "s"} for exact primitives, nullable primitives, direct Array<Int>, or a proven whole-program monomorphic class. A class decision means constructor-produced and already-proven same-class values share one named OCaml record; an admitted captured-and-reassigned local stores that record in one shared cell so the closure sees replacements. Inheritance, interfaces, generics, external boundaries, ordinary mutable locals, and unproved null crossings remain outside this slice.'
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
		final decision:InspectionRepresentationDecision = {
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
			profileEligibility: profiles,
			nominalTargetModuleName: optionalString(value, "nominalTargetModuleName"),
			nominalTargetTypeName: optionalString(value, "nominalTargetTypeName"),
			nominalLayoutRevision: optionalString(value, "nominalLayoutRevision")
		};
		final nominalCount = (decision.nominalTargetModuleName == null ? 0 : 1) + (decision.nominalTargetTypeName == null ? 0 : 1)
			+ (decision.nominalLayoutRevision == null ? 0 : 1);
		final isNominal = decision.boxingPolicy == "nullable-nominal-record-carrier";
		if (isNominal != (nominalCount == 3))
			throw 'Representation decision "${decision.id}" has incomplete or unexpected nominal carrier metadata.';
		if (isNominal
			&& (decision.nominalTargetModuleName.length == 0
				|| decision.nominalTargetTypeName.length == 0
				|| decision.carrierTypeId != decision.nominalTargetTypeName
				|| !StringTools.startsWith(decision.nominalLayoutRevision, "sha256:")
				|| decision.proofId != "whole-program-monomorphic-nominal-record-v1:" + decision.nominalLayoutRevision)) {
			throw 'Representation decision "${decision.id}" does not match its sealed nominal carrier layout.';
		}
		if (isNominal) {
			final expectedStoragePolicy = switch (decision.domain) {
				case "internal-value": "immutable-binding";
				case "captured-local-storage": "shared-local-cell";
				case _:
					throw 'Representation decision "${decision.id}" selects unsupported nominal carrier domain ${decision.domain}.';
			};
			if (decision.storageMutationPolicy != expectedStoragePolicy) {
				throw 'Representation decision "${decision.id}" selects ${decision.storageMutationPolicy} storage for nominal carrier domain ${decision.domain}, expected $expectedStoragePolicy.';
			}
		}
		return decision;
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
			controlRevision: null,
			controls: [],
			controlCatchRevision: null,
			controlCatches: [],
			controlTargetRevision: null,
			controlTargets: [],
			staticStorageRevision: null,
			staticStorage: [],
			scope: "typed-place-call-and-function-loop-throw-catch-control-families",
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
			scope: "exact-int-bool-nullable-string-field-defaults-direct-simple-assignment-array-int-locals-monomorphic-class-v12",
			message: message
		};
	}

	static function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}

	static function sameStrings(left:Array<String>, right:Array<String>):Bool {
		if (left.length != right.length)
			return false;
		for (index in 0...left.length)
			if (left[index] != right[index])
				return false;
		return true;
	}
}
