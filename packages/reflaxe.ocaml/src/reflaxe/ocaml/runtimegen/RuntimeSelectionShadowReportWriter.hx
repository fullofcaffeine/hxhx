package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime || eval)
import haxe.Json;
import haxe.crypto.Sha256;
#if macro
import reflaxe.output.OutputManager;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestBuilder;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactKind;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactOwner;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactSourceKind;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactStability;
#end
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.RuntimeSourceManifestModel.RuntimeSourceManifestSnapshot;
import reflaxe.ocaml.runtimegen.RuntimeSourceManifestModel.RuntimeSourceModule;

/** One runtime module and the reasons it enters a selection closure. **/
typedef RuntimeSelectionReason = {
	final module:String;
	final reasons:Array<String>;
}

/** One manifest-checked source file selected for the generated OCaml project. **/
typedef RuntimeSelectionShadowSourceFile = {
	final module:String;
	final path:String;
	final sha256:String;
	final bytes:Int;
}

/** One reason present on only one side of the shadow comparison. **/
typedef RuntimeSelectionShadowReasonDifference = {
	final module:String;
	final reason:String;
}

/** One source path whose checked content identity differs between selections. **/
typedef RuntimeSelectionShadowChangedSource = {
	final module:String;
	final path:String;
	final currentSha256:String;
	final requirementsOnlySha256:String;
	final currentBytes:Int;
	final requirementsOnlyBytes:Int;
}

/** A normalized selection: direct roots, dependency closure, source bytes, and reasons. **/
typedef RuntimeSelectionShadowSnapshot = {
	final roots:Array<String>;
	final closureModules:Array<String>;
	final sourceFiles:Array<RuntimeSelectionShadowSourceFile>;
	final inclusionReasons:Array<RuntimeSelectionReason>;
	final revision:String;
}

/** Exact differences between today's selection and the requirements-only shadow. **/
typedef RuntimeSelectionShadowDifferences = {
	final currentOnlyRoots:Array<String>;
	final requirementsOnlyRoots:Array<String>;
	final currentOnlyClosureModules:Array<String>;
	final requirementsOnlyClosureModules:Array<String>;
	final currentOnlySourceFiles:Array<RuntimeSelectionShadowSourceFile>;
	final requirementsOnlySourceFiles:Array<RuntimeSelectionShadowSourceFile>;
	final changedSourceFiles:Array<RuntimeSelectionShadowChangedSource>;
	final currentOnlyReasons:Array<RuntimeSelectionShadowReasonDifference>;
	final requirementsOnlyReasons:Array<RuntimeSelectionShadowReasonDifference>;
}

/** Observation-only comparison written next to the authoritative runtime reports. **/
typedef RuntimeSelectionShadowReport = {
	final schemaVersion:Int;
	final model:String;
	final reportRevision:String;
	final authorityStatus:String;
	final profile:String;
	final runtimeMode:String;
	final selectionMode:String;
	final requirementRevision:String;
	final runtimeSourceRevision:String;
	final sourceSelectionStatus:String;
	final exactComparisonStatus:String;
	final currentSelection:RuntimeSelectionShadowSnapshot;
	final requirementsOnlySelection:RuntimeSelectionShadowSnapshot;
	final differences:RuntimeSelectionShadowDifferences;
	final message:String;
}

private typedef RuntimeSelectionShadowPayload = {
	final schemaVersion:Int;
	final model:String;
	final authorityStatus:String;
	final profile:String;
	final runtimeMode:String;
	final selectionMode:String;
	final requirementRevision:String;
	final runtimeSourceRevision:String;
	final sourceSelectionStatus:String;
	final exactComparisonStatus:String;
	final currentSelection:RuntimeSelectionShadowSnapshot;
	final requirementsOnlySelection:RuntimeSelectionShadowSnapshot;
	final differences:RuntimeSelectionShadowDifferences;
	final message:String;
}

/**
	Compares runtime packaging with a requirements-only selection without changing output.

	"Requirements-only" means that direct roots come only from the sealed semantic
	requirement records. Their dependencies and source hashes still come from the checked
	runtime manifest. "Shadow" means the comparison is evidence only: the current compiler
	selection remains authoritative and its files are still the ones copied into the project.
**/
class RuntimeSelectionShadowReportWriter {
	public static inline final FILE_NAME = "ocaml_runtime_selection_shadow_report.json";
	public static inline final MODEL = "requirements-only-runtime-selection-shadow";
	public static inline final SCHEMA_VERSION = 1;

