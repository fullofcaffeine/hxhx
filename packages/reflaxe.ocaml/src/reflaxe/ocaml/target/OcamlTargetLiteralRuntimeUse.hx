package reflaxe.ocaml.target;

import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeReference;
import reflaxe.ocaml.target.OcamlTargetLiteralFact.OcamlTargetLiteralKind;
import reflaxe.ocaml.target.OcamlTargetLiteralLowerer.OcamlTargetLiteralCarrier;
#if (macro || reflaxe_runtime || eval)
import haxe.crypto.Sha256;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementCause;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSourceKind;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSubjectKind;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;
#end

/**
	A checked private-runtime reference for one exact target literal.

	The token is inert so the shared target lowerer can consume it under either
	stock Haxe or native `hxhx`. Only the guarded runtime-use contract can create
	one after it validates the literal, carrier, plan, and request authority.
**/
@:allow(reflaxe.ocaml.target.OcamlTargetLiteralRuntimeUseContract)
class OcamlTargetLiteralRuntimeAuthorization {
	public final decisionId:String;
	public final literalIdentity:String;
	public final carrier:OcamlTargetLiteralCarrier;
	public final reference:OcamlRuntimeReference;

	private function new(decisionId:String, literalIdentity:String, carrier:OcamlTargetLiteralCarrier, reference:OcamlRuntimeReference) {
		this.decisionId = decisionId;
		this.literalIdentity = literalIdentity;
		this.carrier = carrier;
		this.reference = reference;
	}
}

#if (macro || reflaxe_runtime || eval)
/** One source literal's exact permission to box a Boolean as `Dynamic`. **/
typedef OcamlTargetLiteralRuntimeUseDecision = {
	final id:String;
	final revision:String;
	final sourceId:String;
	final source:OcamlLoweredSourceSpan;
	final literalIdentity:String;
	final semanticTypeId:String;
	final boolValue:Bool;
	final carrier:OcamlTargetLiteralCarrier;
	final profileEligibility:Array<String>;
	final runtimeRequirementIds:Array<String>;
	final runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence>;
}

/**
	Seals and validates the private helper owned by a Dynamic Boolean literal.

	All other literal and carrier pairs return no plan. This keeps the permission
	narrow: it cannot authorize general Boolean conversions or another literal.
**/
class OcamlTargetLiteralRuntimeUseContract {
	public static inline final CAPABILITY = "haxe-dynamic-bool-literal";
	public static inline final IMPLEMENTATION_FEATURE = "haxe-dynamic-bool-literal-v1";
	public static inline final EXACT_SYMBOL = "HxRuntime.box_bool";
	public static inline final ROLE = "box-dynamic-bool-literal";
	public static inline final EXPLANATION = "The sealed Haxe Boolean literal enters a Dynamic or type-parameter carrier, so HxRuntime.box_bool preserves its identity separately from integer values.";

	/** Returns one exact plan when this literal needs the private Boolean box. **/
	public static function forLiteral(fact:OcamlTargetLiteralFact, carrier:OcamlTargetLiteralCarrier, sourceId:String,
			source:OcamlLoweredSourceSpan):Null<OcamlTargetLiteralRuntimeUseDecision> {
		requireInputs(fact, carrier, sourceId, source);
		if (!needsRuntimeBox(fact, carrier))
			return null;
		final literalIdentity = fact.getCanonicalIdentity();
		final id = decisionId(sourceId, source, literalIdentity, fact.semanticTypeDisplay, fact.boolValue);
		final profiles = ["metal", "portable"];
		final revision = decisionRevision(id, sourceId, source, literalIdentity, fact.semanticTypeDisplay, fact.boolValue, profiles);
		final requirementId = id + ":runtime:" + CAPABILITY;
		return {
			id: id,
			revision: revision,
			sourceId: sourceId,
			source: copySource(source),
			literalIdentity: literalIdentity,
			semanticTypeId: fact.semanticTypeDisplay,
			boolValue: fact.boolValue,
			carrier: carrier,
			profileEligibility: profiles,
			runtimeRequirementIds: [requirementId],
			runtimeUseOccurrences: [
				{
					id: id + ":runtime-use:" + ROLE,
					planRevision: revision,
					ownerId: id,
					requirementId: requirementId,
					domain: OcamlRuntimeUseDomain.ExpressionIdentifier,
					exactSymbol: EXACT_SYMBOL,
					role: ROLE,
					order: 0,
					source: copySource(source),
					profileEligibility: profiles.copy(),
					cardinality: 1
				}
			]
		};
	}

