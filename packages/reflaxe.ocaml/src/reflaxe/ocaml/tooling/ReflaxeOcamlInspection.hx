package reflaxe.ocaml.tooling;

import haxe.Json;
import haxe.crypto.Sha256;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import reflaxe.ocaml.tooling.InspectionReport.InspectionGeneratedFiles;
import reflaxe.ocaml.tooling.InspectionReport.InspectionArtifactManifest;
import reflaxe.ocaml.tooling.InspectionReport.InspectionAnonymousStructure;
import reflaxe.ocaml.tooling.InspectionReport.InspectionAnonymousStructureOperation;
import reflaxe.ocaml.tooling.InspectionReport.InspectionIMapInterfaceConversion;
import reflaxe.ocaml.tooling.InspectionReport.InspectionCall;
import reflaxe.ocaml.tooling.InspectionReport.InspectionCallEvaluationStep;
import reflaxe.ocaml.tooling.InspectionReport.InspectionCallableBoundary;
import reflaxe.ocaml.tooling.InspectionReport.InspectionReflectCompare;
import reflaxe.ocaml.tooling.InspectionReport.InspectionCallValue;
import reflaxe.ocaml.tooling.InspectionReport.InspectionFunctionResultBoundary;
import reflaxe.ocaml.tooling.InspectionReport.InspectionStandardIMapCallTarget;
import reflaxe.ocaml.tooling.InspectionReport.InspectionStructuralIteratorCallTarget;
import reflaxe.ocaml.tooling.InspectionReport.InspectionStructuralField;
import reflaxe.ocaml.tooling.InspectionReport.InspectionControl;
import reflaxe.ocaml.tooling.InspectionReport.InspectionControlCatchChain;
import reflaxe.ocaml.tooling.InspectionReport.InspectionControlCatchClause;
import reflaxe.ocaml.tooling.InspectionReport.InspectionControlLoopTarget;
import reflaxe.ocaml.tooling.InspectionReport.InspectionControlNominalRepresentationProof;
import reflaxe.ocaml.tooling.InspectionReport.InspectionControlPayload;
import reflaxe.ocaml.tooling.InspectionReport.InspectionContainerElementConversion;
import reflaxe.ocaml.tooling.InspectionReport.InspectionLoweredPlan;
import reflaxe.ocaml.tooling.InspectionReport.InspectionLowering;
import reflaxe.ocaml.tooling.InspectionReport.InspectionLocalConversion;
import reflaxe.ocaml.tooling.InspectionReport.InspectionRepresentation;
import reflaxe.ocaml.tooling.InspectionReport.InspectionRepresentationDecision;
import reflaxe.ocaml.tooling.InspectionReport.InspectionRepresentedArrayDescriptor;
import reflaxe.ocaml.tooling.InspectionReport.InspectionProfile;
import reflaxe.ocaml.tooling.InspectionReport.InspectionRuntime;
import reflaxe.ocaml.tooling.InspectionReport.InspectionRuntimeReason;
import reflaxe.ocaml.tooling.InspectionReport.InspectionStaticStorageEntry;
import reflaxe.ocaml.tooling.InspectionReport.InspectionUnavailableCapability;
import reflaxe.ocaml.tooling.InspectionReport.InspectionUnsafeOperation;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerModel.OcamlArrayLiteralElementProducer;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerModel.OcamlArrayLiteralEvaluationStep;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerModel.OcamlArrayLiteralProducerContract;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerModel.OcamlArrayLiteralProducerDecision;
import reflaxe.ocaml.lowered.OcamlControlAdmission.OcamlControlAdmissionBlocker;
import reflaxe.ocaml.lowered.OcamlControlAdmission.OcamlControlAdmissionContract;
import reflaxe.ocaml.lowered.OcamlControlAdmission.OcamlControlAdmissionFamily;
import reflaxe.ocaml.lowered.OcamlControlAdmission.OcamlControlAdmissionSnapshot;
import reflaxe.ocaml.lowered.OcamlControlAdmission.OcamlControlAdmissionStatus;
import reflaxe.ocaml.lowered.OcamlControlAdmission.OcamlControlCatchAdmission;
import reflaxe.ocaml.lowered.OcamlControlAdmission.OcamlControlFamilyAdmission;
import reflaxe.ocaml.lowered.OcamlFloatRepresentationModel.OcamlFloatRepresentationContract;
import reflaxe.ocaml.lowered.OcamlInt64RepresentationModel.OcamlInt64RepresentationContract;

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
	static inline final FUNCTION_RESULT_BOUNDARY_MODEL = "typed-ocaml-function-result-boundary-v2";
	static inline final CALLABLE_FUNCTION_RESULT_PROOF_ID = "callable-function-result-boundary-v1";
	static inline final STATIC_INLINE_EXACT_INT_RESULT_PROOF_ID = "static-inline-exact-int-function-result-v1";
	static inline final NON_GENERIC_INSTANCE_EXACT_INT_RESULT_PROOF_ID = "non-generic-instance-exact-int-function-result-v1";
	static inline final NON_GENERIC_INSTANCE_EXACT_STRING_RESULT_PROOF_ID = "non-generic-instance-exact-string-function-result-v1";
	static inline final NON_GENERIC_INSTANCE_EFFECT_ONLY_VOID_RESULT_PROOF_ID = "non-generic-instance-effect-only-void-function-result-v1";
	static inline final STATIC_NULLABLE_ANONYMOUS_RESULT_PROOF_ID = "static-nullable-anonymous-function-result-v1";
	static inline final PROFILE_REPORT = "ocaml_profile_report.json";
	static inline final RUNTIME_REPORT = "ocaml_runtime_plan_report.json";
	static inline final LOWERING_REPORT = "ocaml_lowering_report.json";
	static inline final DIRECT_STATIC_SIGNATURE_PROOF_ID = "direct-static-representation-signature-v3";
	static inline final DIRECT_INSTANCE_SIGNATURE_PROOF_ID = "direct-instance-receiver-signature-v1";
	static inline final DIRECT_CONSTRUCTOR_SIGNATURE_PROOF_ID = "direct-constructor-nominal-result-v1";
	static inline final FUNCTION_VALUE_SIGNATURE_PROOF_ID_PREFIX = "typed-function-value-signature-matrix-v1:";
	static inline final REFLECT_COMPARE_MODEL = "typed-ocaml-reflect-compare-intrinsic-v1";
	static inline final REFLECT_COMPARE_PROOF_ID_PREFIX = "ocaml-reflect-compare-intrinsic-v1:";
	static inline final FUNCTION_PLAN_PIPELINE_REVISION = "ocaml-function-plans-v78";
	static inline final NESTED_FUNCTION_PIPELINE_REVISION = "ocaml-nested-function-plans-v12";
	static inline final STANDALONE_EXPRESSION_PIPELINE_REVISION = "ocaml-standalone-expression-plans-v3";

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
			schemaVersion: 43,
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
				representedArrayCount: representation.representedArrays.length,
				arrayLiteralProducerCount: lowering.arrayLiteralProducers.length,
				anonymousStructureCount: lowering.anonymousStructures.length,
				anonymousStructureOperationCount: lowering.anonymousStructureOperations.length,
				structuralFieldCount: lowering.structuralFields.length,
				iMapInterfaceConversionCount: lowering.iMapInterfaceConversions.length,
				iMapInterfaceCallCount: lowering.iMapInterfaceCalls.length,
				localConversionCount: lowering.localConversions.length,
				containerElementConversionCount: lowering.containerElementConversions.length,
				unsafeOperationCount: lowering.unsafeOperations.length,
				callCount: lowering.calls.length,
				callableBoundaryCount: lowering.callableBoundaries.length,
				reflectCompareCount: lowering.reflectCompare.length,
				functionResultBoundaryCount: lowering.functionResultBoundaries.length,
				controlCount: lowering.controls.length,
				controlCatchCount: lowering.controlCatches.length,
				controlTargetCount: lowering.controlTargets.length,
				controlAdmissionCount: lowering.controlAdmissions.length,
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
			lines.push('[PASS] Anonymous objects: ${report.lowering.anonymousStructures.length} runtime shape${report.lowering.anonymousStructures.length == 1 ? "" : "s"} and ${report.lowering.anonymousStructureOperations.length} create, initialize, read, plain-write, or compound-write occurrence${report.lowering.anonymousStructureOperations.length == 1 ? "" : "s"} were validated before target syntax.');
			lines.push('[PASS] Direct represented array literals: ${report.lowering.arrayLiteralProducers.length} construction occurrence${report.lowering.arrayLiteralProducers.length == 1 ? "" : "s"} fixed container creation and source-order element evaluation before target syntax.');
			for (producer in report.lowering.arrayLiteralProducers)
				lines.push('  - ${producer.source.file} bytes ${producer.source.min}-${producer.source.max}: ${producer.arraySemanticTypeId}/${producer.arrayCarrierTypeId} via ${producer.id}');
			for (structure in report.lowering.anonymousStructures) {
				final fields = structure.fields.map(field -> '${field.name}:${field.semanticTypeId}/${field.carrierTypeId}');
				lines.push('  - ${structure.semanticTypeId} -> ${structure.carrierTypeId}: ${fields.join(", ")}');
			}
			lines.push('[PASS] Ambiguous structural fields: ${report.lowering.structuralFields.length} stored read, stored write, captured Iterator method, or proven Map-pair projection occurrence${report.lowering.structuralFields.length == 1 ? "" : "s"} were classified from final Haxe types before target syntax.');
			for (field in report.lowering.structuralFields) {
				lines.push('  - ${field.sourceFile} bytes ${field.sourceMin}-${field.sourceMax} ${field.fieldName}: ${field.operation} via ${field.runtimeModule}.${field.runtimeOperation}');
			}
			lines.push('[PASS] IMap interfaces: ${report.lowering.iMapInterfaceConversions.length} concrete-to-interface conversion${report.lowering.iMapInterfaceConversions.length == 1 ? "" : "s"} and ${report.lowering.iMapInterfaceCalls.length} interface call${report.lowering.iMapInterfaceCalls.length == 1 ? "" : "s"} were validated before target syntax.');
			lines.push('[PASS] Local carrier conversions: ${report.lowering.localConversions.length} occurrence${report.lowering.localConversions.length == 1 ? "" : "s"} sealed before syntax.');
			lines.push('[PASS] Container-element conversions: ${report.lowering.containerElementConversions.length} typed array element${report.lowering.containerElementConversions.length == 1 ? "" : "s"} sealed before syntax.');
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
			lines.push('[PASS] Reflect.compare: ${report.lowering.reflectCompare.length} exact Int, Float, or String comparison${report.lowering.reflectCompare.length == 1 ? "" : "s"} selected before OCaml syntax.');
			lines.push('[PASS] Function results: ${report.lowering.functionResultBoundaries.length} emitted function completion boundar${report.lowering.functionResultBoundaries.length == 1 ? "y" : "ies"} validated independently from call receivers and arguments.');
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
			for (descriptor in report.representation.representedArrays) {
				lines.push('  - ${descriptor.arraySemanticTypeId}: ${descriptor.elementRepresentationId}@${descriptor.elementRepresentationRevision} -> ${descriptor.arrayCarrierTypeId}');
				lines.push('    descriptor: ${descriptor.id}@${descriptor.revision}');
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
		lines.push(report.summary.valid ? 'REFLAXE_OCAML_INSPECT:PASS generated_files=${report.summary.generatedFileCount} artifacts=${report.summary.artifactEntryCount} runtime_modules=${report.summary.runtimeModuleCount} lowered_plans=${report.summary.loweredPlanCount} function_results=${report.summary.functionResultBoundaryCount} control_admissions=${report.summary.controlAdmissionCount}' : 'REFLAXE_OCAML_INSPECT:FAIL errors=${report.summary.errorCount}');
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
					if (version != 3) {
						throw 'Unsupported profile report schema $version; expected 3.';
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
					arrayLiteralProducerModel: null,
					arrayLiteralProducerRevision: null,
					arrayLiteralProducers: [],
					anonymousStructureRevision: null,
					anonymousStructures: [],
					anonymousStructureOperations: [],
					structuralFieldRevision: null,
					structuralFields: [],
					iMapInterfaceRevision: null,
					iMapInterfaceConversions: [],
					iMapInterfaceCalls: [],
					localConversionRevision: null,
					localConversions: [],
					containerElementRequiredConversionRevision: null,
					containerElementRequiredConversionIds: [],
					containerElementConversionRevision: null,
					containerElementConversions: [],
					unsafeOperationCompleteness: null,
					unsafeOperationRevision: null,
					unsafeOperations: [],
					callRevision: null,
					calls: [],
					callableBoundaries: [],
					reflectCompareRevision: null,
					reflectCompare: [],
					functionResultBoundaryRevision: null,
					functionResultBoundaries: [],
					controlRevision: null,
					controls: [],
					controlCatchRevision: null,
					controlCatches: [],
					controlTargetRevision: null,
					controlTargets: [],
					controlAdmissionRevision: null,
					controlAdmissions: [],
					staticStorageRevision: null,
					staticStorage: [],
					scope: "typed-place-anonymous-object-call-and-function-loop-throw-catch-control-families",
					message: "Typed place lowering was not requested. Add -D ocaml_lowering_report to the project HXML and rebuild."
				};
			case Invalid(message):
				loweringFailure(path, message, required);
			case Loaded(value):
				try {
					final version = requiredInt(value, "schemaVersion");
					if (version != 66) {
						throw 'Unsupported lowering report schema $version; expected 66.';
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
					final arrayLiteralProducers = inspectArrayLiteralProducers(value, representation);
					final anonymousStructures = ReflaxeOcamlAnonymousStructureInspection.inspect(value, representation);
					final structuralFields = ReflaxeOcamlStructuralFieldInspection.inspect(value);
					final iMapInterfaces = ReflaxeOcamlIMapInterfaceInspection.inspect(value);
					final localConversions = inspectLocalConversions(value);
					final containerElementRequiredConversionIds = inspectContainerElementRequiredConversions(value);
					final containerElementConversions = inspectContainerElementConversions(value, containerElementRequiredConversionIds);
					final unsafeOperations = inspectUnsafeOperations(value, localConversions, containerElementConversions);
					final callInventory = inspectCalls(value, representation);
					final reflectCompare = inspectReflectCompare(value);
					final functionResultBoundaries = inspectFunctionResultBoundaries(value, representation, callInventory.boundaries,
						anonymousStructures.structures);
					final controlTargets = inspectControlTargets(value);
					final controls = inspectControls(value, representation, arrayLiteralProducers, controlTargets);
					final controlCatches = inspectControlCatches(value, representation);
					final controlAdmissions = inspectControlAdmissions(value, controls, controlTargets, controlCatches);
					requireFunctionResultCoverage(functionResultBoundaries, controlAdmissions, controls);
					final staticStorage = inspectStaticStorage(value, representation);
					final runtimeRequirementCount = validateLoweredRuntimeRequirements(value, plans, representation, localConversions,
						containerElementConversions, anonymousStructures.operations, structuralFields.decisions, iMapInterfaces.conversions,
						callInventory.calls, controls);
					{
						status: "present",
						required: required,
						path: path,
						schemaVersion: version,
						model: model,
						admittedInputRevision: requiredSha256Revision(value, "admittedInputRevision"),
						plans: plans,
						representation: representation,
						arrayLiteralProducerModel: requiredString(value, "arrayLiteralProducerModel"),
						arrayLiteralProducerRevision: requiredSha256Revision(value, "arrayLiteralProducerRevision"),
						arrayLiteralProducers: arrayLiteralProducers,
						anonymousStructureRevision: anonymousStructures.revision,
						anonymousStructures: anonymousStructures.structures,
						anonymousStructureOperations: anonymousStructures.operations,
						structuralFieldRevision: structuralFields.revision,
						structuralFields: structuralFields.decisions,
						iMapInterfaceRevision: iMapInterfaces.revision,
						iMapInterfaceConversions: iMapInterfaces.conversions,
						iMapInterfaceCalls: iMapInterfaces.calls,
						localConversionRevision: requiredSha256Revision(value, "localConversionRevision"),
						localConversions: localConversions,
						containerElementRequiredConversionRevision: requiredSha256Revision(value, "containerElementRequiredConversionRevision"),
						containerElementRequiredConversionIds: containerElementRequiredConversionIds,
						containerElementConversionRevision: requiredSha256Revision(value, "containerElementConversionRevision"),
						containerElementConversions: containerElementConversions,
						unsafeOperationCompleteness: requiredString(value, "unsafeOperationCompleteness"),
						unsafeOperationRevision: requiredSha256Revision(value, "unsafeOperationRevision"),
						unsafeOperations: unsafeOperations,
						callRevision: requiredSha256Revision(value, "callRevision"),
						calls: callInventory.calls,
						callableBoundaries: callInventory.boundaries,
						reflectCompareRevision: requiredSha256Revision(value, "reflectCompareRevision"),
						reflectCompare: reflectCompare,
						functionResultBoundaryRevision: requiredSha256Revision(value, "functionResultBoundaryRevision"),
						functionResultBoundaries: functionResultBoundaries,
						controlRevision: requiredSha256Revision(value, "controlRevision"),
						controls: controls,
						controlCatchRevision: requiredSha256Revision(value, "controlCatchRevision"),
						controlCatches: controlCatches,
						controlTargetRevision: requiredSha256Revision(value, "controlTargetRevision"),
						controlTargets: controlTargets,
						controlAdmissionRevision: requiredSha256Revision(value, "controlAdmissionRevision"),
						controlAdmissions: controlAdmissions,
						staticStorageRevision: requiredSha256Revision(value, "staticStorageRevision"),
						staticStorage: staticStorage,
						scope: "typed-place-anonymous-object-call-and-function-loop-throw-catch-control-families",
						message: 'Typed lowering report contains ${plans.length} sealed place operation${plans.length == 1 ? "" : "s"}, ${arrayLiteralProducers.length} direct represented array-literal producer${arrayLiteralProducers.length == 1 ? "" : "s"}, ${anonymousStructures.structures.length} anonymous-object runtime shape${anonymousStructures.structures.length == 1 ? "" : "s"}, ${anonymousStructures.operations.length} anonymous-object operation${anonymousStructures.operations.length == 1 ? "" : "s"}, ${structuralFields.decisions.length} typed structural-field decision${structuralFields.decisions.length == 1 ? "" : "s"}, ${iMapInterfaces.conversions.length} IMap conversion${iMapInterfaces.conversions.length == 1 ? "" : "s"}, ${iMapInterfaces.calls.length} IMap interface call${iMapInterfaces.calls.length == 1 ? "" : "s"}, ${localConversions.length} occurrence-bound local conversion${localConversions.length == 1 ? "" : "s"}, ${containerElementConversions.length} typed container-element conversion${containerElementConversions.length == 1 ? "" : "s"}, ${unsafeOperations.length} proof-backed unsafe operation${unsafeOperations.length == 1 ? "" : "s"}, ${callInventory.calls.length} typed call${callInventory.calls.length == 1 ? "" : "s"}, ${reflectCompare.length} typed Reflect.compare decision${reflectCompare.length == 1 ? "" : "s"}, ${controls.length} function, loop, or Haxe-exception transfer${controls.length == 1 ? "" : "s"}, ${controlCatches.length} represented primitive, monomorphic-class, or Dynamic catch chain${controlCatches.length == 1 ? "" : "s"}, ${controlTargets.length} lexical loop target${controlTargets.length == 1 ? "" : "s"}, ${controlAdmissions.length} function-level control admission explanation${controlAdmissions.length == 1 ? "" : "s"}, ${staticStorage.length} pre-emission static cell${staticStorage.length == 1 ? "" : "s"}, and $runtimeRequirementCount runtime explanation${runtimeRequirementCount == 1 ? "" : "s"}; it is a bounded typed decision report, not a whole-program IR.'
					};
				} catch (error:Dynamic) {
					loweringFailure(path, Std.string(error), required);
				}
		};
	}

	/**
		Validates every admitted direct represented-array construction before showing it publicly.

		A producer is the compiler's plain-data recipe for allocating one array,
		evaluating each source element once, storing those values in order, and
		returning that same mutable object. Inspection recomputes the recipe revision
		and checks its representation graph, so edited report JSON cannot masquerade
		as compiler-owned construction evidence.
	**/
	static function inspectArrayLiteralProducers(value:Dynamic, representation:InspectionRepresentation):Array<OcamlArrayLiteralProducerDecision> {
		if (requiredString(value, "arrayLiteralProducerModel") != OcamlArrayLiteralProducerContract.MODEL_REVISION)
			throw "Unsupported array-literal producer report model.";
		final raw = requiredArray(value, "arrayLiteralProducers");
		if (raw.length != requiredInt(value, "arrayLiteralProducerCount"))
			throw "Array-literal producer count does not match its inventory.";
		final producers = [for (entry in raw) arrayLiteralProducer(entry)];
		producers.sort((left, right) -> compareStrings(left.id, right.id));
		final expectedRevision = OcamlArrayLiteralProducerContract.planRevision(producers);
		if (requiredSha256Revision(value, "arrayLiteralProducerRevision") != expectedRevision)
			throw "Array-literal producer revision does not match its ordered construction inventory.";

		final representationById:Map<String, InspectionRepresentationDecision> = [];
		for (decision in representation.decisions)
			representationById.set(decision.id, decision);
		final descriptorById:Map<String, InspectionRepresentedArrayDescriptor> = [];
		for (descriptor in representation.representedArrays)
			descriptorById.set(descriptor.id, descriptor);
		final ids:Map<String, Bool> = [];
		for (producer in producers) {
			if (ids.exists(producer.id))
				throw 'Array-literal producer report contains duplicate identity "${producer.id}".';
			final result = representationById.get(producer.resultRepresentationId);
			final descriptor = descriptorById.get(producer.arrayDescriptorId);
			if (result == null || descriptor == null)
				throw 'Array-literal producer "${producer.id}" refers to a missing program representation or represented-array descriptor.';
			if (result.programRevision != producer.programRevision
				|| result.revision != producer.resultRepresentationRevision
				|| result.semanticTypeId != producer.arraySemanticTypeId
				|| result.carrierTypeId != producer.arrayCarrierTypeId
				|| result.domain != "internal-value"
				|| result.arrayDescriptorId != producer.arrayDescriptorId
				|| result.arrayDescriptorRevision != producer.arrayDescriptorRevision
				|| descriptor.programRevision != producer.programRevision
				|| descriptor.revision != producer.arrayDescriptorRevision
				|| descriptor.arraySemanticTypeId != producer.arraySemanticTypeId
				|| descriptor.arrayCarrierTypeId != producer.arrayCarrierTypeId
				|| descriptor.elementSemanticTypeId != producer.elementSemanticTypeId
				|| descriptor.elementCarrierTypeId != producer.elementCarrierTypeId
				|| descriptor.elementRepresentationId != producer.elementRepresentationId
				|| descriptor.elementRepresentationRevision != producer.elementRepresentationRevision) {
				throw 'Array-literal producer "${producer.id}" does not match its program representation and represented-array descriptor.';
			}
			ids.set(producer.id, true);
		}
		return producers;
	}

	static function arrayLiteralProducer(value:Dynamic):OcamlArrayLiteralProducerDecision {
		final source = requiredObject(value, "source");
		final elements:Array<OcamlArrayLiteralElementProducer> = [
			for (entry in requiredArray(value, "elements")) {
				final elementSource = requiredObject(entry, "source");
				{
					id: requiredString(entry, "id"),
					index: requiredInt(entry, "index"),
					source: {
						file: requiredString(elementSource, "file"),
						min: requiredInt(elementSource, "min"),
						max: requiredInt(elementSource, "max")
					},
					semanticTypeId: requiredString(entry, "semanticTypeId"),
					carrierTypeId: requiredString(entry, "carrierTypeId"),
					representationId: requiredString(entry, "representationId"),
					representationRevision: requiredSha256Revision(entry, "representationRevision")
				};
			}
		];
		final evaluationSchedule:Array<OcamlArrayLiteralEvaluationStep> = [
			for (entry in requiredArray(value, "evaluationSchedule")) {
				{
					ordinal: requiredInt(entry, "ordinal"),
					kind: cast requiredString(entry, "kind"),
					elementIndex: optionalInt(entry, "elementIndex"),
					elementProducerId: optionalString(entry, "elementProducerId")
				};
			}
		];
		final producer:OcamlArrayLiteralProducerDecision = {
			id: requiredString(value, "id"),
			source: {
				file: requiredString(source, "file"),
				min: requiredInt(source, "min"),
				max: requiredInt(source, "max")
			},
			literalOrdinal: requiredInt(value, "literalOrdinal"),
			arraySemanticTypeId: requiredString(value, "arraySemanticTypeId"),
			arrayCarrierTypeId: requiredString(value, "arrayCarrierTypeId"),
			resultRepresentationId: requiredString(value, "resultRepresentationId"),
			resultRepresentationRevision: requiredSha256Revision(value, "resultRepresentationRevision"),
			arrayDescriptorId: requiredString(value, "arrayDescriptorId"),
			arrayDescriptorRevision: requiredSha256Revision(value, "arrayDescriptorRevision"),
			elementSemanticTypeId: requiredString(value, "elementSemanticTypeId"),
			elementCarrierTypeId: requiredString(value, "elementCarrierTypeId"),
			elementRepresentationId: requiredString(value, "elementRepresentationId"),
			elementRepresentationRevision: requiredSha256Revision(value, "elementRepresentationRevision"),
			elements: elements,
			evaluationSchedule: evaluationSchedule,
			constructionPolicy: requiredString(value, "constructionPolicy"),
			proofId: requiredString(value, "proofId"),
			proofClaim: requiredString(value, "proofClaim"),
			profileEligibility: requiredStringArray(value, "profileEligibility"),
			functionId: requiredString(value, "functionId"),
			programRevision: requiredString(value, "programRevision"),
			bodyRevision: requiredString(value, "bodyRevision"),
			pipelineRevision: requiredString(value, "pipelineRevision")
		};
		OcamlArrayLiteralProducerContract.requireDecision(producer);
		return producer;
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

	/**
		Validates why each function did or did not use typed control lowering.

		Admitted control lists alone are not complete evidence: an empty list could
		mean either that the function needed no transfer or that one unsupported
		occurrence forced the entire family onto the older builder path. This reader
		requires the planner's explicit distinction and binds it back to every
		reported transfer, loop target, and catch chain.
	**/
	static function inspectControlAdmissions(value:Dynamic, controls:Array<InspectionControl>, targets:Array<InspectionControlLoopTarget>,
			catches:Array<InspectionControlCatchChain>):Array<OcamlControlAdmissionSnapshot> {
		if (requiredString(value, "controlAdmissionModel") != OcamlControlAdmissionContract.MODEL)
			throw "Unsupported control-admission report model.";
		final rawAdmissions = requiredArray(value, "controlAdmissions");
		if (rawAdmissions.length != requiredInt(value, "controlAdmissionCount"))
			throw "Control-admission count does not match its inventory.";
		final expectedRevision = "sha256:" + Sha256.encode(Json.stringify(rawAdmissions));
		if (requiredSha256Revision(value, "controlAdmissionRevision") != expectedRevision)
			throw "Control-admission report revision does not match its function inventory.";
		final admissions = [for (entry in rawAdmissions) controlAdmissionSnapshot(entry)];
		admissions.sort((left, right) -> compareStrings(left.id, right.id));
		final byFunction:Map<String, OcamlControlAdmissionSnapshot> = [];
		final ids:Map<String, Bool> = [];
		for (admission in admissions) {
			OcamlControlAdmissionContract.requireSnapshot(admission);
			final expectedPipelineRevision = admission.functionId.indexOf("|nested-function|") >= 0 ? NESTED_FUNCTION_PIPELINE_REVISION : FUNCTION_PLAN_PIPELINE_REVISION;
			if (admission.pipelineRevision != expectedPipelineRevision)
				throw 'Control admission "${admission.id}" uses unsupported function-plan pipeline "${admission.pipelineRevision}".';
			if (ids.exists(admission.id) || byFunction.exists(admission.functionId))
				throw 'Control-admission report duplicates identity "${admission.id}" or function "${admission.functionId}".';
			ids.set(admission.id, true);
			byFunction.set(admission.functionId, admission);
		}
		for (control in controls)
			requireControlAdmissionBinding(byFunction, control.functionId, control.programRevision, control.bodyRevision, control.pipelineRevision,
				'control decision "${control.id}"');
		for (target in targets)
			requireControlAdmissionBinding(byFunction, target.functionId, target.programRevision, target.bodyRevision, target.pipelineRevision,
				'control loop target "${target.id}"');
		final catchById:Map<String, InspectionControlCatchChain> = [];
		for (chain in catches) {
			requireControlAdmissionBinding(byFunction, chain.functionId, chain.programRevision, chain.bodyRevision, chain.pipelineRevision,
				'control catch chain "${chain.id}"');
			catchById.set(chain.id, chain);
		}
		for (admission in admissions) {
			final controlsForFunction = controls.filter(control -> control.functionId == admission.functionId);
			final returnFamily = OcamlControlAdmissionContract.requireFamilyByKind(admission, OcamlControlAdmissionFamily.Return);
			final loopFamily = OcamlControlAdmissionContract.requireFamilyByKind(admission, OcamlControlAdmissionFamily.Loop);
			final throwFamily = OcamlControlAdmissionContract.requireFamilyByKind(admission, OcamlControlAdmissionFamily.Throw);
			if (returnFamily.decisionCount != Lambda.count(controlsForFunction, control -> control.kind == "return")
				|| loopFamily.decisionCount != Lambda.count(controlsForFunction, control -> control.kind == "break" || control.kind == "continue")
				|| throwFamily.decisionCount != Lambda.count(controlsForFunction, control -> control.kind == "throw")) {
				throw 'Control admission "${admission.id}" disagrees with its admitted decision counts.';
			}
			for (entry in admission.catches) {
				if (entry.status != OcamlControlAdmissionStatus.Admitted)
					continue;
				final chainId:String = cast entry.chainId;
				final chain = catchById.get(chainId);
				if (chain == null
					|| chain.functionId != admission.functionId
					|| chain.programRevision != admission.programRevision
					|| chain.bodyRevision != admission.bodyRevision
					|| chain.pipelineRevision != admission.pipelineRevision) {
					throw 'Control admission "${admission.id}" refers to a missing or stale catch chain.';
				}
			}
			final admittedCatchCount = Lambda.count(admission.catches, entry -> entry.status == OcamlControlAdmissionStatus.Admitted);
			if (admittedCatchCount != Lambda.count(catches, chain -> chain.functionId == admission.functionId))
				throw 'Control admission "${admission.id}" catch count disagrees with the admitted catch-chain inventory.';
		}
		return admissions;
	}

	static function controlAdmissionSnapshot(value:Dynamic):OcamlControlAdmissionSnapshot {
		final families:Array<OcamlControlFamilyAdmission> = [
			for (entry in requiredArray(value, "families"))
				{
					family: cast requiredString(entry, "family"),
					status: cast requiredString(entry, "status"),
					occurrenceCount: requiredInt(entry, "occurrenceCount"),
					decisionCount: requiredInt(entry, "decisionCount"),
					blockers: [
						for (blocker in requiredArray(entry, "blockers"))
							controlAdmissionBlocker(blocker)
					]
				}
		];
		final catches:Array<OcamlControlCatchAdmission> = [
			for (entry in requiredArray(value, "catches"))
				{
					occurrenceId: requiredString(entry, "occurrenceId"),
					source: controlAdmissionSource(requiredObject(entry, "source")),
					status: cast requiredString(entry, "status"),
					chainId: optionalString(entry, "chainId"),
					blockers: [
						for (blocker in requiredArray(entry, "blockers"))
							controlAdmissionBlocker(blocker)
					]
				}
		];
		return {
			id: requiredString(value, "id"),
			functionId: requiredString(value, "functionId"),
			programRevision: requiredString(value, "programRevision"),
			bodyRevision: requiredString(value, "bodyRevision"),
			pipelineRevision: requiredString(value, "pipelineRevision"),
			families: families,
			catches: catches,
			revision: requiredSha256Revision(value, "revision")
		};
	}

	static function controlAdmissionBlocker(value:Dynamic):OcamlControlAdmissionBlocker {
		return {
			code: requiredString(value, "code"),
			occurrenceId: requiredString(value, "occurrenceId"),
			source: controlAdmissionSource(requiredObject(value, "source")),
			semanticTypeId: optionalString(value, "semanticTypeId"),
			message: requiredString(value, "message")
		};
	}

	static function controlAdmissionSource(value:Dynamic):reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan {
		return {
			file: requiredString(value, "file"),
			min: requiredInt(value, "min"),
			max: requiredInt(value, "max")
		};
	}

	static function requireControlAdmissionBinding(byFunction:Map<String, OcamlControlAdmissionSnapshot>, functionId:String, programRevision:String,
			bodyRevision:String, pipelineRevision:String, owner:String):Void {
		final admission = byFunction.get(functionId);
		if (admission == null
			|| admission.programRevision != programRevision
			|| admission.bodyRevision != bodyRevision
			|| admission.pipelineRevision != pipelineRevision) {
			throw 'The $owner has no matching function-level control admission snapshot.';
		}
	}

	static function inspectControls(value:Dynamic, representation:InspectionRepresentation, arrayLiteralProducers:Array<OcamlArrayLiteralProducerDecision>,
			targets:Array<InspectionControlLoopTarget>):Array<InspectionControl> {
		if (requiredString(value, "controlModel") != "typed-ocaml-function-loop-throw-and-catch-control-v21")
			throw "Unsupported control report model.";
		final rawControls = requiredArray(value, "controls");
		if (rawControls.length != requiredInt(value, "controlCount"))
			throw "Control count does not match its inventory.";
		final canonicalControls = Json.stringify({
			targets: requiredArray(value, "controlTargets"),
			decisions: rawControls,
			catchChains: requiredArray(value, "controlCatches")
		});
		final expectedControlRevision = "sha256:" + Sha256.encode(canonicalControls);
		final reportedControlRevision = requiredSha256Revision(value, "controlRevision");
		if (reportedControlRevision != expectedControlRevision)
			throw "Control report revision does not match its targets, decisions, and catch chains.";
		final representationById:Map<String, InspectionRepresentationDecision> = [];
		for (decision in representation.decisions)
			representationById.set(decision.id, decision);
		final representedArrayById:Map<String, InspectionRepresentedArrayDescriptor> = [];
		for (descriptor in representation.representedArrays)
			representedArrayById.set(descriptor.id, descriptor);
		final arrayLiteralProducerById:Map<String, OcamlArrayLiteralProducerDecision> = [];
		final arrayLiteralProducersByBinding:Map<String, Array<OcamlArrayLiteralProducerDecision>> = [];
		for (producer in arrayLiteralProducers) {
			arrayLiteralProducerById.set(producer.id, producer);
			final bindingKey = OcamlArrayLiteralProducerContract.bindingKey(producer.functionId, producer.programRevision, producer.bodyRevision,
				producer.pipelineRevision);
			final bindingProducers = arrayLiteralProducersByBinding.get(bindingKey);
			if (bindingProducers == null)
				arrayLiteralProducersByBinding.set(bindingKey, [producer]);
			else
				bindingProducers.push(producer);
		}
		final arrayLiteralProducerPlanRevisionByBinding:Map<String, String> = [];
		for (bindingKey => producers in arrayLiteralProducersByBinding)
			arrayLiteralProducerPlanRevisionByBinding.set(bindingKey, OcamlArrayLiteralProducerContract.planRevision(producers));
		final targetById:Map<String, InspectionControlLoopTarget> = [];
		for (target in targets)
			targetById.set(target.id, target);
		final controls = [for (entry in rawControls) controlDecision(entry)];
		final ids:Map<String, Bool> = [];
		final bindingByFunction:Map<String, {programRevision:String, bodyRevision:String, pipelineRevision:String}> = [];
		for (control in controls) {
			if (ids.exists(control.id))
				throw 'Control report contains duplicate identity "${control.id}".';
			if (control.sourceFile.length == 0 || control.sourceMin < 0 || control.sourceMax < control.sourceMin)
				throw 'Control decision "${control.id}" has an invalid source span.';
			final expectedPipelineRevision = control.functionId.indexOf("|nested-function|") >= 0 ? NESTED_FUNCTION_PIPELINE_REVISION : FUNCTION_PLAN_PIPELINE_REVISION;
			if (control.pipelineRevision != expectedPipelineRevision) {
				throw 'Control decision "${control.id}" uses unsupported function-plan pipeline "${control.pipelineRevision}"; expected "$expectedPipelineRevision" for function "${control.functionId}".';
			}
			final priorBinding = bindingByFunction.get(control.functionId);
			if (priorBinding == null) {
				bindingByFunction.set(control.functionId, {
					programRevision: control.programRevision,
					bodyRevision: control.bodyRevision,
					pipelineRevision: control.pipelineRevision
				});
			} else if (priorBinding.programRevision != control.programRevision
				|| priorBinding.bodyRevision != control.bodyRevision
				|| priorBinding.pipelineRevision != control.pipelineRevision) {
				throw 'Control decision "${control.id}" disagrees with another decision owned by function "${control.functionId}" about its program, body, or pipeline revision.';
			}
			final payload = control.payload;
			if (payload != null) {
				final producerFieldCount = (payload.arrayLiteralProducerId == null ? 0 : 1) + (payload.arrayLiteralProducerPlanRevision == null ? 0 : 1);
				if (producerFieldCount != 0 && producerFieldCount != 2)
					throw 'Control decision "${control.id}" has an incomplete array-literal producer reference.';
				if (producerFieldCount == 2 && payload.arrayDescriptorId == null)
					throw 'Control decision "${control.id}" attaches an array-literal producer to a non-array payload.';
			}
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
								'Control decision "${control.id}" input', control.programRevision);
							validateCallValueSide(payload.outputRepresentationId, payload.outputSemanticTypeId, payload.outputCarrierTypeId,
								representationById, 'Control decision "${control.id}" output', control.programRevision);
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
							final anonymousDecision = representationById.get(payload.inputRepresentationId);
							final anonymousPayloadValid = StringTools.startsWith(payload.inputSemanticTypeId, "anonymous{")
								&& StringTools.endsWith(payload.inputSemanticTypeId, "}")
								&& payload.inputCarrierTypeId == "Obj.t"
								&& payload.inputRepresentationId == 'representation:${payload.inputSemanticTypeId}:internal-value'
								&& sameSides
								&& anonymousDecision != null
								&& anonymousDecision.revision == payload.representationRevision
								&& anonymousDecision.boxingPolicy == "direct-runtime-container"
								&& payload.nominalRepresentation == null
								&& payload.conversion == "preserve-anonymous-carrier"
								&& payload.proofId == "exact-anonymous-carrier-early-return-control-v1"
								&& control.proofId == "exact-anonymous-carrier-early-return-control-v1";
							final dynamicPayloadValid = payload.inputSemanticTypeId == "Dynamic"
								&& payload.inputCarrierTypeId == "Obj.t"
								&& payload.inputRepresentationId == "representation:Dynamic:internal-value"
								&& sameSides
								&& payload.nominalRepresentation == null
								&& payload.conversion == "preserve-dynamic-return-carrier"
								&& payload.proofId == "dynamic-carrier-return-control-v1"
								&& control.proofId == "dynamic-carrier-return-control-v1";
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
								|| (!exactPayloadValid && !nominalPayloadValid && !nullablePayloadValid && !anonymousPayloadValid && !dynamicPayloadValid
									&& !nullableIntConversionValid && !nullableBoolConversionValid)) {
								throw 'Control decision "${control.id}" has an invalid exact-value, nominal, nullable-carrier, anonymous-object, Dynamic-carrier, or primitive-to-nullable payload crossing.';
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
					final enumCarrier = "haxe-enum-native-variant-carrier-v1:" + payload.inputSemanticTypeId;
					final enumRepresentation = "control-representation:enum-direct-v1:" + payload.inputSemanticTypeId;
					final claimsDirectEnumPayload = payload.conversion == "box-enum-throw-carrier"
						|| payload.proofId == "exact-enum-constructor-throw-control-v1"
						|| control.proofId == "exact-enum-constructor-throw-control-v1"
						|| payload.inputCarrierTypeId.startsWith("haxe-enum-native-variant-carrier-v1:")
						|| payload.outputCarrierTypeId.startsWith("haxe-enum-native-variant-carrier-v1:")
						|| payload.inputRepresentationId.startsWith("control-representation:enum-direct-v1:")
						|| payload.outputRepresentationId.startsWith("control-representation:enum-direct-v1:");
					final directEnumPayload = payload.inputSemanticTypeId.length > 0
						&& payload.inputCarrierTypeId == enumCarrier
						&& payload.outputSemanticTypeId == payload.inputSemanticTypeId
						&& payload.outputCarrierTypeId == enumCarrier
						&& payload.inputRepresentationId == enumRepresentation
						&& payload.outputRepresentationId == enumRepresentation
						&& payload.nominalRepresentation == null;
					if (claimsDirectEnumPayload && !directEnumPayload) {
						throw 'Control decision "${control.id}" has an invalid direct enum-constructor exception carrier.';
					}
					final representedArrayPayload = payload.arrayDescriptorId != null;
					if (payload.representationRevision != null) {
						final programRepresentation = representationById.get(payload.inputRepresentationId);
						if (programRepresentation == null
							|| programRepresentation.revision != payload.representationRevision
							|| programRepresentation.programRevision != control.programRevision) {
							throw 'Control decision "${control.id}" has a missing or stale program-representation revision.';
						}
					}
					if (representedArrayPayload) {
						final descriptorId:String = cast payload.arrayDescriptorId;
						final descriptor = representedArrayById.get(descriptorId);
						final programRepresentation = representationById.get(payload.inputRepresentationId);
						if (descriptor == null
							|| programRepresentation == null
							|| payload.representationRevision != programRepresentation.revision
							|| payload.arrayDescriptorRevision != descriptor.revision
							|| programRepresentation.arrayDescriptorId != descriptor.id
							|| programRepresentation.arrayDescriptorRevision != descriptor.revision
							|| descriptor.arraySemanticTypeId != payload.inputSemanticTypeId
							|| descriptor.arrayCarrierTypeId != payload.inputCarrierTypeId) {
							throw 'Control decision "${control.id}" does not match its represented-array descriptor and representation revisions.';
						}
						if (payload.arrayLiteralProducerId != null) {
							final producerId:String = cast payload.arrayLiteralProducerId;
							final producer = arrayLiteralProducerById.get(producerId);
							final bindingKey = OcamlArrayLiteralProducerContract.bindingKey(control.functionId, control.programRevision, control.bodyRevision,
								control.pipelineRevision);
							final planRevision = arrayLiteralProducerPlanRevisionByBinding.get(bindingKey);
							if (producer == null
								|| planRevision == null
								|| payload.arrayLiteralProducerPlanRevision != planRevision
								|| producer.functionId != control.functionId
								|| producer.programRevision != control.programRevision
								|| producer.bodyRevision != control.bodyRevision
								|| producer.pipelineRevision != control.pipelineRevision
								|| producer.resultRepresentationId != payload.inputRepresentationId
								|| producer.resultRepresentationRevision != payload.representationRevision
								|| producer.arrayDescriptorId != payload.arrayDescriptorId
								|| producer.arrayDescriptorRevision != payload.arrayDescriptorRevision) {
								throw 'Control decision "${control.id}" does not consume its exact revision-bound array-literal producer.';
							}
						}
					}
					if (payload.inputSemanticTypeId == "Dynamic") {
						if (payload.inputCarrierTypeId != "Obj.t"
							|| payload.outputSemanticTypeId != "Dynamic"
							|| payload.outputCarrierTypeId != "Obj.t"
							|| payload.inputRepresentationId != "control-representation:Dynamic:runtime-obj-v1"
							|| payload.outputRepresentationId != "control-representation:Dynamic:runtime-obj-v1"
							|| payload.nominalRepresentation != null) {
							throw 'Control decision "${control.id}" has an invalid Dynamic exception carrier.';
						}
					} else if (payload.inputSemanticTypeId == "haxe.Exception" || payload.inputSemanticTypeId == "haxe.ValueException") {
						final valueException = payload.inputSemanticTypeId == "haxe.ValueException";
						if (payload.inputCarrierTypeId != (valueException ? "Haxe_ValueException.t" : "Haxe_Exception.t")
							|| payload.outputSemanticTypeId != payload.inputSemanticTypeId
							|| payload.outputCarrierTypeId != payload.inputCarrierTypeId
							|| payload.inputRepresentationId != (valueException ? "control-representation:haxe.ValueException:runtime-wrapper-v1" : "control-representation:haxe.Exception:runtime-wrapper-v1")
							|| payload.outputRepresentationId != payload.inputRepresentationId
							|| payload.nominalRepresentation != null) {
							throw 'Control decision "${control.id}" has an invalid exact Haxe exception-wrapper carrier.';
						}
					} else if (!directEnumPayload) {
						validateCallValueSide(payload.inputRepresentationId, payload.inputSemanticTypeId, payload.inputCarrierTypeId, representationById,
							'Control decision "${control.id}" input', control.programRevision);
						validateCallValueSide(payload.outputRepresentationId, payload.outputSemanticTypeId, payload.outputCarrierTypeId, representationById,
							'Control decision "${control.id}" output', control.programRevision);
					}
					final expectedConversion = representedArrayPayload ? "box-represented-array-throw-carrier" : switch (payload.inputSemanticTypeId) {
						case "Int", "String": "repr-and-recover-exact-value";
						case "Bool": "box-bool-and-recover-exact-value";
						case "Null<Int>": "preserve-nullable-int-throw-carrier";
						case "Null<Bool>": "normalize-nullable-bool-throw-carrier";
						case "Dynamic": "preserve-dynamic-throw-carrier";
						case "haxe.Exception", "haxe.ValueException": "box-haxe-exception-wrapper-throw-carrier";
						case _: directEnumPayload ? "box-enum-throw-carrier" : (payload.nominalRepresentation == null ? null : "box-nominal-throw-carrier");
					};
					final expectedTags = representedArrayPayload ? ["Dynamic", "Array"] : switch (payload.inputSemanticTypeId) {
						case "Int", "Bool", "String", "Null<Int>", "Null<Bool>", "Dynamic", "haxe.Exception", "haxe.ValueException": ["Dynamic"];
						case _: directEnumPayload ? ["Dynamic", payload.inputSemanticTypeId] : (payload.nominalRepresentation == null ? [] : ["Dynamic"]);
					};
					final expectedProofId = representedArrayPayload ? "represented-array-throw-control-v1" : switch (payload.inputSemanticTypeId) {
						case "Int", "Bool", "String": "exact-value-throw-control-v1";
						case "Null<Int>": "nullable-int-throw-control-v1";
						case "Null<Bool>": "nullable-bool-throw-control-v1";
						case "Dynamic": "dynamic-carrier-throw-control-v1";
						case "haxe.Exception", "haxe.ValueException": "exact-haxe-exception-wrapper-throw-control-v1";
						case _: directEnumPayload ? "exact-enum-constructor-throw-control-v1" : (payload.nominalRepresentation == null ? null : "exact-monomorphic-class-throw-control-v1");
					};
					final nominalPayloadValid = payload.nominalRepresentation == null ? expectedProofId != "exact-monomorphic-class-throw-control-v1" : validControlNominalRepresentation(payload.inputRepresentationId,
						payload.inputSemanticTypeId, payload.inputCarrierTypeId, payload.nominalRepresentation,
						representationById);
					if (expectedConversion == null
						|| expectedProofId == null
						|| payload.signalCarrierTypeId != "Obj.t"
						|| payload.outputSemanticTypeId != payload.inputSemanticTypeId
						|| payload.outputCarrierTypeId != payload.inputCarrierTypeId
						|| payload.outputRepresentationId != payload.inputRepresentationId
						|| payload.conversion != expectedConversion
						|| !nominalPayloadValid
						|| payload.proofId != expectedProofId
						|| payload.proofClaim.length == 0
						|| control.proofId != expectedProofId
						|| !sameStrings(control.runtimeTags, expectedTags)
						|| control.runtimeTagPolicy != "merge-dynamic-with-exact-runtime-value") {
						if (directEnumPayload)
							throw 'Control decision "${control.id}" has an invalid direct enum-constructor exception carrier.';
						throw 'Control decision "${control.id}" has an invalid represented Haxe exception crossing.';
					}
				case _:
					throw 'Control decision "${control.id}" has unsupported transfer kind "${control.kind}".';
			}
			if (control.proofClaim.length == 0
				|| control.reason.length == 0
				|| control.functionId.length == 0
				|| control.programRevision.length == 0
				|| control.bodyRevision.length == 0
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
		if (requiredString(value, "controlCatchModel") != "typed-ocaml-represented-value-catch-chain-v3")
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
				|| chain.proofId != "represented-value-catch-control-v3"
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
					|| clause.proofId != "represented-value-catch-control-v3"
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
							|| clause.nominalRepresentation != null
							|| index != chain.clauses.length - 1) {
							throw 'Dynamic control catch clause "${clause.id}" has an invalid match-all, order, or carrier-preserving contract.';
						}
					case "haxe.Exception":
						if (clause.outputCarrierTypeId != "Haxe_Exception.t"
							|| clause.outputRepresentationId != "control-representation:haxe.Exception:runtime-wrapper-v1"
							|| clause.matchPolicy != "match-haxe-exception"
							|| clause.runtimeTag != null
							|| clause.conversion != "preserve-or-wrap-haxe-exception"
							|| clause.nominalRepresentation != null) {
							throw 'haxe.Exception control catch clause "${clause.id}" has an invalid match-all wrapper contract.';
						}
					case "haxe.ValueException":
						if (clause.outputCarrierTypeId != "Haxe_ValueException.t"
							|| clause.outputRepresentationId != "control-representation:haxe.ValueException:runtime-wrapper-v1"
							|| clause.matchPolicy != "match-haxe-value-exception"
							|| clause.runtimeTag != null
							|| clause.conversion != "preserve-or-wrap-haxe-value-exception"
							|| clause.nominalRepresentation != null) {
							throw 'haxe.ValueException control catch clause "${clause.id}" has an invalid wrapper-selection contract.';
						}
					case _:
						final nominal = clause.nominalRepresentation;
						if (nominal == null
							|| clause.matchPolicy != "exact-runtime-tag"
							|| clause.runtimeTag != clause.semanticTypeId
							|| clause.conversion != "recover-nominal-value"
							|| !validControlNominalRepresentation(clause.outputRepresentationId, clause.semanticTypeId, clause.outputCarrierTypeId, nominal,
								representationById)) {
							throw 'Monomorphic-class control catch clause "${clause.id}" has an invalid tag, carrier, representation, conversion, or layout proof.';
						}
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
			|| clause.conversion != conversion
			|| clause.nominalRepresentation != null) {
			throw 'Exact ${clause.semanticTypeId} control catch clause "${clause.id}" has an invalid tag, carrier, representation, or conversion.';
		}
		validateCallValueSide(clause.outputRepresentationId, clause.semanticTypeId, clause.outputCarrierTypeId, representationById,
			'Control catch clause "${clause.id}" output', clause.programRevision);
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
		final nominalValue = Reflect.field(value, "nominalRepresentation");
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
			nominalRepresentation: nominalValue == null ? null : controlNominalRepresentation(nominalValue),
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
			representationRevision: optionalString(value, "representationRevision"),
			arrayDescriptorId: optionalString(value, "arrayDescriptorId"),
			arrayDescriptorRevision: optionalString(value, "arrayDescriptorRevision"),
			arrayLiteralProducerId: optionalString(value, "arrayLiteralProducerId"),
			arrayLiteralProducerPlanRevision: optionalString(value, "arrayLiteralProducerPlanRevision"),
			conversion: requiredString(value, "conversion"),
			nominalRepresentation: nominalValue == null ? null : controlNominalRepresentation(nominalValue),
			proofId: requiredString(value, "proofId"),
			proofClaim: requiredString(value, "proofClaim")
		};
	}

	static function controlNominalRepresentation(value:Dynamic):InspectionControlNominalRepresentationProof {
		return {
			targetModuleName: requiredString(value, "targetModuleName"),
			targetTypeName: requiredString(value, "targetTypeName"),
			layoutRevision: requiredString(value, "layoutRevision"),
			representationProofId: requiredString(value, "representationProofId")
		};
	}

	static function validControlNominalRepresentation(representationId:String, semanticTypeId:String, carrierTypeId:String,
			nominal:InspectionControlNominalRepresentationProof, representationById:Map<String, InspectionRepresentationDecision>):Bool {
		final decision = representationById.get(representationId);
		return decision != null
			&& decision.semanticTypeId == semanticTypeId
			&& decision.carrierTypeId == carrierTypeId
			&& decision.domain == "internal-value"
			&& decision.boxingPolicy == "nullable-nominal-record-carrier"
			&& decision.nominalTargetModuleName == nominal.targetModuleName
			&& decision.nominalTargetTypeName == nominal.targetTypeName
			&& decision.nominalLayoutRevision == nominal.layoutRevision
			&& decision.proofId == nominal.representationProofId;
	}

	/**
		Validates the target's concrete `Reflect.compare` choices.

		The report contains plain data chosen from final Haxe types. Inspection checks
		that every entry names one admitted domain and the matching proof, so tooling
		does not infer comparison behavior from generated OCaml text.
	**/
	static function inspectReflectCompare(value:Dynamic):Array<InspectionReflectCompare> {
		if (requiredString(value, "reflectCompareModel") != REFLECT_COMPARE_MODEL)
			throw "Unsupported Reflect.compare report model.";
		final raw = requiredArray(value, "reflectCompare");
		if (raw.length != requiredInt(value, "reflectCompareCount"))
			throw "Reflect.compare count does not match its inventory.";
		final expectedRevision = "sha256:" + Sha256.encode(Json.stringify(raw));
		if (requiredSha256Revision(value, "reflectCompareRevision") != expectedRevision)
			throw "Reflect.compare revision does not match its ordered decision inventory.";
		final decisions = [for (entry in raw) reflectCompareDecision(entry)];
		final ids:Map<String, Bool> = [];
		for (decision in decisions) {
			if (ids.exists(decision.id))
				throw 'Reflect.compare report contains duplicate identity "${decision.id}".';
			if (decision.sourceFile.length == 0 || decision.sourceMin < 0 || decision.sourceMax < decision.sourceMin)
				throw 'Reflect.compare decision "${decision.id}" has an invalid source span.';
			if (decision.domain != "int" && decision.domain != "float" && decision.domain != "string")
				throw 'Reflect.compare decision "${decision.id}" has unsupported domain "${decision.domain}".';
			if (decision.proofId != REFLECT_COMPARE_PROOF_ID_PREFIX + decision.domain || decision.proofClaim.length == 0)
				throw 'Reflect.compare decision "${decision.id}" has an incomplete domain proof.';
			if (decision.functionId.length == 0
				|| decision.programRevision.length == 0
				|| decision.bodyRevision.length == 0
				|| (decision.pipelineRevision != FUNCTION_PLAN_PIPELINE_REVISION
					&& decision.pipelineRevision != STANDALONE_EXPRESSION_PIPELINE_REVISION))
				throw 'Reflect.compare decision "${decision.id}" has an invalid plan binding.';
			ids.set(decision.id, true);
		}
		decisions.sort((left, right) -> compareStrings(left.id, right.id));
		return decisions;
	}

	static function reflectCompareDecision(value:Dynamic):InspectionReflectCompare {
		final source = requiredObject(value, "source");
		return {
			id: requiredString(value, "id"),
			sourceFile: requiredString(source, "file"),
			sourceMin: requiredInt(source, "min"),
			sourceMax: requiredInt(source, "max"),
			domain: requiredString(value, "domain"),
			proofId: requiredString(value, "proofId"),
			proofClaim: requiredString(value, "proofClaim"),
			functionId: requiredString(value, "functionId"),
			programRevision: requiredString(value, "programRevision"),
			bodyRevision: requiredString(value, "bodyRevision"),
			pipelineRevision: requiredString(value, "pipelineRevision")
		};
	}

	static function inspectCalls(value:Dynamic,
			representation:InspectionRepresentation):{calls:Array<InspectionCall>, boundaries:Array<InspectionCallableBoundary>} {
		if (requiredString(value, "callModel") != "typed-ocaml-directional-call-boundary-v20")
			throw "Unsupported call-boundary report model.";
		if (requiredString(value, "structuralIteratorConsumerModel") != "typed-structural-iterator-consumer-v1")
			throw "Unsupported structural Iterator consumer report model.";
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
			if (call.kind == "standard-imap-method") {
				ReflaxeOcamlStandardIMapInspection.validate(call);
				callIds.set(call.id, true);
				continue;
			}
			if (call.kind == "structural-iterator-method") {
				ReflaxeOcamlStructuralIteratorInspection.validate(call);
				callIds.set(call.id, true);
				continue;
			}
			if (call.standardIMapTarget != null)
				throw 'Call "${call.id}" carries a standard IMap target for ordinary call kind "${call.kind}".';
			if (call.structuralIteratorTarget != null)
				throw 'Call "${call.id}" carries a structural Iterator target for ordinary call kind "${call.kind}".';
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

	/**
		Validates the value produced when each emitted function completes.

		A function-result boundary is deliberately narrower than a callable
		boundary: it may authorize recovery of an early `return` value without
		claiming that callers, parameters, or an instance receiver use a new ABI.
		This reader therefore validates result ownership separately and requires
		callable-derived entries to remain exact copies of their callable owner.
	**/
	static function inspectFunctionResultBoundaries(value:Dynamic, representation:InspectionRepresentation,
			callableBoundaries:Array<InspectionCallableBoundary>,
			anonymousStructures:Array<InspectionAnonymousStructure>):Array<InspectionFunctionResultBoundary> {
		if (requiredString(value, "functionResultBoundaryModel") != FUNCTION_RESULT_BOUNDARY_MODEL)
			throw "Unsupported function-result boundary report model.";
		final rawBoundaries = requiredArray(value, "functionResultBoundaries");
		if (rawBoundaries.length != requiredInt(value, "functionResultBoundaryCount"))
			throw "Function-result boundary count does not match its inventory.";
		final expectedRevision = "sha256:" + Sha256.encode(Json.stringify(rawBoundaries));
		if (requiredSha256Revision(value, "functionResultBoundaryRevision") != expectedRevision)
			throw "Function-result boundary revision does not match its ordered inventory.";

		final representationById:Map<String, InspectionRepresentationDecision> = [];
		for (decision in representation.decisions)
			representationById.set(decision.id, decision);
		final callableById:Map<String, InspectionCallableBoundary> = [];
		for (callable in callableBoundaries)
			callableById.set(callable.id, callable);
		final anonymousStructureById:Map<String, InspectionAnonymousStructure> = [];
		for (structure in anonymousStructures)
			anonymousStructureById.set(structure.id, structure);

		final boundaries = [for (entry in rawBoundaries) functionResultBoundary(entry)];
		final ids:Map<String, Bool> = [];
		final functions:Map<String, Bool> = [];
		var previousId = "";
		for (boundary in boundaries) {
			if (ids.exists(boundary.id)
				|| functions.exists(boundary.functionId)
				|| (previousId.length > 0 && compareStrings(previousId, boundary.id) >= 0)) {
				throw 'Function-result boundary report contains duplicate or unsorted identity "${boundary.id}" or function "${boundary.functionId}".';
			}
			if (boundary.id != "function-result-boundary:" + Sha256.encode(boundary.functionId).substr(0, 24)
				|| boundary.functionId.length == 0
				|| boundary.programRevision.length == 0
				|| boundary.bodyRevision.length == 0
				|| boundary.pipelineRevision.length == 0
				|| boundary.reason.length == 0
				|| boundary.proofClaim.length == 0
				|| boundary.profileEligibility.join(",") != "metal,portable") {
				throw 'Function-result boundary "${boundary.id}" has incomplete identity, revision, proof, or profile facts.';
			}
			if (boundary.result != null) {
				validateCallValue(boundary.result, representationById, 'Function-result boundary "${boundary.id}" result');
				validateCallValueSide(boundary.result.inputRepresentationId, boundary.result.inputSemanticTypeId, boundary.result.inputCarrierTypeId,
					representationById, 'Function-result boundary "${boundary.id}" input', boundary.programRevision);
				validateCallValueSide(boundary.result.outputRepresentationId, boundary.result.outputSemanticTypeId, boundary.result.outputCarrierTypeId,
					representationById, 'Function-result boundary "${boundary.id}" output', boundary.programRevision);
			}
			switch (boundary.source) {
				case "callable-boundary":
					final callableId = boundary.callableBoundaryId;
					if (callableId == null)
						throw 'Function-result boundary "${boundary.id}" has no callable owner.';
					final callable = callableById.get(callableId);
					if (callable == null
						|| boundary.anonymousStructure != null
						|| boundary.proofId != CALLABLE_FUNCTION_RESULT_PROOF_ID
						|| boundary.sourceModuleId != callable.sourceModuleId
						|| boundary.sourceTypeName != callable.sourceTypeName
						|| boundary.sourceFieldName != callable.sourceFieldName
						|| boundary.functionId != callable.functionId
						|| boundary.programRevision != callable.programRevision
						|| boundary.bodyRevision != callable.bodyRevision
						|| boundary.pipelineRevision != callable.pipelineRevision
						|| boundary.resultKind != callable.resultKind
						|| !sameFunctionResultValue(boundary.result, callable.result)) {
						throw 'Function-result boundary "${boundary.id}" disagrees with callable owner "$callableId".';
					}
				case "static-inline-exact-int-declaration":
					validateDeclarationExactResult(boundary, STATIC_INLINE_EXACT_INT_RESULT_PROOF_ID, "|static|function|", "static inline", "Int", "int");
				case "non-generic-instance-exact-int-declaration":
					validateDeclarationExactResult(boundary, NON_GENERIC_INSTANCE_EXACT_INT_RESULT_PROOF_ID, "|instance|function|", "non-generic instance",
						"Int", "int");
				case "non-generic-instance-exact-string-declaration":
					validateDeclarationExactResult(boundary, NON_GENERIC_INSTANCE_EXACT_STRING_RESULT_PROOF_ID, "|instance|function|", "non-generic instance",
						"String", "string");
				case "non-generic-instance-effect-only-void-declaration":
					validateDeclarationEffectOnlyVoidResult(boundary);
				case "static-nullable-anonymous-declaration":
					validateDeclarationAnonymousResult(boundary, anonymousStructureById);
				case _:
					throw 'Function-result boundary "${boundary.id}" has unsupported source "${boundary.source}".';
			}
			ids.set(boundary.id, true);
			functions.set(boundary.functionId, true);
			previousId = boundary.id;
		}
		return boundaries;
	}

	/** Rejects any value carrier or callable owner on declaration-only instance `Void`. */
	static function validateDeclarationEffectOnlyVoidResult(boundary:InspectionFunctionResultBoundary):Void {
		if (boundary.callableBoundaryId != null
			|| boundary.anonymousStructure != null
			|| boundary.sourceModuleId.length == 0
			|| boundary.sourceTypeName.length == 0
			|| boundary.sourceFieldName.length == 0
			|| boundary.functionId.indexOf("|instance|function|") < 0
			|| boundary.resultKind != "effect-only-void"
			|| boundary.result != null
			|| boundary.proofId != NON_GENERIC_INSTANCE_EFFECT_ONLY_VOID_RESULT_PROOF_ID) {
			throw 'Function-result boundary "${boundary.id}" exceeds the declaration-only non-generic instance effect-only Void slice.';
		}
	}

	/** Validates one result-only exact declaration without admitting calls. */
	static function validateDeclarationExactResult(boundary:InspectionFunctionResultBoundary, expectedProofId:String, functionMode:String, label:String,
			semanticTypeId:String, carrierTypeId:String):Void {
		final result = boundary.result;
		if (boundary.callableBoundaryId != null
			|| boundary.anonymousStructure != null
			|| boundary.sourceModuleId.length == 0
			|| boundary.sourceTypeName.length == 0
			|| boundary.sourceFieldName.length == 0
			|| boundary.functionId.indexOf(functionMode) < 0
			|| boundary.resultKind != "value"
			|| result == null
			|| !isCallValueSide(result.inputSemanticTypeId, result.inputCarrierTypeId, result.inputRepresentationId, semanticTypeId, carrierTypeId)
			|| !isCallValueSide(result.outputSemanticTypeId, result.outputCarrierTypeId, result.outputRepresentationId, semanticTypeId, carrierTypeId)
			|| result.index != -1
			|| result.parameterOptional
			|| result.conversion != "identity"
			|| result.proofId != "identity-call-carrier-v1"
			|| boundary.proofId != expectedProofId) {
			throw 'Function-result boundary "${boundary.id}" exceeds the declaration-only $label exact-$semanticTypeId slice.';
		}
	}

	/** Validates a result-only nullable anonymous object against its public structure inventory. */
	static function validateDeclarationAnonymousResult(boundary:InspectionFunctionResultBoundary,
			structuresById:Map<String, InspectionAnonymousStructure>):Void {
		final result = boundary.result;
		final proof = boundary.anonymousStructure;
		final structure = proof == null ? null : structuresById.get(proof.structureId);
		if (boundary.callableBoundaryId != null
			|| boundary.functionId.indexOf("|static|function|") < 0
			|| boundary.resultKind != "value"
			|| result == null
			|| proof == null
			|| structure == null
			|| structure.semanticTypeId != proof.semanticTypeId
			|| structure.revision != proof.structureRevision
			|| structure.proofId != proof.structureProofId
			|| structure.representationId != proof.representationId
			|| structure.representationRevision != proof.representationRevision
			|| structure.programRevision != boundary.programRevision
			|| result.inputSemanticTypeId != proof.semanticTypeId
			|| result.inputCarrierTypeId != "Obj.t"
			|| result.inputRepresentationId != proof.representationId
			|| result.outputSemanticTypeId != proof.semanticTypeId
			|| result.outputCarrierTypeId != "Obj.t"
			|| result.outputRepresentationId != proof.representationId
			|| result.index != -1
			|| result.parameterOptional
			|| result.conversion != "identity"
			|| result.proofId != "identity-call-carrier-v1"
			|| boundary.proofId != STATIC_NULLABLE_ANONYMOUS_RESULT_PROOF_ID) {
			throw 'Function-result boundary "${boundary.id}" exceeds the declaration-only static nullable anonymous-object slice.';
		}
	}

	static function functionResultBoundary(value:Dynamic):InspectionFunctionResultBoundary {
		final resultKind = callResultKind(value);
		final anonymousStructure = Reflect.field(value, "anonymousStructure");
		return {
			id: requiredString(value, "id"),
			source: requiredString(value, "source"),
			callableBoundaryId: optionalString(value, "callableBoundaryId"),
			sourceModuleId: requiredString(value, "sourceModuleId"),
			sourceTypeName: requiredString(value, "sourceTypeName"),
			sourceFieldName: requiredString(value, "sourceFieldName"),
			resultKind: resultKind,
			result: callResult(value, resultKind, "function-result-boundary"),
			anonymousStructure: anonymousStructure == null ? null : {
				semanticTypeId: requiredString(anonymousStructure, "semanticTypeId"),
				structureId: requiredString(anonymousStructure, "structureId"),
				structureRevision: requiredSha256Revision(anonymousStructure, "structureRevision"),
				structureProofId: requiredString(anonymousStructure, "structureProofId"),
				representationId: requiredString(anonymousStructure, "representationId"),
				representationRevision: requiredSha256Revision(anonymousStructure, "representationRevision")
			},
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

	static function sameFunctionResultValue(left:Null<InspectionCallValue>, right:Null<InspectionCallValue>):Bool {
		if (left == null || right == null)
			return left == null && right == null;
		return left.index == right.index
			&& left.parameterOptional == right.parameterOptional
			&& left.inputSemanticTypeId == right.inputSemanticTypeId
			&& left.inputCarrierTypeId == right.inputCarrierTypeId
			&& left.inputRepresentationId == right.inputRepresentationId
			&& left.outputSemanticTypeId == right.outputSemanticTypeId
			&& left.outputCarrierTypeId == right.outputCarrierTypeId
			&& left.outputRepresentationId == right.outputRepresentationId
			&& left.conversion == right.conversion
			&& left.proofId == right.proofId
			&& left.proofClaim == right.proofClaim;
	}

	/**
		Requires every admitted root early-return family to name its result owner.

		A nullable anonymous-object return has one extra ownership rule: the private
		return signal must preserve the exact anonymous structure and representation
		selected for that function's normal object-literal result. Checking the two
		report sections together prevents a plausible-looking control record from
		borrowing another function's `Obj.t` carrier or inventing a shape after typed
		planning has finished.
	**/
	static function requireFunctionResultCoverage(boundaries:Array<InspectionFunctionResultBoundary>, admissions:Array<OcamlControlAdmissionSnapshot>,
			controls:Array<InspectionControl>):Void {
		final byFunction:Map<String, InspectionFunctionResultBoundary> = [];
		for (boundary in boundaries)
			byFunction.set(boundary.functionId, boundary);
		for (admission in admissions) {
			if (admission.functionId.indexOf("|nested-function|") >= 0)
				continue;
			final returns = OcamlControlAdmissionContract.requireFamilyByKind(admission, OcamlControlAdmissionFamily.Return);
			if (returns.status == OcamlControlAdmissionStatus.Admitted
				&& returns.occurrenceCount > 0
				&& !byFunction.exists(admission.functionId)) {
				throw 'Control admission "${admission.id}" admits return transfers without a function-result boundary.';
			}
		}
		for (control in controls) {
			final payload = control.payload;
			if (control.kind != "return" || payload == null)
				continue;
			if (payload.conversion != "preserve-anonymous-carrier")
				continue;
			final boundary = byFunction.get(control.functionId);
			if (boundary == null)
				throw 'Control decision "${control.id}" does not match its function-owned nullable anonymous-object result boundary.';
			final proof = boundary.anonymousStructure;
			if (proof == null)
				throw 'Control decision "${control.id}" does not match its function-owned nullable anonymous-object result boundary.';
			if (boundary.source != "static-nullable-anonymous-declaration"
				|| boundary.callableBoundaryId != null
				|| boundary.programRevision != control.programRevision
				|| boundary.bodyRevision != control.bodyRevision
				|| boundary.pipelineRevision != control.pipelineRevision
				|| payload.inputSemanticTypeId != proof.semanticTypeId
				|| payload.outputSemanticTypeId != proof.semanticTypeId
				|| payload.inputCarrierTypeId != "Obj.t"
				|| payload.outputCarrierTypeId != "Obj.t"
				|| payload.inputRepresentationId != proof.representationId
				|| payload.outputRepresentationId != proof.representationId
				|| payload.representationRevision != proof.representationRevision
				|| payload.proofId != "exact-anonymous-carrier-early-return-control-v1"
				|| control.proofId != "exact-anonymous-carrier-early-return-control-v1") {
				throw 'Control decision "${control.id}" does not match its function-owned nullable anonymous-object result boundary.';
			}
		}
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

	static function callResult(value:Dynamic, resultKind:String, kind:String):Null<InspectionCallValue> {
		if (!Reflect.hasField(value, "result"))
			throw 'Expected typed-call field "result".';
		final rawResult = Reflect.field(value, "result");
		if (kind == "standard-imap-method" || kind == "structural-iterator-method") {
			if (rawResult != null)
				throw 'Specialized call kind "$kind" describes its result in the sealed target instead of an ordinary call crossing.';
			return null;
		}
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
			&& kind != "typed-function-value"
			&& kind != "standard-imap-method"
			&& kind != "structural-iterator-method")
			throw 'Unsupported typed-call kind "$kind".';
		return kind;
	}

	static function callDecision(value:Dynamic):InspectionCall {
		final source = requiredObject(value, "source");
		final id = requiredString(value, "id");
		final kind = requireCallKind(value);
		final receiver = callReceiver(value, kind);
		final arguments = callValues(value, "arguments");
		final standardIMapTarget = standardIMapCallTarget(value, kind);
		final structuralIteratorTarget = structuralIteratorCallTarget(value, kind);
		final schedule = callEvaluationSchedule(value, id, kind, arguments, standardIMapTarget, structuralIteratorTarget);
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
			result: callResult(value, resultKind, kind),
			evaluationSchedule: schedule,
			profileEligibility: requiredStringArray(value, "profileEligibility"),
			reason: requiredString(value, "reason"),
			proofId: requiredString(value, "proofId"),
			proofClaim: requiredString(value, "proofClaim"),
			functionId: requiredString(value, "functionId"),
			programRevision: requiredString(value, "programRevision"),
			bodyRevision: requiredString(value, "bodyRevision"),
			pipelineRevision: requiredString(value, "pipelineRevision"),
			standardIMapTarget: standardIMapTarget,
			structuralIteratorTarget: structuralIteratorTarget
		};
	}

	static function standardIMapCallTarget(value:Dynamic, kind:String):Null<InspectionStandardIMapCallTarget> {
		if (!Reflect.hasField(value, "standardIMapTarget"))
			throw 'Expected typed-call field "standardIMapTarget".';
		final rawTarget = Reflect.field(value, "standardIMapTarget");
		if (kind != "standard-imap-method") {
			if (rawTarget != null)
				throw 'Typed-call kind "$kind" cannot carry a standard IMap target.';
			return null;
		}
		final target = requiredObject(value, "standardIMapTarget");
		return {
			operation: requiredString(target, "operation"),
			keyKind: requiredString(target, "keyKind"),
			receiverSemanticTypeId: requiredString(target, "receiverSemanticTypeId"),
			receiverCarrierId: requiredString(target, "receiverCarrierId"),
			keySemanticTypeId: requiredString(target, "keySemanticTypeId"),
			valueSemanticTypeId: requiredString(target, "valueSemanticTypeId"),
			argumentSemanticTypeIds: requiredStringArray(target, "argumentSemanticTypeIds"),
			resultSemanticTypeId: requiredString(target, "resultSemanticTypeId"),
			runtimeModule: requiredString(target, "runtimeModule"),
			runtimeFunction: requiredString(target, "runtimeFunction"),
			resultForm: requiredString(target, "resultForm"),
			iteratorModule: optionalString(target, "iteratorModule"),
			iteratorFunction: optionalString(target, "iteratorFunction"),
			keyStringifier: optionalString(target, "keyStringifier"),
			valueStringifier: optionalString(target, "valueStringifier"),
			runtimeCapabilities: requiredStringArray(target, "runtimeCapabilities"),
			proofId: requiredString(target, "proofId"),
			proofClaim: requiredString(target, "proofClaim")
		};
	}

	static function structuralIteratorCallTarget(value:Dynamic, kind:String):Null<InspectionStructuralIteratorCallTarget> {
		if (!Reflect.hasField(value, "structuralIteratorTarget"))
			throw 'Expected typed-call field "structuralIteratorTarget".';
		final rawTarget = Reflect.field(value, "structuralIteratorTarget");
		if (kind != "structural-iterator-method") {
			if (rawTarget != null)
				throw 'Typed-call kind "$kind" cannot carry a structural Iterator target.';
			return null;
		}
		final target = requiredObject(value, "structuralIteratorTarget");
		return {
			operation: requiredString(target, "operation"),
			receiverSemanticTypeId: requiredString(target, "receiverSemanticTypeId"),
			receiverCarrierTypeId: requiredString(target, "receiverCarrierTypeId"),
			resultSemanticTypeId: requiredString(target, "resultSemanticTypeId"),
			runtimeModule: requiredString(target, "runtimeModule"),
			runtimeFunction: requiredString(target, "runtimeFunction"),
			runtimeCapabilities: requiredStringArray(target, "runtimeCapabilities"),
			proofId: requiredString(target, "proofId"),
			proofClaim: requiredString(target, "proofClaim")
		};
	}

	static function callEvaluationSchedule(value:Dynamic, callId:String, kind:String, arguments:Array<InspectionCallValue>,
			standardIMapTarget:Null<InspectionStandardIMapCallTarget>,
			structuralIteratorTarget:Null<InspectionStructuralIteratorCallTarget>):Array<InspectionCallEvaluationStep> {
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
		final materializesReceiver = kind == "direct-instance-haxe-method"
			|| kind == "standard-imap-method"
			|| kind == "structural-iterator-method";
		final argumentCount = standardIMapTarget == null ? arguments.length : standardIMapTarget.argumentSemanticTypeIds.length;
		if (structuralIteratorTarget != null && argumentCount != 0)
			throw 'Structural Iterator call "$callId" unexpectedly owns source arguments.';
		final scheduleOffset = (materializesCallee ? 1 : 0) + (materializesReceiver ? 1 : 0);
		if (schedule.length != argumentCount + scheduleOffset + 1)
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
		for (index in 0...argumentCount) {
			final step = schedule[index + scheduleOffset];
			final omitted = standardIMapTarget == null && isOmittedConversion(arguments[index].conversion);
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
			result: callResult(value, resultKind, kind),
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
			case "checked-unbox-nullable-int":
				if (value.index < -1
					|| value.parameterOptional
					|| value.inputSemanticTypeId != "Null<Int>"
					|| value.inputCarrierTypeId != "Obj.t"
					|| value.outputSemanticTypeId != "Int"
					|| value.outputCarrierTypeId != "int"
					|| value.proofId != "nullable-int-call-checked-unbox-v1")
					throw '$owner has an invalid checked Null<Int>-to-Int result crossing.';
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
			case "preserve-dynamic-carrier":
				if (!sameSides
					|| value.inputSemanticTypeId != "Dynamic"
					|| value.inputCarrierTypeId != "Obj.t"
					|| value.proofId != "dynamic-call-carrier-preserve-v1")
					throw '$owner has an invalid Dynamic carrier-preserving crossing.';
			case "box-concrete-to-dynamic":
				final concreteInput = isCallValueSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId, "Int", "int")
					|| isCallValueSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId, "String", "string")
					|| isAdmittedNominalSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId, representations);
				if (value.index < 0
					|| !concreteInput
					|| !isCallValueSide(value.outputSemanticTypeId, value.outputCarrierTypeId, value.outputRepresentationId, "Dynamic", "Obj.t")
					|| value.proofId != "dynamic-call-box-concrete-v1")
					throw '$owner has an invalid admitted concrete-to-Dynamic boxing crossing.';
			case "box-exact-bool-to-dynamic":
				if (value.index < 0
					|| !isCallValueSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId, "Bool", "bool")
					|| !isCallValueSide(value.outputSemanticTypeId, value.outputCarrierTypeId, value.outputRepresentationId, "Dynamic", "Obj.t")
					|| value.proofId != "dynamic-call-box-bool-v1")
					throw '$owner has an invalid exact Bool-to-Dynamic boxing crossing.';
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
			validateFunctionValueSignatureMatrix(arguments, resultKind, result, proofId, representations, owner);
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
			final admittedDynamicNominalInput = !isCallableBoundary
				&& argument.conversion == "box-concrete-to-dynamic"
				&& isAdmittedNominalSide(argument.inputSemanticTypeId, argument.inputCarrierTypeId, argument.inputRepresentationId, representations);
			if ((!isAdmittedCallValueSide(argument.inputSemanticTypeId, argument.inputCarrierTypeId, argument.inputRepresentationId)
				&& !admittedDynamicNominalInput)
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
			proofId:String, representations:Map<String, InspectionRepresentationDecision>, owner:String):Void {
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
			if ((!isAdmittedCallValueSide(functionResult.inputSemanticTypeId, functionResult.inputCarrierTypeId, functionResult.inputRepresentationId)
				&& !isAdmittedNominalSide(functionResult.inputSemanticTypeId, functionResult.inputCarrierTypeId, functionResult.inputRepresentationId,
					representations))
				|| (!isAdmittedCallValueSide(functionResult.outputSemanticTypeId, functionResult.outputCarrierTypeId, functionResult.outputRepresentationId)
					&& !isAdmittedNominalSide(functionResult.outputSemanticTypeId, functionResult.outputCarrierTypeId, functionResult.outputRepresentationId,
						representations))
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
			|| isCallValueSide(semanticTypeId, carrierTypeId, representationId, "Null<Bool>", "Obj.t")
			|| isCallValueSide(semanticTypeId, carrierTypeId, representationId, "Dynamic", "Obj.t");
	}

	static function isAdmittedDirectResultSide(kind:String, semanticTypeId:String, carrierTypeId:String, representationId:String,
			representations:Map<String, InspectionRepresentationDecision>):Bool {
		if (isAdmittedCallValueSide(semanticTypeId, carrierTypeId, representationId))
			return true;
		return (kind == "direct-static-haxe-method"
			|| kind == "direct-instance-haxe-method"
			|| kind == "direct-haxe-constructor"
			|| kind == "typed-function-value")
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

	/**
		Validates one report consumer against the program-owned representation it names.

		When the consumer records a program revision, both sides must come from that
		same complete typed program. Recomputing a report digest therefore cannot make
		a stale control or catch decision look compatible with a newer representation.
	**/
	static function validateCallValueSide(representationId:String, semanticTypeId:String, carrierTypeId:String,
			representations:Map<String, InspectionRepresentationDecision>, owner:String, ?expectedProgramRevision:String):Void {
		final representation = representations.get(representationId);
		if (representation == null)
			throw '$owner refers to missing representation "$representationId".';
		if (expectedProgramRevision != null && representation.programRevision != expectedProgramRevision) {
			throw '$owner belongs to program revision "$expectedProgramRevision", but representation ${representation.id} belongs to "${representation.programRevision}".';
		}
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
		if (scope != "exact-int-bool-int64-nullable-string-field-defaults-direct-simple-assignment-represented-array-locals-monomorphic-class-dynamic-internal-v15")
			throw 'Unsupported representation report scope "$scope".';
		final rawDecisions = requiredArray(value, "representations");
		final expectedCount = requiredInt(value, "representationCount");
		if (rawDecisions.length != expectedCount)
			throw 'Representation report representationCount is $expectedCount but representations contains ${rawDecisions.length} entries.';
		if (requiredSha256Revision(value, "representationRevision") != "sha256:" + Sha256.encode(Json.stringify(rawDecisions)))
			throw "Representation report revision does not match its sorted decisions.";
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
		final representedArrayModel = requiredString(value, "representedArrayModel");
		if (representedArrayModel != "ocaml-represented-array-v1")
			throw 'Unsupported represented-array report model "$representedArrayModel".';
		final rawRepresentedArrays = requiredArray(value, "representedArrays");
		if (rawRepresentedArrays.length != requiredInt(value, "representedArrayCount"))
			throw "Represented-array count does not match its inventory.";
		final representedArrayRevision = requiredSha256Revision(value, "representedArrayRevision");
		if (representedArrayRevision != "sha256:" + Sha256.encode(Json.stringify(rawRepresentedArrays)))
			throw "Represented-array report revision does not match its sorted descriptors.";
		final representedArrays = [for (descriptor in rawRepresentedArrays) representedArrayDescriptor(descriptor)];
		representedArrays.sort((left, right) -> compareStrings(left.id, right.id));
		final representedArrayById:Map<String, InspectionRepresentedArrayDescriptor> = [];
		for (descriptor in representedArrays) {
			if (representedArrayById.exists(descriptor.id))
				throw 'Represented-array report contains duplicate identity "${descriptor.id}".';
			final element = byId.get(descriptor.elementRepresentationId);
			if (element == null)
				throw 'Represented-array descriptor "${descriptor.id}" refers to missing element representation "${descriptor.elementRepresentationId}".';
			validateRepresentedArrayDescriptor(descriptor, element);
			representedArrayById.set(descriptor.id, descriptor);
		}
		for (decision in decisions) {
			final arrayFieldCount = (decision.arrayDescriptorId == null ? 0 : 1) + (decision.arrayDescriptorRevision == null ? 0 : 1);
			if (arrayFieldCount == 0)
				continue;
			if (arrayFieldCount != 2)
				throw 'Representation decision "${decision.id}" has incomplete represented-array metadata.';
			final descriptorId:String = cast decision.arrayDescriptorId;
			final descriptor = representedArrayById.get(descriptorId);
			if (descriptor == null
				|| descriptor.revision != decision.arrayDescriptorRevision
				|| descriptor.programRevision != decision.programRevision
				|| descriptor.arraySemanticTypeId != decision.semanticTypeId
				|| descriptor.arrayCarrierTypeId != decision.carrierTypeId) {
				throw 'Representation decision "${decision.id}" does not match ${decision.arrayDescriptorId}@${decision.arrayDescriptorRevision}.';
			}
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
			representedArrayModel: representedArrayModel,
			representedArrayRevision: representedArrayRevision,
			representedArrays: representedArrays,
			scope: scope,
			message: 'The compiler reported ${decisions.length} program-owned carrier decision${decisions.length == 1 ? "" : "s"} and ${representedArrays.length} represented-array descriptor${representedArrays.length == 1 ? "" : "s"}. Each descriptor binds one direct flat array identity to an exact array-element representation. Array<Int> remains the only generally admitted local/place family; Array<String> may appear only when an independently sealed literal producer requires it. Exact primitives, the narrow Float internal value, the exact nominal Int64 value, nullable primitives, and proven whole-program monomorphic classes keep their existing bounded contracts.'
		};
	}

	static function inspectLocalConversions(value:Dynamic):Array<InspectionLocalConversion> {
		if (requiredString(value, "localConversionModel") != "typed-ocaml-local-carrier-conversions-v3")
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
					localId: requiredString(entry, "localId"),
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
				final canonicalId = localConversionOccurrenceId(result);
				if (result.pipelineRevision != FUNCTION_PLAN_PIPELINE_REVISION
					|| result.id != canonicalId)
					throw 'Local conversion "${result.id}" does not match its retained function, revisions, local, role, and source; expected "$canonicalId".';
				if (result.conversion == "box-exact-enum-to-dynamic") {
					final expectedCarrier = "haxe-enum-native-variant-carrier-v1:" + result.inputSemanticTypeId;
					if (result.role != "initializer"
						|| result.inputSemanticTypeId.length == 0
						|| result.inputCarrierTypeId != expectedCarrier
						|| result.outputSemanticTypeId != "Dynamic"
						|| result.outputCarrierTypeId != "Obj.t"
						|| result.proofId != "dynamic-box-exact-enum-v1"
						|| result.unsafeOperationId == null) {
						throw 'Local conversion "${result.id}" has an invalid exact enum-to-Dynamic contract.';
					}
				}
				seen.set(result.id, true);
				result;
			}
		];
		conversions.sort((left, right) -> compareStrings(left.id, right.id));
		return conversions;
	}

	/** Rebuilds the occurrence key using the same schema as final target planning. */
	static function localConversionOccurrenceId(conversion:InspectionLocalConversion):String {
		return "local-conversion:" + Sha256.encode([
			conversion.functionId,
			conversion.programRevision,
			conversion.bodyRevision,
			conversion.pipelineRevision,
			conversion.localId,
			conversion.role,
			conversion.sourceFile,
			Std.string(conversion.sourceMin),
			Std.string(conversion.sourceMax)
		].join("\n")).substr(0, 32);
	}

	/**
		Validates the independent typed-body inventory of required conversions.

		This section remains present even if a conversion, unsafe-operation proof,
		and runtime requirement are all accidentally removed together. The public
		inspector can therefore detect complete disappearance instead of accepting
		a smaller but internally self-consistent report.
	**/
	static function inspectContainerElementRequiredConversions(value:Dynamic):Array<String> {
		if (requiredString(value, "containerElementRequiredConversionModel") != "typed-ocaml-required-container-element-conversions-v1")
			throw "Unsupported required container-element conversion report model.";
		final ids = requiredStringArray(value, "containerElementRequiredConversionIds");
		if (ids.length != requiredInt(value, "containerElementRequiredConversionCount"))
			throw "Required container-element conversion count does not match its inventory.";
		final seen:Map<String, Bool> = [];
		var previous:Null<String> = null;
		for (id in ids) {
			if (id.length == 0)
				throw "Required container-element conversion inventory contains an empty identity.";
			if (seen.exists(id))
				throw 'Required container-element conversion inventory contains duplicate identity "$id".';
			if (previous != null && compareStrings(previous, id) >= 0)
				throw "Required container-element conversion inventory is not in deterministic identity order.";
			seen.set(id, true);
			previous = id;
		}
		final expectedRevision = "sha256:" + Sha256.encode(Json.stringify(ids));
		if (requiredSha256Revision(value, "containerElementRequiredConversionRevision") != expectedRevision)
			throw "Required container-element conversion revision does not match its inventory.";
		return ids;
	}

	static function inspectContainerElementConversions(value:Dynamic, requiredConversionIds:Array<String>):Array<InspectionContainerElementConversion> {
		if (requiredString(value, "containerElementConversionModel") != "typed-ocaml-container-element-conversions-v1")
			throw "Unsupported container-element conversion report model.";
		final raw = requiredArray(value, "containerElementConversions");
		if (raw.length != requiredInt(value, "containerElementConversionCount"))
			throw "Container-element conversion count does not match its inventory.";
		final expectedRevision = "sha256:" + Sha256.encode(Json.stringify(raw));
		if (requiredSha256Revision(value, "containerElementConversionRevision") != expectedRevision)
			throw "Container-element conversion revision does not match its inventory.";
		final seen:Map<String, Bool> = [];
		final conversions = [
			for (entry in raw) {
				final containerSource = requiredObject(entry, "containerSource");
				final source = requiredObject(entry, "source");
				final unsafe = requiredObject(entry, "unsafeOperation");
				final result:InspectionContainerElementConversion = {
					id: requiredString(entry, "id"),
					role: requiredString(entry, "role"),
					containerSourceFile: requiredString(containerSource, "file"),
					containerSourceMin: requiredInt(containerSource, "min"),
					containerSourceMax: requiredInt(containerSource, "max"),
					sourceFile: requiredString(source, "file"),
					sourceMin: requiredInt(source, "min"),
					sourceMax: requiredInt(source, "max"),
					containerOrdinal: requiredInt(entry, "containerOrdinal"),
					elementIndex: requiredInt(entry, "elementIndex"),
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
					unsafeOperationId: requiredString(unsafe, "id")
				};
				if (seen.exists(result.id)) throw 'Container-element conversion report contains duplicate identity "${result.id}".';
				final expectedPipelineRevision = StringTools.startsWith(result.functionId,
					"standalone:") ? STANDALONE_EXPRESSION_PIPELINE_REVISION : FUNCTION_PLAN_PIPELINE_REVISION;
				if (result.role != "array-literal-dynamic-element"
					|| result.containerOrdinal < 0
					|| result.elementIndex < 0
					|| result.containerSourceFile != result.sourceFile
					|| result.containerSourceMin < 0
					|| result.containerSourceMax < result.containerSourceMin
					|| result.sourceMin < 0
					|| result.sourceMax < result.sourceMin
					|| result.inputSemanticTypeId.length == 0
					|| result.inputCarrierTypeId != "haxe-enum-native-variant-carrier-v1:" + result.inputSemanticTypeId
					|| result.outputSemanticTypeId != "Dynamic"
					|| result.outputCarrierTypeId != "Obj.t"
					|| result.conversion != "box-exact-enum-to-dynamic"
					|| result.reason.length == 0
					|| result.proofId != "dynamic-array-element-box-exact-enum-v1"
					|| result.proofClaim.length == 0
					|| result.profileEligibility.length == 0
					|| result.functionId.length == 0
					|| result.programRevision.length == 0
					|| result.bodyRevision.length == 0
					|| result.pipelineRevision != expectedPipelineRevision) {
					throw 'Container-element conversion "${result.id}" has an invalid exact enum-to-Dynamic array contract.';
				}
				final canonicalId = containerElementOccurrenceId(result);
				if (result.id != canonicalId)
					throw 'Container-element conversion "${result.id}" does not match its retained function, revisions, role, sources, array ordinal, and element index; expected "$canonicalId".';
				seen.set(result.id, true);
				result;
			}
		];
		conversions.sort((left, right) -> compareStrings(left.id, right.id));
		final containerSourceByOrdinal:Map<String, String> = [];
		final occupiedSlots:Map<String, Bool> = [];
		for (conversion in conversions) {
			final ordinal = [
				conversion.functionId,
				conversion.programRevision,
				conversion.bodyRevision,
				conversion.pipelineRevision,
				Std.string(conversion.containerOrdinal)
			].join("|");
			final containerSource = '${conversion.containerSourceFile}:${conversion.containerSourceMin}:${conversion.containerSourceMax}';
			final previousSource = containerSourceByOrdinal.get(ordinal);
			if (previousSource != null && previousSource != containerSource)
				throw 'Container-element structural ordinal "$ordinal" names both "$previousSource" and "$containerSource".';
			containerSourceByOrdinal.set(ordinal, containerSource);
			final slot = '$ordinal:${conversion.elementIndex}';
			if (occupiedSlots.exists(slot))
				throw 'Container-element structural slot "$slot" occurs more than once.';
			occupiedSlots.set(slot, true);
		}
		final conversionIds = conversions.map(conversion -> conversion.id);
		if (conversionIds.join("\n") != requiredConversionIds.join("\n"))
			throw 'Required container-element conversion inventory [${requiredConversionIds.join(",")}] does not match sealed conversions [${conversionIds.join(",")}].';
		return conversions;
	}

	static function containerElementOccurrenceId(conversion:InspectionContainerElementConversion):String {
		return "container-element-conversion:" + Sha256.encode([
			conversion.functionId,
			conversion.programRevision,
			conversion.bodyRevision,
			conversion.pipelineRevision,
			conversion.role,
			conversion.containerSourceFile,
			Std.string(conversion.containerSourceMin),
			Std.string(conversion.containerSourceMax),
			conversion.sourceFile,
			Std.string(conversion.sourceMin),
			Std.string(conversion.sourceMax),
			Std.string(conversion.containerOrdinal),
			Std.string(conversion.elementIndex)
		].join("\n")).substr(0, 32);
	}

	static function inspectUnsafeOperations(value:Dynamic, conversions:Array<InspectionLocalConversion>,
			containerElementConversions:Array<InspectionContainerElementConversion>):Array<InspectionUnsafeOperation> {
		if (requiredString(value, "unsafeOperationModel") != "proof-backed-admitted-unsafe-operations-v1")
			throw "Unsupported unsafe-operation report model.";
		if (requiredString(value, "unsafeOperationCompleteness") != "exact-null-int-null-bool-inline-dynamic-and-enum-to-dynamic-local-and-container-slices")
			throw "Unsupported unsafe-operation completeness claim.";
		final raw = requiredArray(value, "unsafeOperations");
		if (raw.length != requiredInt(value, "unsafeOperationCount"))
			throw "Unsafe-operation count does not match its inventory.";
		final conversionById:Map<String, Dynamic> = [];
		for (conversion in conversions)
			conversionById.set(conversion.id, conversion);
		for (conversion in containerElementConversions) {
			if (conversionById.exists(conversion.id))
				throw 'Unsafe-operation owner identity "${conversion.id}" occurs in both local and container-element conversions.';
			conversionById.set(conversion.id, conversion);
		}
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
				final conversion:Dynamic = conversionById.get(result.conversionId);
				if (conversion == null
					|| conversion.unsafeOperationId != result.id) throw 'Unsafe operation "${result.id}" is not owned by its sealed conversion.';
				if (conversion.conversion == "box-exact-enum-to-dynamic"
					&& (result.id != conversion.id + ":unsafe:box-exact-enum-to-dynamic"
						|| result.operation != "box-exact-enum-to-dynamic"
						|| result.sourceFile != conversion.sourceFile
						|| result.sourceMin != conversion.sourceMin
						|| result.sourceMax != conversion.sourceMax
						|| result.inputSemanticTypeId != conversion.inputSemanticTypeId
						|| result.inputCarrierTypeId != conversion.inputCarrierTypeId
						|| result.outputSemanticTypeId != conversion.outputSemanticTypeId
						|| result.outputCarrierTypeId != conversion.outputCarrierTypeId
						|| result.reason != conversion.reason
						|| result.proofId != conversion.proofId
						|| result.proofClaim != conversion.proofClaim
						|| result.profileEligibility.join(",") != conversion.profileEligibility.join(",")
						|| result.functionId != conversion.functionId
						|| result.programRevision != conversion.programRevision
						|| result.bodyRevision != conversion.bodyRevision
						|| result.pipelineRevision != conversion.pipelineRevision))
					throw 'Unsafe operation "${result.id}" does not preserve its sealed enum-to-Dynamic conversion.';
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
		for (conversion in containerElementConversions)
			if (!seen.exists(conversion.unsafeOperationId))
				throw 'Container-element conversion "${conversion.id}" refers to a missing unsafe operation.';
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
			nominalLayoutRevision: optionalString(value, "nominalLayoutRevision"),
			arrayDescriptorId: optionalString(value, "arrayDescriptorId"),
			arrayDescriptorRevision: optionalString(value, "arrayDescriptorRevision")
		};
		final nominalCount = (decision.nominalTargetModuleName == null ? 0 : 1) + (decision.nominalTargetTypeName == null ? 0 : 1)
			+ (decision.nominalLayoutRevision == null ? 0 : 1);
		final isNominal = decision.boxingPolicy == "nullable-nominal-record-carrier"
			|| decision.boxingPolicy == "direct-nominal-value-carrier";
		if (isNominal != (nominalCount == 3))
			throw 'Representation decision "${decision.id}" has incomplete or unexpected nominal carrier metadata.';
		if (isNominal
			&& (decision.nominalTargetModuleName == null
				|| decision.nominalTargetModuleName.length == 0
				|| decision.nominalTargetTypeName == null
				|| decision.nominalTargetTypeName.length == 0
				|| decision.carrierTypeId != decision.nominalTargetTypeName
				|| decision.nominalLayoutRevision == null
				|| !StringTools.startsWith((cast decision.nominalLayoutRevision : String), "sha256:"))) {
			throw 'Representation decision "${decision.id}" does not match its sealed nominal carrier layout.';
		}
		if (decision.semanticTypeId == OcamlFloatRepresentationContract.SEMANTIC_TYPE_ID
			|| decision.id == OcamlFloatRepresentationContract.INTERNAL_REPRESENTATION_ID) {
			if (decision.id != OcamlFloatRepresentationContract.INTERNAL_REPRESENTATION_ID
				|| decision.semanticTypeId != OcamlFloatRepresentationContract.SEMANTIC_TYPE_ID
				|| decision.domain != "internal-value"
				|| decision.carrierTypeId != OcamlFloatRepresentationContract.CARRIER_TYPE_ID
				|| decision.nullPolicy != "non-null"
				|| decision.identityPolicy != "primitive-value"
				|| decision.aliasingPolicy != "no-value-alias"
				|| decision.storageMutationPolicy != "immutable-binding"
				|| decision.valueMutationPolicy != "immutable-value"
				|| decision.boxingPolicy != "direct-unboxed"
				|| decision.implicitDefaultPolicy != "not-admitted"
				|| decision.proofId != OcamlFloatRepresentationContract.PROOF_ID
				|| nominalCount != 0) {
				throw 'Representation decision "${decision.id}" does not match the sealed exact Float internal value carrier.';
			}
		}
		if (decision.boxingPolicy == "direct-nominal-value-carrier") {
			if (decision.id != OcamlInt64RepresentationContract.INTERNAL_REPRESENTATION_ID
				|| decision.semanticTypeId != OcamlInt64RepresentationContract.SEMANTIC_TYPE_ID
				|| decision.domain != "internal-value"
				|| decision.carrierTypeId != OcamlInt64RepresentationContract.TARGET_TYPE_NAME
				|| decision.nullPolicy != "non-null"
				|| decision.identityPolicy != "primitive-value"
				|| decision.aliasingPolicy != "no-value-alias"
				|| decision.storageMutationPolicy != "immutable-binding"
				|| decision.valueMutationPolicy != "immutable-value"
				|| decision.implicitDefaultPolicy != "not-admitted"
				|| decision.nominalTargetModuleName != OcamlInt64RepresentationContract.TARGET_MODULE_NAME
				|| decision.nominalTargetTypeName != OcamlInt64RepresentationContract.TARGET_TYPE_NAME
				|| decision.nominalLayoutRevision != OcamlInt64RepresentationContract.LAYOUT_REVISION
				|| decision.proofId != OcamlInt64RepresentationContract.PROOF_ID) {
				throw 'Representation decision "${decision.id}" does not match the sealed exact Int64 nominal value carrier.';
			}
		} else if (decision.boxingPolicy == "nullable-nominal-record-carrier") {
			if (decision.proofId != "whole-program-monomorphic-nominal-record-v1:" + decision.nominalLayoutRevision) {
				throw 'Representation decision "${decision.id}" does not match its sealed monomorphic-class carrier proof.';
			}
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
		final expectedRevision = "sha256:" + Sha256.encode([
			"ocaml-representation-v21",
			decision.semanticTypeId,
			decision.domain,
			decision.carrierTypeId,
			decision.nullPolicy,
			decision.identityPolicy,
			decision.aliasingPolicy,
			decision.storageMutationPolicy,
			decision.valueMutationPolicy,
			decision.boxingPolicy,
			decision.implicitDefaultPolicy,
			decision.reason,
			decision.proofId,
			decision.proofClaim,
			decision.profileEligibility.join(","),
			decision.nominalTargetModuleName ?? "",
			decision.nominalTargetTypeName ?? "",
			decision.nominalLayoutRevision ?? "",
			decision.arrayDescriptorId ?? "",
			decision.arrayDescriptorRevision ?? ""
		].join("\n"));
		if (decision.revision != expectedRevision)
			throw 'Representation decision "${decision.id}" revision does not match its reported leaf facts.';
		return decision;
	}

	static function representedArrayDescriptor(value:Dynamic):InspectionRepresentedArrayDescriptor {
		return {
			id: requiredString(value, "id"),
			key: requiredString(value, "key"),
			programRevision: requiredString(value, "programRevision"),
			modelRevision: requiredString(value, "modelRevision"),
			revision: requiredSha256Revision(value, "revision"),
			arraySemanticTypeId: requiredString(value, "arraySemanticTypeId"),
			sourceForm: requiredString(value, "sourceForm"),
			closureKind: requiredString(value, "closureKind"),
			outerWrapperKind: requiredString(value, "outerWrapperKind"),
			elementSemanticTypeId: requiredString(value, "elementSemanticTypeId"),
			elementRepresentationId: requiredString(value, "elementRepresentationId"),
			elementRepresentationRevision: requiredSha256Revision(value, "elementRepresentationRevision"),
			elementCarrierTypeId: requiredString(value, "elementCarrierTypeId"),
			elementDomain: requiredString(value, "elementDomain"),
			carrierFamilyId: requiredString(value, "carrierFamilyId"),
			arrayCarrierTypeId: requiredString(value, "arrayCarrierTypeId"),
			runtimeCarrierCapabilityId: requiredString(value, "runtimeCarrierCapabilityId"),
			runtimeKindTagId: requiredString(value, "runtimeKindTagId"),
			nestingKind: requiredString(value, "nestingKind"),
			reason: requiredString(value, "reason"),
			proofId: requiredString(value, "proofId"),
			proofClaim: requiredString(value, "proofClaim"),
			profileEligibility: requiredStringArray(value, "profileEligibility")
		};
	}

	static function validateRepresentedArrayDescriptor(descriptor:InspectionRepresentedArrayDescriptor, element:InspectionRepresentationDecision):Void {
		final expectedArraySemanticTypeId = 'Array<${descriptor.elementSemanticTypeId}>';
		final expectedCarrier = element.carrierTypeId + " HxArray.t";
		final expectedReason = 'The direct closed flat ${descriptor.arraySemanticTypeId} shape uses ${element.id}@${element.revision} for element storage and composes its ${element.carrierTypeId} carrier with HxArray.t.';
		final expectedProofId = "direct-flat-array-element-binding-v1";
		final expectedProofClaim = "The element decision is registered in the ArrayElement domain for the same program, so one HxArray container can store that exact carrier. This descriptor proves only shape and element binding; domain-specific representation decisions still own outer nullability, identity, aliases, replacement, and boxing.";
		final expectedRevision = "sha256:" + Sha256.encode([
			"ocaml-represented-array-v1",
			descriptor.arraySemanticTypeId,
			descriptor.sourceForm,
			descriptor.closureKind,
			descriptor.outerWrapperKind,
			descriptor.elementSemanticTypeId,
			element.id,
			element.revision,
			element.carrierTypeId,
			"array-element",
			"HxArray",
			expectedCarrier,
			"haxe-array",
			"Array",
			descriptor.nestingKind,
			expectedReason,
			expectedProofId,
			expectedProofClaim,
			element.profileEligibility.join(",")
		].join("\n"));
		if (descriptor.id != "represented-array:" + descriptor.arraySemanticTypeId
			|| descriptor.key != descriptor.arraySemanticTypeId
			|| descriptor.arraySemanticTypeId != expectedArraySemanticTypeId
			|| descriptor.programRevision != element.programRevision
			|| descriptor.modelRevision != "ocaml-represented-array-v1"
			|| descriptor.revision != expectedRevision
			|| descriptor.sourceForm != "direct-builtin-array"
			|| descriptor.closureKind != "closed-monomorphic"
			|| descriptor.outerWrapperKind != "none"
			|| descriptor.elementRepresentationId != element.id
			|| descriptor.elementRepresentationRevision != element.revision
			|| descriptor.elementSemanticTypeId != element.semanticTypeId
			|| descriptor.elementCarrierTypeId != element.carrierTypeId
			|| descriptor.elementDomain != "array-element"
			|| element.domain != "array-element"
			|| descriptor.carrierFamilyId != "HxArray"
			|| descriptor.arrayCarrierTypeId != expectedCarrier
			|| descriptor.runtimeCarrierCapabilityId != "haxe-array"
			|| descriptor.runtimeKindTagId != "Array"
			|| descriptor.nestingKind != "flat"
			|| descriptor.reason != expectedReason
			|| descriptor.proofId != expectedProofId
			|| descriptor.proofClaim != expectedProofClaim
			|| descriptor.profileEligibility.join(",") != element.profileEligibility.join(",")) {
			throw 'Represented-array descriptor "${descriptor.id}" does not match its exact array-element representation and derived carrier facts.';
		}
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

	static function validateLoweredRuntimeRequirements(value:Dynamic, plans:Array<InspectionLoweredPlan>, representation:InspectionRepresentation,
			localConversions:Array<InspectionLocalConversion>, containerElementConversions:Array<InspectionContainerElementConversion>,
			anonymousOperations:Array<InspectionAnonymousStructureOperation>, structuralFields:Array<InspectionStructuralField>,
			iMapInterfaceConversions:Array<InspectionIMapInterfaceConversion>, calls:Array<InspectionCall>, controls:Array<InspectionControl>):Int {
		requiredSha256Revision(value, "runtimeRequirementRevision");
		final requirementValues = requiredArray(value, "runtimeRequirements");
		final expectedCount = requiredInt(value, "runtimeRequirementCount");
		if (requirementValues.length != expectedCount) {
			throw 'Lowering report runtimeRequirementCount is $expectedCount but runtimeRequirements contains ${requirementValues.length} entries.';
		}
		final requirements:Map<String, Dynamic> = [];
		for (requirement in requirementValues) {
			final id = requiredString(requirement, "id");
			if (requirements.exists(id))
				throw 'Lowering report contains duplicate runtime requirement "$id".';
			requirements.set(id, requirement);
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
		for (conversion in localConversions) {
			if (conversion.conversion != "box-exact-enum-to-dynamic")
				continue;
			final requirementId = conversion.id + ":runtime:haxe-enum-dynamic-box";
			final requirement = requirements.get(requirementId);
			if (requirement == null)
				throw 'Enum-to-Dynamic conversion "${conversion.id}" refers to missing runtime requirement "$requirementId".';
			final source = requiredObject(requirement, "source");
			final subject = requiredObject(requirement, "subject");
			final roots = requiredStringArray(requirement, "rootModules");
			if (requiredString(requirement, "sourceKind") != "haxe-expression"
				|| requiredString(requirement, "sourceId") != conversion.id
				|| requiredString(source, "file") != conversion.sourceFile
				|| requiredInt(source, "min") != conversion.sourceMin
				|| requiredInt(source, "max") != conversion.sourceMax
				|| requiredString(requirement, "semanticCapability") != "haxe-enum-dynamic-box"
				|| requiredString(requirement, "cause") != "lowering-decision"
				|| requiredString(requirement, "decisionId") != conversion.id
				|| requiredString(subject, "kind") != "haxe-type"
				|| requiredString(subject, "id") != conversion.inputSemanticTypeId
				|| requiredString(requirement, "implementationFeature") != "haxe-enum-dynamic-box-v1"
				|| roots.length != 1
				|| roots[0] != "HxEnum"
				|| requiredStringArray(requirement, "profileEligibility").join(",") != conversion.profileEligibility.join(",")) {
				throw 'Enum-to-Dynamic conversion "${conversion.id}" runtime requirement "$requirementId" disagrees with its sealed HxEnum dependency.';
			}
			referenced.set(requirementId, true);
		}
		for (conversion in containerElementConversions) {
			final requirementId = conversion.id + ":runtime:haxe-enum-dynamic-box";
			final requirement = requirements.get(requirementId);
			if (requirement == null)
				throw 'Container-element conversion "${conversion.id}" refers to missing runtime requirement "$requirementId".';
			final source = requiredObject(requirement, "source");
			final subject = requiredObject(requirement, "subject");
			final roots = requiredStringArray(requirement, "rootModules");
			if (requiredString(requirement, "sourceKind") != "haxe-expression"
				|| requiredString(requirement, "sourceId") != conversion.id
				|| requiredString(source, "file") != conversion.sourceFile
				|| requiredInt(source, "min") != conversion.sourceMin
				|| requiredInt(source, "max") != conversion.sourceMax
				|| requiredString(requirement, "semanticCapability") != "haxe-enum-dynamic-box"
				|| requiredString(requirement, "cause") != "lowering-decision"
				|| requiredString(requirement, "decisionId") != conversion.id
				|| requiredString(subject, "kind") != "haxe-type"
				|| requiredString(subject, "id") != conversion.inputSemanticTypeId
				|| requiredString(requirement, "implementationFeature") != "haxe-enum-dynamic-box-v1"
				|| roots.length != 1
				|| roots[0] != "HxEnum"
				|| requiredStringArray(requirement, "profileEligibility").join(",") != conversion.profileEligibility.join(",")) {
				throw 'Container-element conversion "${conversion.id}" runtime requirement "$requirementId" disagrees with its sealed HxEnum dependency.';
			}
			referenced.set(requirementId, true);
		}
		for (control in controls) {
			final payload = control.payload;
			if (control.kind != "throw" || payload == null)
				continue;
			final enumPayload:InspectionControlPayload = payload;
			if (enumPayload.conversion != "box-enum-throw-carrier")
				continue;
			final requirementId = control.id + ":runtime:haxe-enum-dynamic-box";
			final requirement = requirements.get(requirementId);
			if (requirement == null)
				throw 'Direct enum throw "${control.id}" refers to missing runtime requirement "$requirementId".';
			final source = requiredObject(requirement, "source");
			final subject = requiredObject(requirement, "subject");
			final roots = requiredStringArray(requirement, "rootModules");
			if (requiredString(requirement, "sourceKind") != "haxe-expression"
				|| requiredString(requirement, "sourceId") != control.id
				|| requiredString(source, "file") != control.sourceFile
				|| requiredInt(source, "min") != control.sourceMin
				|| requiredInt(source, "max") != control.sourceMax
				|| requiredString(requirement, "semanticCapability") != "haxe-enum-dynamic-box"
				|| requiredString(requirement, "cause") != "lowering-decision"
				|| requiredString(requirement, "decisionId") != control.id
				|| requiredString(subject, "kind") != "haxe-type"
				|| requiredString(subject, "id") != enumPayload.inputSemanticTypeId
				|| requiredString(requirement, "implementationFeature") != "haxe-enum-dynamic-box-v1"
				|| roots.length != 1
				|| roots[0] != "HxEnum"
				|| requiredStringArray(requirement, "profileEligibility").join(",") != control.profileEligibility.join(",")) {
				throw 'Direct enum throw "${control.id}" runtime requirement "$requirementId" disagrees with its sealed HxEnum dependency.';
			}
			referenced.set(requirementId, true);
		}
		for (decision in representation.decisions) {
			final expectedStringProofId = decision.domain == "array-element" ? "nullable-string-array-element-carrier-v1" : "nullable-string-runtime-sentinel-carrier-v1";
			final selectsExactStringSentinel = decision.boxingPolicy == "nullable-string-carrier"
				|| decision.proofId == "nullable-string-runtime-sentinel-carrier-v1"
				|| decision.proofId == "nullable-string-array-element-carrier-v1";
			if (!selectsExactStringSentinel)
				continue;
			if (decision.semanticTypeId != "String"
				|| decision.carrierTypeId != "string"
				|| decision.nullPolicy != "runtime-sentinel"
				|| decision.boxingPolicy != "nullable-string-carrier"
				|| decision.implicitDefaultPolicy != "runtime-null-sentinel"
				|| decision.proofId != expectedStringProofId) {
				throw 'Representation decision "${decision.id}" does not match the sealed exact String null-sentinel contract.';
			}
			final requirementId = decision.id + ":runtime:haxe-string-null-sentinel";
			final requirement = requirements.get(requirementId);
			if (requirement == null)
				throw 'Representation decision "${decision.id}" refers to missing runtime requirement "$requirementId".';
			final subject = requiredObject(requirement, "subject");
			final roots = requiredStringArray(requirement, "rootModules");
			if (requiredString(requirement, "sourceKind") != "representation-decision"
				|| requiredString(requirement, "sourceId") != decision.id + "@" + decision.revision
				|| requiredString(requirement, "semanticCapability") != "haxe-string-null-sentinel"
				|| requiredString(requirement, "cause") != "representation-decision"
				|| requiredString(requirement, "decisionId") != decision.id
				|| requiredString(subject, "kind") != "haxe-type"
				|| requiredString(subject, "id") != "String"
				|| requiredString(requirement, "implementationFeature") != "haxe-string-null-sentinel-v1"
				|| roots.length != 1
				|| roots[0] != "HxString") {
				throw 'Representation decision "${decision.id}" runtime requirement "$requirementId" does not match the sealed exact String dependency.';
			}
			referenced.set(requirementId, true);
		}
		for (operation in anonymousOperations) {
			final compoundWrite = operation.kind == "compound-write-field";
			if (operation.runtimeRequirementIds.length != (compoundWrite ? 2 : 1))
				throw 'Anonymous operation "${operation.id}" has the wrong number of runtime requirements for ${operation.kind}.';
			final requirementId = operation.runtimeRequirementIds[0];
			final requirement = requirements.get(requirementId);
			if (requirement == null)
				throw 'Anonymous operation "${operation.id}" refers to missing runtime requirement "$requirementId".';
			final source = requiredObject(requirement, "source");
			final subject = requiredObject(requirement, "subject");
			final roots = requiredStringArray(requirement, "rootModules");
			final expectedSubject = operation.resultSemanticTypeId.length == 0 ? operation.structureId : operation.resultSemanticTypeId;
			if (requirementId != operation.id + ":runtime:haxe-anonymous-structure"
				|| requiredString(requirement, "sourceKind") != "haxe-expression"
				|| requiredString(requirement, "sourceId") != operation.occurrenceId
				|| requiredString(source, "file") != operation.sourceFile
				|| requiredInt(source, "min") != operation.sourceMin
				|| requiredInt(source, "max") != operation.sourceMax
				|| requiredString(requirement, "semanticCapability") != "haxe-anonymous-structure"
				|| requiredString(requirement, "cause") != "lowering-decision"
				|| requiredString(requirement, "decisionId") != operation.id
				|| requiredString(subject, "kind") != "haxe-type"
				|| requiredString(subject, "id") != expectedSubject
				|| requiredString(requirement, "implementationFeature") != "haxe-anonymous-structure-v1"
				|| roots.length != 1
				|| roots[0] != "HxAnon"
				|| requiredStringArray(requirement, "profileEligibility").join(",") != "metal,portable") {
				throw 'Anonymous operation "${operation.id}" runtime requirement "$requirementId" disagrees with its sealed runtime-container decision.';
			}
			referenced.set(requirementId, true);
			if (compoundWrite) {
				final arithmeticId = operation.runtimeRequirementIds[1];
				final arithmetic = requirements.get(arithmeticId);
				if (arithmetic == null)
					throw 'Anonymous compound write "${operation.id}" refers to missing Int32 runtime requirement "$arithmeticId".';
				final arithmeticSource = requiredObject(arithmetic, "source");
				final arithmeticSubject = requiredObject(arithmetic, "subject");
				final arithmeticRoots = requiredStringArray(arithmetic, "rootModules");
				if (arithmeticId != operation.id + ":runtime:haxe-int32-add"
					|| requiredString(arithmetic, "sourceKind") != "haxe-expression"
					|| requiredString(arithmetic, "sourceId") != operation.occurrenceId
					|| requiredString(arithmeticSource, "file") != operation.sourceFile
					|| requiredInt(arithmeticSource, "min") != operation.sourceMin
					|| requiredInt(arithmeticSource, "max") != operation.sourceMax
					|| requiredString(arithmetic, "semanticCapability") != "haxe-int32-add"
					|| requiredString(arithmetic, "cause") != "lowering-decision"
					|| requiredString(arithmetic, "decisionId") != operation.id
					|| requiredString(arithmeticSubject, "kind") != "haxe-type"
					|| requiredString(arithmeticSubject, "id") != operation.fieldSemanticTypeId
					|| requiredString(arithmetic, "implementationFeature") != "haxe-int32-arithmetic-v1"
					|| arithmeticRoots.length != 1
					|| arithmeticRoots[0] != "HxInt"
					|| requiredStringArray(arithmetic, "profileEligibility").join(",") != "metal,portable") {
					throw 'Anonymous compound write "${operation.id}" runtime requirement "$arithmeticId" disagrees with its sealed Int32 addition decision.';
				}
				referenced.set(arithmeticId, true);
			}
		}
		for (field in structuralFields) {
			final tupleProjection = field.operation == "project-tuple-key" || field.operation == "project-tuple-value";
			if (tupleProjection) {
				if (field.runtimeRequirementIds.length != 0
					|| field.runtimeModule != "Stdlib"
					|| (field.operation == "project-tuple-key" ? field.runtimeOperation != "fst" : field.runtimeOperation != "snd"))
					throw 'Structural field decision "${field.id}" has an invalid Stdlib tuple projection.';
				continue;
			}
			final iteratorMethod = field.operation == "capture-iterator-method";
			final capability = iteratorMethod ? "haxe-iterator" : "haxe-structural-field";
			final requirementId = field.id + ":runtime:" + capability;
			if (field.runtimeRequirementIds.length != 1 || field.runtimeRequirementIds[0] != requirementId)
				throw 'Structural field decision "${field.id}" has the wrong runtime requirement identity.';
			final requirement = requirements.get(requirementId);
			if (requirement == null)
				throw 'Structural field decision "${field.id}" refers to missing runtime requirement "$requirementId".';
			final source = requiredObject(requirement, "source");
			final subject = requiredObject(requirement, "subject");
			final roots = requiredStringArray(requirement, "rootModules");
			final expectedFeature = iteratorMethod ? "haxe-iterator-v1" : "haxe-anonymous-structure-v1";
			if (requiredString(requirement, "sourceKind") != "haxe-expression"
				|| requiredString(requirement, "sourceId") != field.id
				|| requiredString(source, "file") != field.sourceFile
				|| requiredInt(source, "min") != field.sourceMin
				|| requiredInt(source, "max") != field.sourceMax
				|| requiredString(requirement, "semanticCapability") != capability
				|| requiredString(requirement, "cause") != "lowering-decision"
				|| requiredString(requirement, "decisionId") != field.id
				|| requiredString(subject, "kind") != "haxe-type"
				|| requiredString(subject, "id") != field.receiverSemanticTypeId
				|| requiredString(requirement, "implementationFeature") != expectedFeature
				|| roots.length != 1
				|| roots[0] != field.runtimeModule
				|| requiredStringArray(requirement, "profileEligibility").join(",") != "metal,portable") {
				throw 'Structural field decision "${field.id}" runtime requirement "$requirementId" disagrees with its sealed typed operation.';
			}
			referenced.set(requirementId, true);
		}
		for (conversion in iMapInterfaceConversions) {
			for (capability in conversion.runtimeCapabilities) {
				final requirementId = conversion.id + ":runtime:" + capability;
				final requirement = requirements.get(requirementId);
				if (requirement == null)
					throw 'IMap interface conversion "${conversion.id}" refers to missing runtime requirement "$requirementId".';
				final implementation = ReflaxeOcamlStandardIMapInspection.runtimeImplementation(capability);
				final source = requiredObject(requirement, "source");
				final subject = requiredObject(requirement, "subject");
				final roots = requiredStringArray(requirement, "rootModules");
				if (requiredString(requirement, "sourceKind") != "haxe-expression"
					|| requiredString(requirement, "sourceId") != conversion.id
					|| requiredString(source, "file") != conversion.sourceFile
					|| requiredInt(source, "min") != conversion.sourceMin
					|| requiredInt(source, "max") != conversion.sourceMax
					|| requiredString(requirement, "semanticCapability") != capability
					|| requiredString(requirement, "cause") != "lowering-decision"
					|| requiredString(requirement, "decisionId") != conversion.id
					|| requiredString(subject, "kind") != "haxe-type"
					|| requiredString(subject, "id") != conversion.targetSemanticTypeId
					|| requiredString(requirement, "implementationFeature") != implementation.feature
					|| roots.length != 1
					|| roots[0] != implementation.root
					|| requiredStringArray(requirement, "profileEligibility").join(",") != "metal,portable") {
					throw 'IMap interface conversion "${conversion.id}" runtime requirement "$requirementId" disagrees with its sealed adapter.';
				}
				referenced.set(requirementId, true);
			}
		}
		for (call in calls) {
			final target = call.standardIMapTarget;
			if (target != null)
				for (capability in target.runtimeCapabilities) {
					final requirementId = call.id + ":runtime:" + capability;
					final requirement = requirements.get(requirementId);
					if (requirement == null)
						throw 'Standard IMap call "${call.id}" refers to missing runtime requirement "$requirementId".';
					final implementation = ReflaxeOcamlStandardIMapInspection.runtimeImplementation(capability);
					final source = requiredObject(requirement, "source");
					final subject = requiredObject(requirement, "subject");
					final roots = requiredStringArray(requirement, "rootModules");
					if (requiredString(requirement, "sourceKind") != "haxe-expression"
						|| requiredString(requirement, "sourceId") != call.id
						|| requiredString(source, "file") != call.sourceFile
						|| requiredInt(source, "min") != call.sourceMin
						|| requiredInt(source, "max") != call.sourceMax
						|| requiredString(requirement, "semanticCapability") != capability
						|| requiredString(requirement, "cause") != "lowering-decision"
						|| requiredString(requirement, "decisionId") != call.id
						|| requiredString(subject, "kind") != "haxe-type"
						|| requiredString(subject, "id") != target.receiverSemanticTypeId
						|| requiredString(requirement, "implementationFeature") != implementation.feature
						|| roots.length != 1
						|| roots[0] != implementation.root
						|| requiredStringArray(requirement, "profileEligibility").join(",") != call.profileEligibility.join(",")) {
						throw 'Standard IMap call "${call.id}" runtime requirement "$requirementId" disagrees with its sealed target.';
					}
					referenced.set(requirementId, true);
				}
			final iteratorTarget = call.structuralIteratorTarget;
			if (iteratorTarget != null) {
				final capability = "haxe-iterator";
				final requirementId = call.id + ":runtime:" + capability;
				final requirement = requirements.get(requirementId);
				if (requirement == null)
					throw 'Structural Iterator call "${call.id}" refers to missing runtime requirement "$requirementId".';
				final source = requiredObject(requirement, "source");
				final subject = requiredObject(requirement, "subject");
				final roots = requiredStringArray(requirement, "rootModules");
				if (iteratorTarget.runtimeCapabilities.length != 1
					|| iteratorTarget.runtimeCapabilities[0] != capability
					|| requiredString(requirement, "sourceKind") != "haxe-expression"
					|| requiredString(requirement, "sourceId") != call.id
					|| requiredString(source, "file") != call.sourceFile
					|| requiredInt(source, "min") != call.sourceMin
					|| requiredInt(source, "max") != call.sourceMax
					|| requiredString(requirement, "semanticCapability") != capability
					|| requiredString(requirement, "cause") != "lowering-decision"
					|| requiredString(requirement, "decisionId") != call.id
					|| requiredString(subject, "kind") != "haxe-type"
					|| requiredString(subject, "id") != iteratorTarget.receiverSemanticTypeId
					|| requiredString(requirement, "implementationFeature") != "haxe-iterator-v1"
					|| roots.length != 1
					|| roots[0] != "HxIterator"
					|| requiredStringArray(requirement, "profileEligibility").join(",") != call.profileEligibility.join(",")) {
					throw 'Structural Iterator call "${call.id}" runtime requirement "$requirementId" disagrees with its sealed target.';
				}
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
				"The checked partial report derives its capability and source-kind inventory from this compilation's exact requirements. Some generated runtime uses still have only module-name observations, so they need occurrence-level explanations before whole-program authority is complete."),
			unavailable("native-dependencies", "Native package and source dependencies", "Structured Dune/opam/native-source ownership has not landed."),
			{
				id: "raw-unsafe",
				label: "Whole-program raw and unsafe operation inventory",
				status: lowering.status == "present" ? "partial" : "unavailable",
				reason: lowering.status == "present" ? 'The compiler reports ${lowering.unsafeOperations.length} proof-backed operation${lowering.unsafeOperations.length == 1 ? "" : "s"} for admitted exact nullable-primitive and immutable Dynamic-local crossings, including exact enum boxing; other raw, Obj, and Obj.magic uses are not yet inventoried.' : "The lowering report that owns the admitted local-carrier slices is not available."
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
				'[PASS] Program representation registry: ${value.decisions.length} decision${value.decisions.length == 1 ? "" : "s"} and ${value.representedArrays.length} represented-array descriptor${value.representedArrays.length == 1 ? "" : "s"} (${value.scope}).';
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
			anonymousStructureRevision: null,
			anonymousStructures: [],
			anonymousStructureOperations: [],
			structuralFieldRevision: null,
			structuralFields: [],
			iMapInterfaceRevision: null,
			iMapInterfaceConversions: [],
			iMapInterfaceCalls: [],
			localConversionRevision: null,
			localConversions: [],
			containerElementRequiredConversionRevision: null,
			containerElementRequiredConversionIds: [],
			containerElementConversionRevision: null,
			containerElementConversions: [],
			unsafeOperationCompleteness: null,
			unsafeOperationRevision: null,
			unsafeOperations: [],
			callRevision: null,
			calls: [],
			callableBoundaries: [],
			reflectCompareRevision: null,
			reflectCompare: [],
			functionResultBoundaryRevision: null,
			functionResultBoundaries: [],
			controlRevision: null,
			controls: [],
			controlCatchRevision: null,
			controlCatches: [],
			controlTargetRevision: null,
			controlTargets: [],
			controlAdmissionRevision: null,
			controlAdmissions: [],
			arrayLiteralProducerModel: null,
			arrayLiteralProducerRevision: null,
			arrayLiteralProducers: [],
			staticStorageRevision: null,
			staticStorage: [],
			scope: "typed-place-anonymous-object-call-and-function-loop-throw-catch-control-families",
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
			representedArrayModel: null,
			representedArrayRevision: null,
			representedArrays: [],
			scope: "exact-int-bool-int64-nullable-string-field-defaults-direct-simple-assignment-represented-array-locals-monomorphic-class-dynamic-internal-v15",
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
