package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;

/** How syntax construction must convert one value crossing a local-carrier boundary. */
enum abstract OcamlLocalCarrierConversion(String) from String to String {
	/** The family has not yet migrated this conversion into the sealed plan. */
	final LegacyCoercion = "legacy-coercion";

	/** The typed value already uses exactly the selected carrier. */
	final Identity = "identity";
}

/** One function-local reference to a program-owned representation decision. */
typedef OcamlLocalRepresentationReference = {
	final localId:Int;
	final representationId:String;
	final semanticTypeId:String;
	final domain:OcamlRepresentationDomain;
}

/** Complete representation status for one admitted or mutated local. */
enum OcamlLocalRepresentationChoice {
	/** Syntax must resolve this exact program-owned decision. */
	ProgramDecision(representationId:String, semanticTypeId:String, domain:OcamlRepresentationDomain);

	/** This semantic type remains deliberately on the legacy mapper for now. */
	Unmigrated(semanticTypeId:String);
}

/** One explicit representation and local-carrier conversion choice for a local. */
typedef OcamlLocalRepresentationDecision = {
	final localId:Int;
	final choice:OcamlLocalRepresentationChoice;
	final initializerConversion:OcamlLocalCarrierConversion;
	final assignmentConversion:OcamlLocalCarrierConversion;
	final readConversion:OcamlLocalCarrierConversion;
}

/**
	Immutable representation references for admitted or mutated locals in one function.

	The program registry owns carrier policy. This function plan retains only the
	stable decision identity selected for each local, so syntax construction can
	validate and consume the answer without reclassifying the Haxe type. Carrier
	conversions are sealed separately so initialization, whole-value
	replacement, and reads cannot fall back to generic same-class casts.
**/
class OcamlLocalRepresentationPlan {
	final orderedDecisions:Array<OcamlLocalRepresentationDecision>;
	final decisionsByLocalId:Map<Int, OcamlLocalRepresentationDecision> = [];

	public final count:Int;
	public final admittedCount:Int;
	public final revision:String;

	public function new(decisions:Array<OcamlLocalRepresentationDecision>) {
		orderedDecisions = decisions.map(copyDecision);
		orderedDecisions.sort((left, right) -> left.localId - right.localId);
		var admitted = 0;
		for (decision in orderedDecisions) {
			if (decisionsByLocalId.exists(decision.localId))
				throw 'reflaxe.ocaml [ocaml-representation:duplicate-local-choice]: local ${decision.localId} has more than one representation choice';
			decisionsByLocalId.set(decision.localId, decision);
			switch (decision.choice) {
				case ProgramDecision(_, _, _):
					admitted += 1;
				case Unmigrated(_):
					if (decision.initializerConversion != OcamlLocalCarrierConversion.LegacyCoercion
						|| decision.assignmentConversion != OcamlLocalCarrierConversion.LegacyCoercion
						|| decision.readConversion != OcamlLocalCarrierConversion.LegacyCoercion) {
						throw 'reflaxe.ocaml [ocaml-representation:unmigrated-conversion]: local ${decision.localId} is unmigrated but selects a non-legacy carrier conversion';
					}
			}
		}
		count = orderedDecisions.length;
		admittedCount = admitted;
		revision = "sha256:" + Sha256.encode(orderedDecisions.map(decisionFingerprint).join("\n"));
	}

	/** Returns the sealed program-decision or explicit-unmigrated choice. */
	public function choiceFor(localId:Int):Null<OcamlLocalRepresentationChoice> {
		final decision = decisionsByLocalId.get(localId);
		return decision == null ? null : copyChoice(decision.choice);
	}

	/** Returns the sealed initializer conversion for one planned local. */
	public function initializerConversionFor(localId:Int):Null<OcamlLocalCarrierConversion> {
		final decision = decisionsByLocalId.get(localId);
		return decision == null ? null : decision.initializerConversion;
	}

	/** Returns the sealed whole-value assignment conversion for one planned local. */
	public function assignmentConversionFor(localId:Int):Null<OcamlLocalCarrierConversion> {
		final decision = decisionsByLocalId.get(localId);
		return decision == null ? null : decision.assignmentConversion;
	}

	/** Returns the sealed conversion applied when syntax reads one planned local. */
	public function readConversionFor(localId:Int):Null<OcamlLocalCarrierConversion> {
		final decision = decisionsByLocalId.get(localId);
		return decision == null ? null : decision.readConversion;
	}

	/** Returns a defensive copy of one local's registry reference. */
	public function referenceFor(localId:Int):Null<OcamlLocalRepresentationReference> {
		final choice = choiceFor(localId);
		return switch (choice) {
			case ProgramDecision(representationId, semanticTypeId, domain): {
					localId: localId,
					representationId: representationId,
					semanticTypeId: semanticTypeId,
					domain: domain
				};
			case Unmigrated(_), null: null;
		}
	}

	/** Returns all references in deterministic local-id order. */
	public function references():Array<OcamlLocalRepresentationReference> {
		final references:Array<OcamlLocalRepresentationReference> = [];
		for (decision in orderedDecisions) {
			switch (decision.choice) {
				case ProgramDecision(representationId, semanticTypeId, domain):
					references.push({
						localId: decision.localId,
						representationId: representationId,
						semanticTypeId: semanticTypeId,
						domain: domain
					});
				case Unmigrated(_):
			}
		}
		return references;
	}

	static function copyDecision(decision:OcamlLocalRepresentationDecision):OcamlLocalRepresentationDecision {
		return {
			localId: decision.localId,
			choice: copyChoice(decision.choice),
			initializerConversion: decision.initializerConversion,
			assignmentConversion: decision.assignmentConversion,
			readConversion: decision.readConversion
		};
	}

	static function copyChoice(choice:OcamlLocalRepresentationChoice):OcamlLocalRepresentationChoice {
		return switch (choice) {
			case ProgramDecision(representationId, semanticTypeId, domain): ProgramDecision(representationId, semanticTypeId, domain);
			case Unmigrated(semanticTypeId): Unmigrated(semanticTypeId);
		}
	}

	static function decisionFingerprint(decision:OcamlLocalRepresentationDecision):String {
		final choiceFingerprint = switch (decision.choice) {
			case ProgramDecision(representationId, semanticTypeId,
				domain): '${decision.localId}|program|$representationId|$semanticTypeId|${(domain : String)}';
			case Unmigrated(semanticTypeId): '${decision.localId}|unmigrated|$semanticTypeId';
		}
		return choiceFingerprint + "|initializer:" + (decision.initializerConversion : String) + "|assignment:" + (decision.assignmentConversion : String)
			+ "|read:" + (decision.readConversion : String);
	}
}
#end