	/** Rejects a plan that no longer describes its source literal and carrier. **/
	public static function requireForLiteral(fact:OcamlTargetLiteralFact, carrier:OcamlTargetLiteralCarrier, sourceId:String, source:OcamlLoweredSourceSpan,
			decision:OcamlTargetLiteralRuntimeUseDecision):Void {
		final expected = forLiteral(fact, carrier, sourceId, source);
		if (expected == null)
			throw 'reflaxe.ocaml [ocaml-target-literal:unexpected-runtime-use]: literal "${fact.getCanonicalIdentity()}" does not need a private runtime helper';
		requireDecision(decision);
		if (!sameDecision(decision, expected)) {
			throw 'reflaxe.ocaml [ocaml-target-literal:invalid-runtime-use]: literal "${fact.getCanonicalIdentity()}" does not own its exact runtime requirement and occurrence';
		}
	}

	/** Rejects a saved plan whose identity, source, or exact occurrence changed. **/
	public static function requireDecision(decision:OcamlTargetLiteralRuntimeUseDecision):Void {
		if (decision == null)
			throw "reflaxe.ocaml [ocaml-target-literal:missing-runtime-use]: Dynamic Boolean literal requires a sealed runtime-use plan";
		requireSourceId(decision.sourceId);
		requireSource(decision.source, decision.sourceId);
		if (!~/^[0-9a-f]{64}$/.match(decision.literalIdentity))
			throw 'reflaxe.ocaml [ocaml-target-literal:invalid-runtime-use]: literal plan "${decision.id}" has an invalid literal identity';
		if (decision.semanticTypeId == null || StringTools.trim(decision.semanticTypeId).length == 0)
			throw 'reflaxe.ocaml [ocaml-target-literal:invalid-runtime-use]: literal plan "${decision.id}" has no semantic type';
		if (decision.carrier != OcamlTargetLiteralCarrier.DynamicOrTypeParameter
			|| decision.profileEligibility.join(",") != "metal,portable") {
			throw 'reflaxe.ocaml [ocaml-target-literal:invalid-runtime-use]: literal plan "${decision.id}" has the wrong carrier or profiles';
		}
		final expectedId = decisionId(decision.sourceId, decision.source, decision.literalIdentity, decision.semanticTypeId, decision.boolValue);
		final expectedRevision = decisionRevision(expectedId, decision.sourceId, decision.source, decision.literalIdentity, decision.semanticTypeId,
			decision.boolValue, decision.profileEligibility);
		final expectedRequirementId = expectedId + ":runtime:" + CAPABILITY;
		if (decision.id != expectedId
			|| decision.revision != expectedRevision
			|| decision.runtimeRequirementIds.length != 1
			|| decision.runtimeRequirementIds[0] != expectedRequirementId
			|| decision.runtimeUseOccurrences.length != 1
			|| !sameOccurrence(decision.runtimeUseOccurrences[0], expectedId, expectedRevision, expectedRequirementId, decision.source)) {
			throw 'reflaxe.ocaml [ocaml-target-literal:invalid-runtime-use]: literal plan "${decision.id}" has stale or conflicting runtime authority';
		}
	}

	/** Creates the only token accepted by the shared target-literal lowerer. **/
	public static function authorize(decision:OcamlTargetLiteralRuntimeUseDecision, fact:OcamlTargetLiteralFact, carrier:OcamlTargetLiteralCarrier,
			sourceId:String, source:OcamlLoweredSourceSpan, authority:OcamlRuntimeUseAuthority):OcamlTargetLiteralRuntimeAuthorization {
		requireForLiteral(fact, carrier, sourceId, source, decision);
		if (authority == null)
			throw 'reflaxe.ocaml [ocaml-target-literal:missing-runtime-authority]: literal plan "${decision.id}" cannot construct its private Boolean box';
		final occurrence = decision.runtimeUseOccurrences[0];
		final reference = authority.expressionIdentifier(occurrence.id, decision.revision, EXACT_SYMBOL);
		if (reference.ownerId != decision.id)
			throw 'reflaxe.ocaml [ocaml-target-literal:invalid-runtime-authority]: literal plan "${decision.id}" received a foreign runtime reference';
		return new OcamlTargetLiteralRuntimeAuthorization(decision.id, decision.literalIdentity, carrier, reference);
	}