	/** Builds a deterministic comparison without writing files or changing selection. **/
	public static function build(profile:String, runtimeMode:String, selectionMode:String, requirementRevision:String, allowTooling:Bool,
			sourceManifest:RuntimeSourceManifestSnapshot, requirements:Array<OcamlRuntimeRequirement>, currentRoots:Array<String>,
			currentEntries:Array<RuntimeSourceModule>, currentReasons:Array<RuntimeSelectionReason>):RuntimeSelectionShadowReport {
		if (runtimeMode != "full" && runtimeMode != "selective")
			throw 'Requirements-only runtime selection received unsupported runtime mode "$runtimeMode".';
		if (selectionMode == null || selectionMode.length == 0)
			throw "Requirements-only runtime selection requires the current selection-mode identity.";
		if (!~/^sha256:[0-9a-f]{64}$/.match(requirementRevision))
			throw "Requirements-only runtime selection received an invalid requirement revision.";
		final normalizedRequirements = requirements == null ? [] : requirements.copy();
		normalizedRequirements.sort((left, right) -> compareStrings(left.id, right.id));
		final seenRequirementIds:Map<String, Bool> = [];
		final requirementRootSet:Map<String, Bool> = [];
		final requirementsReasonMap:Map<String, Map<String, Bool>> = [];
		for (requirement in normalizedRequirements) {
			if (seenRequirementIds.exists(requirement.id))
				throw 'Requirements-only runtime selection repeats requirement identity "${requirement.id}".';
			seenRequirementIds.set(requirement.id, true);
			if (!requirement.profileEligibility.contains(profile))
				throw 'Requirements-only runtime selection requirement "${requirement.id}" is not eligible for the "$profile" profile.';
			for (root in requirement.rootModules) {
				requirementRootSet.set(root, true);
				addReason(requirementsReasonMap, root, "requirement:" + requirement.id);
			}
		}

		final normalizedCurrentRoots = uniqueSorted(currentRoots == null ? [] : currentRoots, "current runtime roots");
		final requirementRoots = mapKeysSorted(requirementRootSet);
		final resolvedCurrent = RuntimeSourceManifest.resolveClosure(sourceManifest, normalizedCurrentRoots, profile, allowTooling);
		final normalizedCurrentEntries = normalizeEntries(currentEntries == null ? [] : currentEntries);
		assertSameEntries(resolvedCurrent, normalizedCurrentEntries);
		final requirementsOnlyEntries = RuntimeSourceManifest.resolveClosure(sourceManifest, requirementRoots, profile, allowTooling);
		addDependencyReasons(requirementsReasonMap, requirementsOnlyEntries);

		final currentSelection = snapshot(normalizedCurrentRoots, normalizedCurrentEntries, currentReasons == null ? [] : currentReasons);
		final requirementsOnlySelection = snapshot(requirementRoots, requirementsOnlyEntries,
			reasonsForModules(requirementsReasonMap, [for (entry in requirementsOnlyEntries) entry.module]));
		final differences = compare(currentSelection, requirementsOnlySelection);
		final sourceSelectionMatches = differences.currentOnlyClosureModules.length == 0
			&& differences.requirementsOnlyClosureModules.length == 0
			&& differences.currentOnlySourceFiles.length == 0
			&& differences.requirementsOnlySourceFiles.length == 0
			&& differences.changedSourceFiles.length == 0;
		final exactComparisonMatches = sourceSelectionMatches
			&& differences.currentOnlyRoots.length == 0
			&& differences.requirementsOnlyRoots.length == 0
			&& differences.currentOnlyReasons.length == 0
			&& differences.requirementsOnlyReasons.length == 0;
		final payload:RuntimeSelectionShadowPayload = {
			schemaVersion: SCHEMA_VERSION,
			model: MODEL,
			authorityStatus: "observation-only",
			profile: profile,
			runtimeMode: runtimeMode,
			selectionMode: selectionMode,
			requirementRevision: requirementRevision,
			runtimeSourceRevision: sourceManifest.revision,
			sourceSelectionStatus: sourceSelectionMatches ? "match" : "mismatch",
			exactComparisonStatus: exactComparisonMatches ? "match" : "mismatch",
			currentSelection: currentSelection,
			requirementsOnlySelection: requirementsOnlySelection,
			differences: differences,
			message: sourceSelectionMatches ? "Explicit requirements select the same checked runtime source bytes for this request. The current compiler selection remains authoritative until the separate occurrence and zero-legacy-inventory hard-cut gates pass." : "Explicit requirements do not yet select the same checked runtime source bytes. This mismatch blocks a hard cut, while the current compiler selection remains authoritative."
		};
		return {
			schemaVersion: payload.schemaVersion,
			model: payload.model,
			reportRevision: "sha256:" + Sha256.encode(Json.stringify(payload)),
			authorityStatus: payload.authorityStatus,
			profile: payload.profile,
			runtimeMode: payload.runtimeMode,
			selectionMode: payload.selectionMode,
			requirementRevision: payload.requirementRevision,
			runtimeSourceRevision: payload.runtimeSourceRevision,
			sourceSelectionStatus: payload.sourceSelectionStatus,
			exactComparisonStatus: payload.exactComparisonStatus,
			currentSelection: payload.currentSelection,
			requirementsOnlySelection: payload.requirementsOnlySelection,
			differences: payload.differences,
			message: payload.message
		};
	}

