package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime)
import haxe.Json;
import haxe.crypto.Sha256;
import reflaxe.output.OutputManager;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestBuilder;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactKind;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactOwner;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactSourceKind;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactStability;
import reflaxe.ocaml.OcamlRuntimeMode;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.RuntimeSourceManifestModel.RuntimeSourceManifestSnapshot;
import reflaxe.ocaml.runtimegen.RuntimeSourceManifestModel.RuntimeSourceModule;

private typedef OcamlRuntimeRequirementChain = {
	final requirementId:String;
	final resolvedModules:Array<String>;
}

private typedef OcamlRuntimeRequirementReportPayload = {
	final schemaVersion:Int;
	final model:String;
	final authorityStatus:String;
	final recordedSemanticCapabilities:Array<String>;
	final recordedRequirementSourceKinds:Array<String>;
	final selectionAuthority:String;
	final profile:String;
	final runtimeMode:String;
	final selectionMode:String;
	final requirementRevision:String;
	final runtimeVersion:String;
	final runtimeSourceRevision:String;
	final requirements:Array<OcamlRuntimeRequirement>;
	final requirementChains:Array<OcamlRuntimeRequirementChain>;
	final requirementRootModules:Array<String>;
	final requirementClosureModules:Array<String>;
	final compilerObservationGranularity:String;
	final compilerObservedModules:Array<String>;
	final compilerObservedModulesWithRequirementRoots:Array<String>;
	final compilerObservedModulesWithoutRequirementRoots:Array<String>;
	final requirementRootsNotCompilerObserved:Array<String>;
	final selectedModules:Array<String>;
	final runtimeSources:Array<RuntimeSourceModule>;
	final message:String;
}

/**
	Writes the compiler-decision-to-runtime explanation chain for migrated families.

	The report is intentionally explicit about partial coverage. It proves that
	each recorded need resolves through the checked runtime catalog, while keeping
	compiler observations visible until every compiler family records why it needs
	each runtime helper.
**/
class OcamlRuntimeRequirementReportWriter {
	public static inline final FILE_NAME = "ocaml_runtime_requirement_report.json";
	public static inline final MODEL = "recorded-ocaml-runtime-requirements";
	public static inline final SCHEMA_VERSION = 5;