	/** Returns whether the literal/carrier pair owns the Dynamic Boolean helper. **/
	public static function needsRuntimeBox(fact:OcamlTargetLiteralFact, carrier:OcamlTargetLiteralCarrier):Bool {
		return fact != null
			&& fact.kind == OcamlTargetLiteralKind.BoolValue
			&& carrier == OcamlTargetLiteralCarrier.DynamicOrTypeParameter;
	}

	static function decisionId(sourceId:String, source:OcamlLoweredSourceSpan, literalIdentity:String, semanticTypeId:String, boolValue:Bool):String {
		final canonical = [
			sourceId,
			source.file,
			Std.string(source.min),
			Std.string(source.max),
			literalIdentity,
			semanticTypeId,
			boolValue ? "1" : "0"
		];
		return "target-literal:" + Sha256.encode(canonical.map(value -> value.length + ":" + value).join("|"));
	}

	static function decisionRevision(id:String, sourceId:String, source:OcamlLoweredSourceSpan, literalIdentity:String, semanticTypeId:String, boolValue:Bool,
			profiles:Array<String>):String {
		final canonical = [
			"ocaml-target-literal-runtime-use-v1",
			id,
			sourceId,
			source.file,
			Std.string(source.min),
			Std.string(source.max),
			literalIdentity,
			semanticTypeId,
			boolValue ? "1" : "0",
			profiles.join(","),
			EXACT_SYMBOL,
			ROLE
		];
		return "sha256:" + Sha256.encode(canonical.map(value -> value.length + ":" + value).join("|"));
	}

	static function sameDecision(actual:OcamlTargetLiteralRuntimeUseDecision, expected:OcamlTargetLiteralRuntimeUseDecision):Bool {
		return actual.id == expected.id
			&& actual.revision == expected.revision
			&& actual.sourceId == expected.sourceId
			&& sameSource(actual.source, expected.source)
			&& actual.literalIdentity == expected.literalIdentity
			&& actual.semanticTypeId == expected.semanticTypeId
			&& actual.boolValue == expected.boolValue
			&& actual.carrier == expected.carrier
			&& actual.profileEligibility.join(",") == expected.profileEligibility.join(",")
			&& actual.runtimeRequirementIds.join(",") == expected.runtimeRequirementIds.join(",")
			&& actual.runtimeUseOccurrences.length == 1
			&& expected.runtimeUseOccurrences.length == 1
			&& sameExactOccurrence(actual.runtimeUseOccurrences[0], expected.runtimeUseOccurrences[0]);
	}

	static function sameOccurrence(actual:OcamlRuntimeUseOccurrence, ownerId:String, revision:String, requirementId:String,
			source:OcamlLoweredSourceSpan):Bool {
		return actual != null
			&& actual.id == ownerId + ":runtime-use:" + ROLE
			&& actual.planRevision == revision
			&& actual.ownerId == ownerId
			&& actual.requirementId == requirementId
			&& actual.domain == OcamlRuntimeUseDomain.ExpressionIdentifier
			&& actual.exactSymbol == EXACT_SYMBOL
			&& actual.role == ROLE
			&& actual.order == 0
			&& sameSource(actual.source, source)
			&& actual.profileEligibility.join(",") == "metal,portable"
			&& actual.cardinality == 1;
	}

	static function sameExactOccurrence(actual:OcamlRuntimeUseOccurrence, expected:OcamlRuntimeUseOccurrence):Bool {
		return actual != null
			&& expected != null
			&& actual.id == expected.id
			&& actual.planRevision == expected.planRevision
			&& actual.ownerId == expected.ownerId
			&& actual.requirementId == expected.requirementId
			&& actual.domain == expected.domain
			&& actual.exactSymbol == expected.exactSymbol
			&& actual.role == expected.role
			&& actual.order == expected.order
			&& sameSource(actual.source, expected.source)
			&& actual.profileEligibility.join(",") == expected.profileEligibility.join(",")
			&& actual.cardinality == expected.cardinality;
	}