	/** Writes the comparison as a compiler report that is excluded from source-bundle authority. **/
	#if macro
	public static function write(output:OutputManager, artifacts:OcamlArtifactManifestBuilder, profile:String, runtimeMode:String, selectionMode:String,
			requirementRevision:String, allowTooling:Bool, sourceManifest:RuntimeSourceManifestSnapshot, requirements:Array<OcamlRuntimeRequirement>,
			currentRoots:Array<String>, currentEntries:Array<RuntimeSourceModule>, currentReasons:Array<RuntimeSelectionReason>):RuntimeSelectionShadowReport {
		final report = build(profile, runtimeMode, selectionMode, requirementRevision, allowTooling, sourceManifest, requirements, currentRoots,
			currentEntries, currentReasons);
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
		return report;
	}
	#end

	static function snapshot(roots:Array<String>, entries:Array<RuntimeSourceModule>, reasons:Array<RuntimeSelectionReason>):RuntimeSelectionShadowSnapshot {
		final closureModules = [for (entry in entries) entry.module];
		final sourceFiles = flattenSourceFiles(entries);
		final normalizedReasons = normalizeReasons(reasons, closureModules);
		final payload = {
			roots: roots.copy(),
			closureModules: closureModules,
			sourceFiles: sourceFiles,
			inclusionReasons: normalizedReasons
		};
		return {
			roots: payload.roots,
			closureModules: payload.closureModules,
			sourceFiles: payload.sourceFiles,
			inclusionReasons: payload.inclusionReasons,
			revision: "sha256:" + Sha256.encode(Json.stringify(payload))
		};
	}

	static function compare(current:RuntimeSelectionShadowSnapshot, requirementsOnly:RuntimeSelectionShadowSnapshot):RuntimeSelectionShadowDifferences {
		final currentFiles = filesByIdentity(current.sourceFiles);
		final requirementsFiles = filesByIdentity(requirementsOnly.sourceFiles);
		final currentOnlySourceFiles = new Array<RuntimeSelectionShadowSourceFile>();
		final requirementsOnlySourceFiles = new Array<RuntimeSelectionShadowSourceFile>();
		final changedSourceFiles = new Array<RuntimeSelectionShadowChangedSource>();
		for (file in current.sourceFiles) {
			final other = requirementsFiles.get(sourceIdentity(file));
			if (other == null) {
				currentOnlySourceFiles.push(file);
			} else if (file.sha256 != other.sha256 || file.bytes != other.bytes) {
				changedSourceFiles.push({
					module: file.module,
					path: file.path,
					currentSha256: file.sha256,
					requirementsOnlySha256: other.sha256,
					currentBytes: file.bytes,
					requirementsOnlyBytes: other.bytes
				});
			}
		}
		for (file in requirementsOnly.sourceFiles)
			if (!currentFiles.exists(sourceIdentity(file)))
				requirementsOnlySourceFiles.push(file);

		final currentReasonSet = reasonSet(current.inclusionReasons);
		final requirementsReasonSet = reasonSet(requirementsOnly.inclusionReasons);
		return {
			currentOnlyRoots: onlyIn(current.roots, requirementsOnly.roots),
			requirementsOnlyRoots: onlyIn(requirementsOnly.roots, current.roots),
			currentOnlyClosureModules: onlyIn(current.closureModules, requirementsOnly.closureModules),
			requirementsOnlyClosureModules: onlyIn(requirementsOnly.closureModules, current.closureModules),
			currentOnlySourceFiles: currentOnlySourceFiles,
			requirementsOnlySourceFiles: requirementsOnlySourceFiles,
			changedSourceFiles: changedSourceFiles,
			currentOnlyReasons: reasonDifferences(current.inclusionReasons, requirementsReasonSet),
			requirementsOnlyReasons: reasonDifferences(requirementsOnly.inclusionReasons, currentReasonSet)
		};
	}

	static function normalizeEntries(entries:Array<RuntimeSourceModule>):Array<RuntimeSourceModule> {
		final out = entries.copy();
		out.sort((left, right) -> compareStrings(left.module, right.module));
		for (index in 1...out.length)
			if (out[index - 1].module == out[index].module)
				throw 'Current runtime selection repeats module "${out[index].module}".';
		return out;
	}