	/** Resolves, cross-checks, and writes the current partial requirement ledger. **/
	public static function write(output:OutputManager, artifacts:OcamlArtifactManifestBuilder, profile:String, allowTooling:Bool,
			runtimeMode:OcamlRuntimeMode, selectionMode:String, sourceManifest:RuntimeSourceManifestSnapshot, requirements:Array<OcamlRuntimeRequirement>,
			requirementRevision:String, compilerObservedModules:Array<String>, selectedEntries:Array<RuntimeSourceModule>):Void {
		if (!~/^sha256:[0-9a-f]{64}$/.match(requirementRevision))
			throw "OCaml runtime requirement report received an invalid requirement revision.";
		final sortedRequirements = requirements.copy();
		sortedRequirements.sort((left, right) -> compareStrings(left.id, right.id));
		final seenRequirements:Map<String, Bool> = [];
		final requirementRoots:Map<String, Bool> = [];
		final requirementClosure:Map<String, Bool> = [];
		final chains = new Array<OcamlRuntimeRequirementChain>();
		for (requirement in sortedRequirements) {
			if (seenRequirements.exists(requirement.id))
				throw 'OCaml runtime requirement report repeats identity "${requirement.id}".';
			seenRequirements.set(requirement.id, true);
			if (!requirement.profileEligibility.contains(profile))
				throw 'OCaml runtime requirement "${requirement.id}" is not eligible for the "$profile" profile.';
			for (root in requirement.rootModules)
				requirementRoots.set(root, true);
			final closure = RuntimeSourceManifest.resolveClosure(sourceManifest, requirement.rootModules, profile, allowTooling);
			final resolvedModules = [for (entry in closure) entry.module];
			for (moduleName in resolvedModules)
				requirementClosure.set(moduleName, true);
			chains.push({requirementId: requirement.id, resolvedModules: resolvedModules});
		}
		final recordedSemanticCapabilities = uniqueValuesSorted([for (requirement in sortedRequirements) requirement.semanticCapability]);
		final recordedRequirementSourceKinds = uniqueValuesSorted([for (requirement in sortedRequirements) Std.string(requirement.sourceKind)]);
		final requirementRootModules = mapKeysSorted(requirementRoots);
		final requirementClosureModules = mapKeysSorted(requirementClosure);
		final observed = uniqueSorted(compilerObservedModules, "compiler-observed runtime modules");
		final observedSet:Map<String, Bool> = [for (moduleName in observed) moduleName => true];
		final selectedModules = [for (entry in selectedEntries) entry.module];
		final selectedSet:Map<String, Bool> = [for (moduleName in selectedModules) moduleName => true];
		for (moduleName in requirementClosureModules)
			if (!selectedSet.exists(moduleName))
				throw 'Recorded runtime requirement closure contains "$moduleName", but runtime packaging did not select it.';
		final omittedObservedModules = [for (moduleName in observed) if (!selectedSet.exists(moduleName)) moduleName];
		if (omittedObservedModules.length > 0) {
			final omittedLabel = omittedObservedModules.join(", ");
			throw 'Runtime packaging omitted compiler-observed module${omittedObservedModules.length == 1 ? "" : "s"}: $omittedLabel. Enable automatic runtime discovery or add every named module to -D ocaml_runtime_modules.';
		}
		final compilerObservedModulesWithRequirementRoots = [for (moduleName in observed) if (requirementRoots.exists(moduleName)) moduleName];
		final compilerObservedModulesWithoutRequirementRoots = [
			for (moduleName in observed)
				if (!requirementRoots.exists(moduleName)) moduleName
		];
		final requirementRootsNotCompilerObserved = [
			for (moduleName in requirementRootModules)
				if (!observedSet.exists(moduleName)) moduleName
		];
		final runtimeSources = [
			for (entry in sourceManifest.modules)
				if (requirementClosure.exists(entry.module)) entry
		];
		final selectionAuthority = runtimeMode == OcamlRuntimeMode.Full ? "explicit-full-with-recorded-requirement-audit-v2" : "recorded-requirements-with-compiler-observation-check-v2";
		final payload:OcamlRuntimeRequirementReportPayload = {
			schemaVersion: SCHEMA_VERSION,
			model: MODEL,
			authorityStatus: "partial",
			recordedSemanticCapabilities: recordedSemanticCapabilities,
			recordedRequirementSourceKinds: recordedRequirementSourceKinds,
			selectionAuthority: selectionAuthority,
			profile: profile,
			runtimeMode: OcamlRuntimeMode.toDefineValue(runtimeMode),
			selectionMode: selectionMode,
			requirementRevision: requirementRevision,
			runtimeVersion: sourceManifest.runtimeVersion,
			runtimeSourceRevision: sourceManifest.revision,
			requirements: sortedRequirements,
			requirementChains: chains,
			requirementRootModules: requirementRootModules,
			requirementClosureModules: requirementClosureModules,
			compilerObservationGranularity: "module-name-only",
			compilerObservedModules: observed,
			compilerObservedModulesWithRequirementRoots: compilerObservedModulesWithRequirementRoots,
			compilerObservedModulesWithoutRequirementRoots: compilerObservedModulesWithoutRequirementRoots,
			requirementRootsNotCompilerObserved: requirementRootsNotCompilerObserved,
			selectedModules: selectedModules,
			runtimeSources: runtimeSources,
			message: "The semantic capability and source-kind lists are derived from this compilation's sealed runtime requirements. Authority remains partial because compiler observations still contain module names rather than individual use sites, so a recorded root does not prove that every generated use of that module has its own explanation."
		};
		final report = {
			schemaVersion: payload.schemaVersion,
			model: payload.model,
			reportRevision: "sha256:" + Sha256.encode(Json.stringify(payload)),
			authorityStatus: payload.authorityStatus,
			recordedSemanticCapabilities: payload.recordedSemanticCapabilities,
			recordedRequirementSourceKinds: payload.recordedRequirementSourceKinds,
			selectionAuthority: payload.selectionAuthority,
			profile: payload.profile,
			runtimeMode: payload.runtimeMode,
			selectionMode: payload.selectionMode,
			requirementRevision: payload.requirementRevision,
			runtimeVersion: payload.runtimeVersion,
			runtimeSourceRevision: payload.runtimeSourceRevision,
			requirementCount: payload.requirements.length,
			requirements: payload.requirements,
			requirementChains: payload.requirementChains,
			requirementRootModules: payload.requirementRootModules,
			requirementClosureModules: payload.requirementClosureModules,
			compilerObservationGranularity: payload.compilerObservationGranularity,
			compilerObservedModules: payload.compilerObservedModules,
			compilerObservedModulesWithRequirementRoots: payload.compilerObservedModulesWithRequirementRoots,
			compilerObservedModulesWithoutRequirementRoots: payload.compilerObservedModulesWithoutRequirementRoots,
			requirementRootsNotCompilerObserved: payload.requirementRootsNotCompilerObserved,
			selectedModules: payload.selectedModules,
			runtimeSources: payload.runtimeSources,
			message: payload.message
		};
		output.saveFile(FILE_NAME, Json.stringify(report, null, "  ") + "\n");
		artifacts.record({
			path: FILE_NAME,
			kind: OcamlArtifactKind.CompilerReport,
			owner: OcamlArtifactOwner.RuntimePackaging,
			sourceKind: OcamlArtifactSourceKind.Generated,
			sourcePath: null,
			license: "generated-output",
			profileEligibility: ["portable", "metal"],
			stability: OcamlArtifactStability.Stable,
			includeInSourceBundle: false
		});
	}

	static function uniqueSorted(values:Array<String>, label:String):Array<String> {
		final seen:Map<String, Bool> = [];
		for (value in values) {
			if (seen.exists(value))
				throw '$label repeats "$value".';
			seen.set(value, true);
		}
		return mapKeysSorted(seen);
	}

	static function uniqueValuesSorted(values:Array<String>):Array<String> {
		final seen:Map<String, Bool> = [];
		for (value in values)
			seen.set(value, true);
		return mapKeysSorted(seen);
	}

	static function mapKeysSorted(values:Map<String, Bool>):Array<String> {
		final out = [for (value in values.keys()) value];
		out.sort(compareStrings);
		return out;
	}

	static function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}
}
#end