	static function requireInputs(fact:OcamlTargetLiteralFact, carrier:OcamlTargetLiteralCarrier, sourceId:String, source:OcamlLoweredSourceSpan):Void {
		if (fact == null || carrier == null)
			throw "reflaxe.ocaml [ocaml-target-literal:missing-input]: runtime-use planning requires a literal fact and carrier";
		requireSourceId(sourceId);
		requireSource(source, sourceId);
	}

	static function requireSourceId(sourceId:String):Void {
		if (sourceId == null || StringTools.trim(sourceId).length == 0)
			throw "reflaxe.ocaml [ocaml-target-literal:missing-source-id]: runtime-use planning requires one source occurrence identity";
	}

	static function requireSource(source:OcamlLoweredSourceSpan, sourceId:String):Void {
		if (source == null || source.file == null || source.file.length == 0 || source.min < 0 || source.max < source.min)
			throw 'reflaxe.ocaml [ocaml-target-literal:invalid-source]: source occurrence "$sourceId" has no valid source span';
	}

	static function sameSource(left:OcamlLoweredSourceSpan, right:OcamlLoweredSourceSpan):Bool {
		return left.file == right.file && left.min == right.min && left.max == right.max;
	}

	static function copySource(source:OcamlLoweredSourceSpan):OcamlLoweredSourceSpan {
		return {file: source.file, min: source.min, max: source.max};
	}
}

/** Builds and checks the portable runtime-requirement row for this literal plan. **/
class OcamlTargetLiteralRuntimeRequirementContract {
	/** Returns the exact HxRuntime need selected by one Dynamic Boolean literal. **/
	public static function requirementsFor(decision:OcamlTargetLiteralRuntimeUseDecision):Array<OcamlRuntimeRequirement> {
		OcamlTargetLiteralRuntimeUseContract.requireDecision(decision);
		return [
			{
				id: decision.runtimeRequirementIds[0],
				sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
				sourceId: decision.sourceId,
				source: {file: decision.source.file, min: decision.source.min, max: decision.source.max},
				semanticCapability: OcamlTargetLiteralRuntimeUseContract.CAPABILITY,
				cause: OcamlRuntimeRequirementCause.LoweringDecision,
				decisionId: decision.id,
				subject: {
					kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: "Bool -> " + decision.semanticTypeId
				},
				implementationFeature: OcamlTargetLiteralRuntimeUseContract.IMPLEMENTATION_FEATURE,
				rootModules: ["HxRuntime"],
				profileEligibility: decision.profileEligibility.copy(),
				explanation: OcamlTargetLiteralRuntimeUseContract.EXPLANATION
			}
		];
	}

	/** Rejects a public requirement that no longer matches the literal contract. **/
	public static function requireRequirement(requirement:OcamlRuntimeRequirement):Void {
		final expectedId = requirement.decisionId + ":runtime:" + OcamlTargetLiteralRuntimeUseContract.CAPABILITY;
		if (requirement.id != expectedId
			|| !~/^target-literal:[0-9a-f]{64}$/.match(requirement.decisionId)
			|| requirement.sourceKind != OcamlRuntimeRequirementSourceKind.HaxeExpression
			|| requirement.sourceId == null
			|| StringTools.trim(requirement.sourceId).length == 0
			|| requirement.semanticCapability != OcamlTargetLiteralRuntimeUseContract.CAPABILITY
			|| requirement.cause != OcamlRuntimeRequirementCause.LoweringDecision
			|| requirement.subject.kind != OcamlRuntimeRequirementSubjectKind.HaxeType
			|| requirement.subject.id == null
			|| !StringTools.startsWith(requirement.subject.id, "Bool -> ")
			|| StringTools.trim(requirement.subject.id.substr("Bool -> ".length)).length == 0
			|| requirement.implementationFeature != OcamlTargetLiteralRuntimeUseContract.IMPLEMENTATION_FEATURE
			|| requirement.rootModules.join(",") != "HxRuntime"
			|| requirement.profileEligibility.join(",") != "metal,portable"
			|| requirement.explanation != OcamlTargetLiteralRuntimeUseContract.EXPLANATION) {
			throw 'Dynamic Boolean literal runtime requirement "${requirement.id}" does not match its sealed target-literal contract.';
		}
	}
}
#end
