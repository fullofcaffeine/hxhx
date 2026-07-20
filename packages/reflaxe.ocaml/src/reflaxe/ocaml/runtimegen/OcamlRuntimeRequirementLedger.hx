package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime || eval)
import haxe.Json;
import haxe.crypto.Sha256;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementCause;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSourceKind;

using StringTools;

/**
	Collects immutable explanations for compatibility-runtime use in one compile.

	Entries are recorded where a target decision is made. Later packaging may read
	the sorted records, but it must not invent or reinterpret their Haxe semantics.
**/
class OcamlRuntimeRequirementLedger {
	public static inline final INT32_ADD = "haxe-int32-add";
	public static inline final ARRAY_ELEMENT_GET = "haxe-array-element-get";
	public static inline final ARRAY_ELEMENT_SET = "haxe-array-element-set";

	var currentProgramRevision:Null<String> = null;
	final byId:Map<String, OcamlRuntimeRequirement> = [];

	public function new() {}

	/** Starts one compile and discards every requirement from the prior program. **/
	public function beginProgram(programRevision:String):Void {
		final revision = required(programRevision, "program revision");
		currentProgramRevision = revision;
		byId.clear();
	}

	/** Records one requirement and rejects reused identities with different facts. **/
	public function record(requirement:OcamlRuntimeRequirement):Void {
		if (currentProgramRevision == null)
			throw "OCaml runtime requirements cannot be recorded before the program revision begins.";
		final normalized = normalize(requirement);
		final existing = byId.get(normalized.id);
		if (existing != null) {
			if (Json.stringify(existing) != Json.stringify(normalized))
				throw 'OCaml runtime requirement identity "${normalized.id}" was reused with different facts.';
			return;
		}
		byId.set(normalized.id, normalized);
	}

	/**
		Expands the closed capability IDs on one sealed place plan into complete
		source-rooted runtime requirements.
	**/
	public function recordPlacePlan(decisionId:String, originId:String, source:OcamlLoweredSourceSpan, subjectTypeId:String,
			requirementIds:Array<String>):Void {
		for (requirementId in requirementIds) {
			final expectedPrefix = originId + ":runtime:";
			if (!requirementId.startsWith(expectedPrefix))
				throw 'Place runtime requirement "$requirementId" is not scoped to origin "$originId".';
			final capability = requirementId.substr(expectedPrefix.length);
			final implementation = placeImplementation(capability);
			record({
				id: requirementId,
				sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
				sourceId: originId,
				source: source,
				semanticCapability: capability,
				cause: OcamlRuntimeRequirementCause.LoweringDecision,
				decisionId: decisionId,
				subjectTypeId: subjectTypeId,
				implementationFeature: implementation.feature,
				rootModules: [implementation.module],
				profileEligibility: ["metal", "portable"],
				explanation: implementation.explanation
			});
		}
	}

	/** Returns immutable records in stable identity order. **/
	public function requirementsSorted():Array<OcamlRuntimeRequirement> {
		final out = [for (entry in byId) entry];
		out.sort((left, right) -> compareStrings(left.id, right.id));
		return out;
	}

	/** Returns the deduplicated runtime roots selected by recorded decisions. **/
	public function rootModulesSorted():Array<String> {
		final roots:Map<String, Bool> = [];
		for (entry in byId)
			for (moduleName in entry.rootModules)
				roots.set(moduleName, true);
		final out = [for (moduleName in roots.keys()) moduleName];
		out.sort(compareStrings);
		return out;
	}

	/** Computes a path-stable revision for reports and cache keys. **/
	public function revision():String {
		if (currentProgramRevision == null)
			throw "OCaml runtime requirement revision is unavailable before the program revision begins.";
		return "sha256:" + Sha256.encode(currentProgramRevision + "\n" + Json.stringify(requirementsSorted()));
	}

	static function placeImplementation(capability:String):{feature:String, module:String, explanation:String} {
		return switch (capability) {
			case INT32_ADD:
				{
					feature: "haxe-int32-arithmetic-v1",
					module: "HxInt",
					explanation: "Haxe Int addition has defined 32-bit overflow behavior, so generated OCaml uses the checked HxInt operation."
				};
			case ARRAY_ELEMENT_GET:
				{
					feature: "haxe-array-element-access-v1",
					module: "HxArray",
					explanation: "Reading a Haxe array element must preserve Haxe array bounds, storage, and identity behavior."
				};
			case ARRAY_ELEMENT_SET:
				{
					feature: "haxe-array-element-access-v1",
					module: "HxArray",
					explanation: "Writing a Haxe array element must update the original growable Haxe array using its checked storage contract."
				};
			case _:
				throw 'Unknown place runtime capability "$capability".';
		}
	}

	static function normalize(requirement:OcamlRuntimeRequirement):OcamlRuntimeRequirement {
		if (requirement == null)
			throw "OCaml runtime requirement must not be null.";
		final id = required(requirement.id, "identity");
		final sourceId = required(requirement.sourceId, 'source identity for "$id"');
		final decisionId = required(requirement.decisionId, 'decision identity for "$id"');
		final semanticCapability = required(requirement.semanticCapability, 'semantic capability for "$id"');
		final subjectTypeId = required(requirement.subjectTypeId, 'subject type for "$id"');
		final implementationFeature = required(requirement.implementationFeature, 'implementation feature for "$id"');
		final explanation = required(requirement.explanation, 'explanation for "$id"');
		if (requirement.source == null || requirement.source.min < 0 || requirement.source.max < requirement.source.min)
			throw 'OCaml runtime requirement "$id" has an invalid source span.';
		final rootModules = normalizedTokens(requirement.rootModules, 'root modules for "$id"');
		if (rootModules.length == 0)
			throw 'OCaml runtime requirement "$id" must name at least one root module.';
		for (moduleName in rootModules)
			if (!~/^[A-Za-z][A-Za-z0-9_]*$/.match(moduleName))
				throw 'OCaml runtime requirement "$id" has invalid root module "$moduleName".';
		final profiles = normalizedTokens(requirement.profileEligibility, 'profiles for "$id"');
		if (profiles.length == 0)
			throw 'OCaml runtime requirement "$id" must name at least one eligible profile.';
		for (profile in profiles)
			if (profile != "metal" && profile != "portable")
				throw 'OCaml runtime requirement "$id" has unsupported profile "$profile".';
		return {
			id: id,
			sourceKind: requirement.sourceKind,
			sourceId: sourceId,
			source: {
				file: OcamlLoweredOrigin.normalizeSourcePath(requirement.source.file),
				min: requirement.source.min,
				max: requirement.source.max
			},
			semanticCapability: semanticCapability,
			cause: requirement.cause,
			decisionId: decisionId,
			subjectTypeId: subjectTypeId,
			implementationFeature: implementationFeature,
			rootModules: rootModules,
			profileEligibility: profiles,
			explanation: explanation
		};
	}

	static function normalizedTokens(values:Array<String>, label:String):Array<String> {
		if (values == null)
			throw 'OCaml runtime requirement $label must be an array.';
		final out = new Array<String>();
		final seen:Map<String, Bool> = [];
		for (raw in values) {
			final value = required(raw, label);
			if (seen.exists(value))
				throw 'OCaml runtime requirement $label repeats "$value".';
			seen.set(value, true);
			out.push(value);
		}
		out.sort(compareStrings);
		return out;
	}

	static function required(value:String, label:String):String {
		final normalized = value == null ? "" : value.trim();
		if (normalized.length == 0)
			throw 'OCaml runtime requirement $label must not be empty.';
		return normalized;
	}

	static function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}
}
#end
