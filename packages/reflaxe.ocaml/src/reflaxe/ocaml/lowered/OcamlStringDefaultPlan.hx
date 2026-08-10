package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.Json;
import haxe.crypto.Sha256;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlFinalRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/**
	One concrete place where generated OCaml needs the exact Haxe String null value.

	A representation decision explains why String uses a nullable direct carrier,
	but the same decision can serve many fields, locals, and call arguments. This
	plan adds the missing concrete owner. Its single runtime occurrence therefore
	cannot be reused as a program-wide permission to print the String sentinel.
**/
typedef OcamlStringDefaultDecision = {
	final id:String;
	final revision:String;
	final ownerId:String;
	final ownerRevision:String;
	final source:OcamlLoweredSourceSpan;
	final representationId:String;
	final representationRevision:String;
	final representationDomain:OcamlRepresentationDomain;
	final requirement:OcamlRuntimeRequirement;
	final runtimeUse:OcamlRuntimeUseOccurrence;
}

/** Seals and validates owner-bound exact String null materializations. */
class OcamlStringDefaultPlan {
	public static inline final MODEL_REVISION = "ocaml-string-default-v1";
	public static inline final EXACT_SYMBOL = "HxString.hx_null_string";
	public static inline final RUNTIME_ROLE = "string-null-default";

	/**
		Creates one immutable default plan from an already-sealed representation.

		`ownerId` names the field, local, call slot, or expression that will contain
		the generated value. `ownerRevision` changes whenever that owning plan changes.
	**/
	public static function seal(representation:OcamlRepresentationDecision, ownerId:String, ownerRevision:String,
			source:OcamlLoweredSourceSpan):OcamlStringDefaultDecision {
		requireOwner(ownerId, ownerRevision, source);
		final requirements = OcamlRuntimeRequirementLedger.requirementsForRepresentationDecision(representation);
		if (requirements.length != 1)
			throw 'reflaxe.ocaml [ocaml-string-default:missing-requirement]: representation "${representation.id}" must provide exactly one String null-sentinel requirement';
		final requirement = requirements[0];
		final id = "string-default:" + ownerId;
		final revision = revisionFor(id, ownerId, ownerRevision, source, representation, requirement);
		final runtimeUse:OcamlRuntimeUseOccurrence = {
			id: id + ":runtime-use:" + OcamlRuntimeRequirementLedger.STRING_NULL_SENTINEL,
			planRevision: revision,
			ownerId: id,
			requirementId: requirement.id,
			domain: OcamlRuntimeUseDomain.ExpressionIdentifier,
			exactSymbol: EXACT_SYMBOL,
			role: RUNTIME_ROLE,
			order: 0,
			source: copySource(source),
			profileEligibility: requirement.profileEligibility.copy(),
			cardinality: 1
		};
		return {
			id: id,
			revision: revision,
			ownerId: ownerId,
			ownerRevision: ownerRevision,
			source: copySource(source),
			representationId: representation.id,
			representationRevision: representation.revision,
			representationDomain: representation.domain,
			requirement: copyRequirement(requirement),
			runtimeUse: runtimeUse
		};
	}

	/** Reconstructs the expected plan and rejects any stale or widened fact. */
	public static function requireDecision(decision:OcamlStringDefaultDecision, representation:OcamlRepresentationDecision):Void {
		if (decision == null)
			throw "reflaxe.ocaml [ocaml-string-default:missing-plan]: String null materialization requires an owner-bound plan";
		final expected = seal(representation, decision.ownerId, decision.ownerRevision, decision.source);
		if (Json.stringify(decision) != Json.stringify(expected))
			throw 'reflaxe.ocaml [ocaml-string-default:stale-plan]: default plan "${decision.id}" no longer matches its owner or sealed String representation';
	}

	/** Creates the single request-local authority that consumes this plan. */
	public static function authority(decision:OcamlStringDefaultDecision, activeProfile:String,
			?finalOutputAuthority:OcamlFinalRuntimeUseAuthority):OcamlRuntimeUseAuthority {
		if (decision == null)
			throw "reflaxe.ocaml [ocaml-string-default:missing-plan]: String null materialization requires an owner-bound plan";
		return new OcamlRuntimeUseAuthority(decision.revision, activeProfile, [decision.requirement], [decision.runtimeUse], finalOutputAuthority);
	}

	static function revisionFor(id:String, ownerId:String, ownerRevision:String, source:OcamlLoweredSourceSpan, representation:OcamlRepresentationDecision,
			requirement:OcamlRuntimeRequirement):String {
		final fields = [
			MODEL_REVISION,
			id,
			ownerId,
			ownerRevision,
			source.file,
			Std.string(source.min),
			Std.string(source.max),
			representation.id,
			representation.revision,
			(representation.domain : String),
			requirement.id,
			requirement.semanticCapability,
			requirement.rootModules.join(","),
			requirement.profileEligibility.join(","),
			EXACT_SYMBOL,
			RUNTIME_ROLE
		];
		return "sha256:" + Sha256.encode(fields.map(value -> value.length + ":" + value).join("|"));
	}

	static function requireOwner(ownerId:String, ownerRevision:String, source:OcamlLoweredSourceSpan):Void {
		if (ownerId == null || ownerId.length == 0)
			throw "reflaxe.ocaml [ocaml-string-default:missing-owner]: String null materialization requires a concrete owner identity";
		if (ownerRevision == null || ownerRevision.length == 0)
			throw 'reflaxe.ocaml [ocaml-string-default:missing-owner-revision]: owner "$ownerId" has no revision';
		if (source == null || source.file == null || source.file.length == 0 || source.min < 0 || source.max < source.min)
			throw 'reflaxe.ocaml [ocaml-string-default:invalid-source]: owner "$ownerId" has no valid source span';
	}

	static function copySource(source:OcamlLoweredSourceSpan):OcamlLoweredSourceSpan {
		return {file: source.file, min: source.min, max: source.max};
	}

	static function copyRequirement(requirement:OcamlRuntimeRequirement):OcamlRuntimeRequirement {
		return {
			id: requirement.id,
			sourceKind: requirement.sourceKind,
			sourceId: requirement.sourceId,
			source: copySource(requirement.source),
			semanticCapability: requirement.semanticCapability,
			cause: requirement.cause,
			decisionId: requirement.decisionId,
			subject: {
				kind: requirement.subject.kind,
				id: requirement.subject.id
			},
			implementationFeature: requirement.implementationFeature,
			rootModules: requirement.rootModules.copy(),
			profileEligibility: requirement.profileEligibility.copy(),
			explanation: requirement.explanation
		};
	}
}
#end