	static function assertSameEntries(expected:Array<RuntimeSourceModule>, actual:Array<RuntimeSourceModule>):Void {
		if (Json.stringify(expected) != Json.stringify(actual))
			throw "Current runtime roots do not reproduce the authoritative selected runtime entries.";
	}

	static function flattenSourceFiles(entries:Array<RuntimeSourceModule>):Array<RuntimeSelectionShadowSourceFile> {
		final out = new Array<RuntimeSelectionShadowSourceFile>();
		for (entry in entries)
			for (file in entry.files)
				out.push({
					module: entry.module,
					path: file.path,
					sha256: file.sha256,
					bytes: file.bytes
				});
		out.sort((left, right) -> {
			final byModule = compareStrings(left.module, right.module);
			return byModule != 0 ? byModule : compareStrings(left.path, right.path);
		});
		return out;
	}

	static function normalizeReasons(reasons:Array<RuntimeSelectionReason>, closureModules:Array<String>):Array<RuntimeSelectionReason> {
		final closureSet:Map<String, Bool> = [for (moduleName in closureModules) moduleName => true];
		final reasonMap:Map<String, Map<String, Bool>> = [];
		for (entry in reasons) {
			if (!closureSet.exists(entry.module))
				throw 'Runtime selection reason names unselected module "${entry.module}".';
			for (reason in entry.reasons)
				addReason(reasonMap, entry.module, reason);
		}
		return reasonsForModules(reasonMap, closureModules);
	}

	static function reasonsForModules(reasonMap:Map<String, Map<String, Bool>>, modules:Array<String>):Array<RuntimeSelectionReason> {
		final out = new Array<RuntimeSelectionReason>();
		for (moduleName in modules) {
			final reasonSet = reasonMap.get(moduleName);
			final reasons = reasonSet == null ? [] : mapKeysSorted(reasonSet);
			out.push({module: moduleName, reasons: reasons});
		}
		return out;
	}

	static function addDependencyReasons(reasonMap:Map<String, Map<String, Bool>>, entries:Array<RuntimeSourceModule>):Void {
		final selected:Map<String, Bool> = [for (entry in entries) entry.module => true];
		for (entry in entries)
			for (dependency in entry.dependencies)
				if (selected.exists(dependency))
					addReason(reasonMap, dependency, "transitive:" + entry.module);
	}

	static function addReason(reasonMap:Map<String, Map<String, Bool>>, moduleName:String, reason:String):Void {
		if (moduleName == null || moduleName.length == 0 || reason == null || reason.length == 0)
			throw "Runtime selection reasons must name a module and a reason.";
		var reasonSet = reasonMap.get(moduleName);
		if (reasonSet == null) {
			reasonSet = [];
			reasonMap.set(moduleName, reasonSet);
		}
		reasonSet.set(reason, true);
	}

	static function uniqueSorted(values:Array<String>, label:String):Array<String> {
		final seen:Map<String, Bool> = [];
		for (value in values) {
			if (value == null || value.length == 0)
				throw '$label contains an empty value.';
			if (seen.exists(value))
				throw '$label repeats "$value".';
			seen.set(value, true);
		}
		return mapKeysSorted(seen);
	}

	static function onlyIn(left:Array<String>, right:Array<String>):Array<String> {
		final rightSet:Map<String, Bool> = [for (value in right) value => true];
		return [for (value in left) if (!rightSet.exists(value)) value];
	}

	static function filesByIdentity(files:Array<RuntimeSelectionShadowSourceFile>):Map<String, RuntimeSelectionShadowSourceFile> {
		final out:Map<String, RuntimeSelectionShadowSourceFile> = [];
		for (file in files)
			out.set(sourceIdentity(file), file);
		return out;
	}

	static function sourceIdentity(file:RuntimeSelectionShadowSourceFile):String {
		return file.module + "\t" + file.path;
	}

	static function reasonSet(reasons:Array<RuntimeSelectionReason>):Map<String, Bool> {
		final out:Map<String, Bool> = [];
		for (entry in reasons)
			for (reason in entry.reasons)
				out.set(entry.module + "\t" + reason, true);
		return out;
	}

	static function reasonDifferences(reasons:Array<RuntimeSelectionReason>, other:Map<String, Bool>):Array<RuntimeSelectionShadowReasonDifference> {
		final out = new Array<RuntimeSelectionShadowReasonDifference>();
		for (entry in reasons)
			for (reason in entry.reasons)
				if (!other.exists(entry.module + "\t" + reason))
					out.push({module: entry.module, reason: reason});
		return out;
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
