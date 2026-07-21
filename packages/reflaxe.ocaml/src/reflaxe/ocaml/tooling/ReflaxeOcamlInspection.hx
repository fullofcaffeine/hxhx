package reflaxe.ocaml.tooling;

import haxe.Json;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import reflaxe.ocaml.tooling.InspectionReport.InspectionGeneratedFiles;
import reflaxe.ocaml.tooling.InspectionReport.InspectionArtifactManifest;
import reflaxe.ocaml.tooling.InspectionReport.InspectionLoweredPlan;
import reflaxe.ocaml.tooling.InspectionReport.InspectionLowering;
import reflaxe.ocaml.tooling.InspectionReport.InspectionRepresentation;
import reflaxe.ocaml.tooling.InspectionReport.InspectionRepresentationDecision;
import reflaxe.ocaml.tooling.InspectionReport.InspectionProfile;
import reflaxe.ocaml.tooling.InspectionReport.InspectionRuntime;
import reflaxe.ocaml.tooling.InspectionReport.InspectionRuntimeReason;
import reflaxe.ocaml.tooling.InspectionReport.InspectionStaticStorageEntry;
import reflaxe.ocaml.tooling.InspectionReport.InspectionUnavailableCapability;

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
			schemaVersion: 5,
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
			unavailable: unavailableCapabilities(),
			summary: {
				valid: errorCount == 0,
				exitCode: errorCount == 0 ? 0 : 1,
				errorCount: errorCount,
				generatedFileCount: generated.files.length,
				artifactEntryCount: artifactManifest.entryCount,
				runtimeModuleCount: runtime.selectedModules.length,
				loweredPlanCount: lowering.plans.length,
				representationDecisionCount: representation.decisions.length,
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
		lines.push("Not available yet (never inferred from generated text):");
		for (capability in report.unavailable) {
			lines.push('  - ${capability.label}: ${capability.reason}');
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
					staticStorageRevision: null,
					staticStorage: [],
					scope: "typed-place-assignment-and-update-family",
					message: "Typed place lowering was not requested. Add -D ocaml_lowering_report to the project HXML and rebuild."
				};
			case Invalid(message):
				loweringFailure(path, message, required);
			case Loaded(value):
				try {
					final version = requiredInt(value, "schemaVersion");
					if (version != 9) {
						throw 'Unsupported lowering report schema $version; expected 9.';
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
						staticStorageRevision: requiredSha256Revision(value, "staticStorageRevision"),
						staticStorage: staticStorage,
						scope: "typed-place-assignment-and-update-family",
						message: 'Typed place report contains ${plans.length} sealed operation${plans.length == 1 ? "" : "s"}, ${staticStorage.length} pre-emission static cell${staticStorage.length == 1 ? "" : "s"}, and $runtimeRequirementCount runtime explanation${runtimeRequirementCount == 1 ? "" : "s"} tied to those Haxe operations; it is not a whole-program IR.'
					};
				} catch (error:Dynamic) {
					loweringFailure(path, Std.string(error), required);
				}
		};
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
		if (scope != "exact-non-null-int-v1")
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
		}
		return {
			status: "present",
			path: path,
			schemaVersion: schemaVersion,
			model: model,
			revision: requiredSha256Revision(value, "representationRevision"),
			decisions: decisions,
			scope: scope,
			message: 'The compiler reported ${decisions.length} program-owned exact-Int carrier decision${decisions.length == 1 ? "" : "s"}; other Haxe types and boundary domains remain outside this first slice.'
		};
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
			mutationPolicy: requiredString(value, "mutationPolicy"),
			boxingPolicy: requiredString(value, "boxingPolicy"),
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

	static function unavailableCapabilities():Array<InspectionUnavailableCapability> {
		return [
			unavailable("semantic-runtime-manifest", "Whole-program runtime requirement ledger",
				"A checked partial report now covers core packaging, the generated type registry, declared static native boundaries, and typed assignments/updates; other compiler paths still need explicit explanations."),
			unavailable("native-dependencies", "Native package and source dependencies", "Structured Dune/opam/native-source ownership has not landed."),
			unavailable("raw-unsafe", "Raw and unsafe operation inventory", "The compiler does not yet emit an owned raw/Obj.magic proof inventory."),
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
			staticStorageRevision: null,
			staticStorage: [],
			scope: "typed-place-assignment-and-update-family",
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
			scope: "exact-non-null-int-v1",
			message: message
		};
	}

	static function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}
}
