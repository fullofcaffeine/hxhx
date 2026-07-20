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
	final coveredFamilies:Array<String>;
	final selectionAuthority:String;
	final profile:String;
	final runtimeMode:String;
	final selectionMode:String;
	final requirementRevision:String;
	final runtimeVersion:String;
	final runtimeSourceRevision:String;
	final requirements:Array<OcamlRuntimeRequirement>;
	final requirementChains:Array<OcamlRuntimeRequirementChain>;
	final semanticRootModules:Array<String>;
	final semanticClosureModules:Array<String>;
	final syntaxObservedModules:Array<String>;
	final explainedSyntaxModules:Array<String>;
	final unexplainedSyntaxModules:Array<String>;
	final semanticRootsMissingFromSyntax:Array<String>;
	final selectedModules:Array<String>;
	final runtimeSources:Array<RuntimeSourceModule>;
	final message:String;
}

/**
	Writes the source-to-runtime explanation chain for migrated semantic families.

	The report is intentionally explicit about partial coverage. It proves that
	each recorded need resolves through the checked runtime catalog, while keeping
	generated-syntax observations visible until every compiler family records its
	own source-level reason.
**/
class OcamlRuntimeRequirementReportWriter {
	public static inline final FILE_NAME = "ocaml_runtime_requirement_report.json";
	public static inline final MODEL = "source-rooted-ocaml-runtime-requirements";
	public static inline final SCHEMA_VERSION = 1;

	/** Resolves, cross-checks, and writes the current partial semantic ledger. **/
	public static function write(output:OutputManager, artifacts:OcamlArtifactManifestBuilder, profile:String, allowTooling:Bool,
			runtimeMode:OcamlRuntimeMode, selectionMode:String, sourceManifest:RuntimeSourceManifestSnapshot, requirements:Array<OcamlRuntimeRequirement>,
			requirementRevision:String, syntaxObservedModules:Array<String>, selectedEntries:Array<RuntimeSourceModule>):Void {
		if (!~/^sha256:[0-9a-f]{64}$/.match(requirementRevision))
			throw "OCaml runtime requirement report received an invalid requirement revision.";
		final sortedRequirements = requirements.copy();
		sortedRequirements.sort((left, right) -> compareStrings(left.id, right.id));
		final seenRequirements:Map<String, Bool> = [];
		final semanticRoots:Map<String, Bool> = [];
		final semanticClosure:Map<String, Bool> = [];
		final chains = new Array<OcamlRuntimeRequirementChain>();
		for (requirement in sortedRequirements) {
			if (seenRequirements.exists(requirement.id))
				throw 'OCaml runtime requirement report repeats identity "${requirement.id}".';
			seenRequirements.set(requirement.id, true);
			if (!requirement.profileEligibility.contains(profile))
				throw 'OCaml runtime requirement "${requirement.id}" is not eligible for the "$profile" profile.';
			for (root in requirement.rootModules)
				semanticRoots.set(root, true);
			final closure = RuntimeSourceManifest.resolveClosure(sourceManifest, requirement.rootModules, profile, allowTooling);
			final resolvedModules = [for (entry in closure) entry.module];
			for (moduleName in resolvedModules)
				semanticClosure.set(moduleName, true);
			chains.push({requirementId: requirement.id, resolvedModules: resolvedModules});
		}
		final semanticRootModules = mapKeysSorted(semanticRoots);
		final semanticClosureModules = mapKeysSorted(semanticClosure);
		final observed = uniqueSorted(syntaxObservedModules, "syntax-observed runtime modules");
		final observedSet:Map<String, Bool> = [for (moduleName in observed) moduleName => true];
		final selectedModules = [for (entry in selectedEntries) entry.module];
		final selectedSet:Map<String, Bool> = [for (moduleName in selectedModules) moduleName => true];
		for (moduleName in semanticClosureModules)
			if (!selectedSet.exists(moduleName))
				throw 'Semantic runtime requirement closure contains "$moduleName", but runtime packaging did not select it.';
		final omittedObservedModules = [for (moduleName in observed) if (!selectedSet.exists(moduleName)) moduleName];
		if (omittedObservedModules.length > 0) {
			final omittedLabel = omittedObservedModules.join(", ");
			throw 'Runtime packaging omitted syntax-observed module${omittedObservedModules.length == 1 ? "" : "s"}: $omittedLabel. Enable automatic runtime discovery or add every named module to -D ocaml_runtime_modules.';
		}
		final explainedSyntaxModules = [for (moduleName in observed) if (semanticRoots.exists(moduleName)) moduleName];
		final unexplainedSyntaxModules = [for (moduleName in observed) if (!semanticRoots.exists(moduleName)) moduleName];
		final semanticRootsMissingFromSyntax = [
			for (moduleName in semanticRootModules)
				if (!observedSet.exists(moduleName)) moduleName
		];
		final runtimeSources = [
			for (entry in sourceManifest.modules)
				if (semanticClosure.exists(entry.module)) entry
		];
		final selectionAuthority = runtimeMode == OcamlRuntimeMode.Full ? "explicit-full-with-source-requirement-audit-v1" : "source-required-with-syntax-consistency-check-v1";
		final payload:OcamlRuntimeRequirementReportPayload = {
			schemaVersion: SCHEMA_VERSION,
			model: MODEL,
			authorityStatus: "partial",
			coveredFamilies: ["typed-place-assignment-and-update"],
			selectionAuthority: selectionAuthority,
			profile: profile,
			runtimeMode: OcamlRuntimeMode.toDefineValue(runtimeMode),
			selectionMode: selectionMode,
			requirementRevision: requirementRevision,
			runtimeVersion: sourceManifest.runtimeVersion,
			runtimeSourceRevision: sourceManifest.revision,
			requirements: sortedRequirements,
			requirementChains: chains,
			semanticRootModules: semanticRootModules,
			semanticClosureModules: semanticClosureModules,
			syntaxObservedModules: observed,
			explainedSyntaxModules: explainedSyntaxModules,
			unexplainedSyntaxModules: unexplainedSyntaxModules,
			semanticRootsMissingFromSyntax: semanticRootsMissingFromSyntax,
			selectedModules: selectedModules,
			runtimeSources: runtimeSources,
			message: "Source-rooted runtime explanations currently cover typed assignment and update lowering. Other generated runtime references remain migration debt."
		};
		final report = {
			schemaVersion: payload.schemaVersion,
			model: payload.model,
			reportRevision: "sha256:" + Sha256.encode(Json.stringify(payload)),
			authorityStatus: payload.authorityStatus,
			coveredFamilies: payload.coveredFamilies,
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
			semanticRootModules: payload.semanticRootModules,
			semanticClosureModules: payload.semanticClosureModules,
			syntaxObservedModules: payload.syntaxObservedModules,
			explainedSyntaxModules: payload.explainedSyntaxModules,
			unexplainedSyntaxModules: payload.unexplainedSyntaxModules,
			semanticRootsMissingFromSyntax: payload.semanticRootsMissingFromSyntax,
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
