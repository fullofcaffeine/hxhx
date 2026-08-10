package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.Json;
import haxe.crypto.Sha256;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationBoxingPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationImplicitDefaultPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationNullPolicy;
import reflaxe.ocaml.runtimegen.OcamlFinalRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/**
	One concrete field declaration that starts with Haxe `null`.

	The shared representation says that `Null<Int>` or `Null<Bool>` can use an
	`Obj.t` carrier. This value is narrower: it names the exact field or static
	cell whose generated initializer may reference `HxRuntime.hx_null` once.
**/
typedef OcamlNullablePrimitiveFieldDefaultDecision = {
	final id:String;
	final revision:String;
	final ownerId:String;
	final ownerRevision:String;
	final source:OcamlLoweredSourceSpan;
	final representationId:String;
	final representationRevision:String;
	final representationDomain:OcamlRepresentationDomain;
	final semanticTypeId:String;
	final requirement:OcamlRuntimeRequirement;
	final runtimeUse:OcamlRuntimeUseOccurrence;
}

/** Seals and validates one owner-bound nullable primitive field default. */
class OcamlNullablePrimitiveFieldDefaultPlan {
	public static inline final MODEL_REVISION = "ocaml-nullable-primitive-field-default-v1";
	public static inline final EXACT_SYMBOL = "HxRuntime.hx_null";
	public static inline final RUNTIME_ROLE = "nullable-primitive-field-default";

	/**
		Checks the carrier contract without claiming a generated default value.

		Type declarations use this method because learning that the OCaml carrier is
		`Obj.t` must not grant permission to print a private runtime identifier.
	**/
	public static function requireRepresentation(representation:OcamlRepresentationDecision, expectedDomain:OcamlRepresentationDomain):Void {
		switch (expectedDomain) {
			case InstanceField, StaticField:
			case InternalValue, MutableLocalStorage, CapturedLocalStorage, ArrayElement:
				throw 'reflaxe.ocaml [ocaml-nullable-field-default:unsupported-domain]: nullable primitive field defaults require instance-field or static-field, not $expectedDomain';
		}
		if (representation.domain != expectedDomain)
			throw 'reflaxe.ocaml [ocaml-nullable-field-default:wrong-domain]: representation ${representation.id} selects ${representation.domain}, but the field default requires $expectedDomain';
		final expectedProof = switch (representation.semanticTypeId) {
			case "Null<Int>": "nullable-int-obj-carrier-v2";
			case "Null<Bool>": "nullable-bool-obj-carrier-v2";
			case other:
				throw 'reflaxe.ocaml [ocaml-nullable-field-default:unsupported-family]: no nullable primitive field default exists for $other';
		};
		if (representation.carrierTypeId != "Obj.t"
			|| representation.nullPolicy != OcamlRepresentationNullPolicy.RuntimeSentinel
			|| representation.boxingPolicy != OcamlRepresentationBoxingPolicy.NullablePrimitiveCarrier
			|| representation.implicitDefaultPolicy != OcamlRepresentationImplicitDefaultPolicy.RuntimeNullSentinel
			|| representation.proof.id != expectedProof) {
			throw 'reflaxe.ocaml [ocaml-nullable-field-default:unsupported-decision]: representation ${representation.id} must select ${representation.semanticTypeId} -> Obj.t with the exact nullable primitive field proof';
		}
	}

	/** Creates one immutable default plan from an already-sealed field representation. */
	public static function seal(representation:OcamlRepresentationDecision, ownerId:String, ownerRevision:String,
			source:OcamlLoweredSourceSpan):OcamlNullablePrimitiveFieldDefaultDecision {
		requireOwner(ownerId, ownerRevision, source);
		requireRepresentation(representation, representation.domain);
		final requirements = OcamlRuntimeRequirementLedger.requirementsForRepresentationDecision(representation);
		if (requirements.length != 1)
			throw 'reflaxe.ocaml [ocaml-nullable-field-default:missing-requirement]: representation "${representation.id}" must provide exactly one nullable primitive field-default requirement';
		final requirement = requirements[0];
		final id = "nullable-primitive-field-default:" + ownerId;
		final revision = revisionFor(id, ownerId, ownerRevision, source, representation, requirement);
		final runtimeUse:OcamlRuntimeUseOccurrence = {
			id: id + ":runtime-use:" + OcamlRuntimeRequirementLedger.NULLABLE_PRIMITIVE_FIELD_DEFAULT,
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
			semanticTypeId: representation.semanticTypeId,
			requirement: copyRequirement(requirement),
			runtimeUse: runtimeUse
		};
	}

	/** Reconstructs the expected plan and rejects stale or widened facts. */
	public static function requireDecision(decision:OcamlNullablePrimitiveFieldDefaultDecision, representation:OcamlRepresentationDecision):Void {
		if (decision == null)
			throw "reflaxe.ocaml [ocaml-nullable-field-default:missing-plan]: nullable primitive field materialization requires an owner-bound plan";
		final expected = seal(representation, decision.ownerId, decision.ownerRevision, decision.source);
		if (Json.stringify(decision) != Json.stringify(expected))
			throw 'reflaxe.ocaml [ocaml-nullable-field-default:stale-plan]: default plan "${decision.id}" no longer matches its owner or sealed field representation';
	}

	/** Creates the request-local authority that consumes this plan once. */
	public static function authority(decision:OcamlNullablePrimitiveFieldDefaultDecision, activeProfile:String,
			?finalOutputAuthority:OcamlFinalRuntimeUseAuthority):OcamlRuntimeUseAuthority {
		if (decision == null)
			throw "reflaxe.ocaml [ocaml-nullable-field-default:missing-plan]: nullable primitive field materialization requires an owner-bound plan";
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
			representation.semanticTypeId,
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
			throw "reflaxe.ocaml [ocaml-nullable-field-default:missing-owner]: nullable primitive field materialization requires a concrete owner identity";
		if (ownerRevision == null || ownerRevision.length == 0)
			throw 'reflaxe.ocaml [ocaml-nullable-field-default:missing-owner-revision]: owner "$ownerId" has no revision';
		if (source == null || source.file == null || source.file.length == 0 || source.min < 0 || source.max < source.min)
			throw 'reflaxe.ocaml [ocaml-nullable-field-default:invalid-source]: owner "$ownerId" has no valid source span';
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
