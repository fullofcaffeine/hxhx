package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;

/** The OCaml storage shape selected for one mutated Haxe local. */
enum abstract OcamlLocalStorageKind(String) to String {
	/** Each straight-line write introduces a newer immutable `let` binding. */
	var ImmutableRebinding = "immutable-rebinding";

	/** Reads and writes share one mutable OCaml `ref` cell. */
	var RefCell = "ref-cell";
}

/** Closed explanations for selecting one local-storage shape. */
enum abstract OcamlLocalStorageReason(String) to String {
	/** A top-level statement assignment can safely introduce a newer binding. */
	var StraightLineAssignment = "straight-line-assignment";

	/** A write in a nested block must remain visible after that block. */
	var NestedBlockMutation = "nested-block-mutation";

	/** A write performed by a loop must update storage shared across iterations. */
	var LoopMutation = "loop-mutation";

	/** A write inside a nested function must update storage shared with its caller. */
	var NestedFunctionMutation = "nested-function-mutation";

	/** A write used inside another expression cannot become a surrounding `let` statement. */
	var ExpressionPositionMutation = "expression-position-mutation";

	/** Compound assignment reads and writes the same local as one operation. */
	var CompoundAssignment = "compound-assignment";

	/** Increment or decrement reads and writes the same local as one operation. */
	var IncrementOrDecrement = "increment-or-decrement";

	/** A nested function observes the local and at least one path mutates it. */
	var CapturedAndMutated = "captured-and-mutated";
}

/** One deterministic storage decision for a mutated Haxe local. */
typedef OcamlLocalStorageDecision = {
	final localId:Int;
	final storage:OcamlLocalStorageKind;
	final reasons:Array<OcamlLocalStorageReason>;
}

/**
	Immutable result of local-storage analysis for one expression or block.

	Only mutated locals appear in this first model. The plan records whether each
	write can use a newer immutable binding or needs one shared `ref` cell, plus
	the source-language reason for that choice. Callers receive copies so they
	cannot mutate the planner's retained decisions accidentally.
**/
class OcamlLocalStoragePlan {
	final orderedDecisions:Array<OcamlLocalStorageDecision>;
	final decisionsByLocalId:Map<Int, OcamlLocalStorageDecision> = [];

	public final count:Int;

	/** Deterministic digest of the selected local-storage decisions. */
	public final revision:String;

	public function new(decisions:Array<OcamlLocalStorageDecision>) {
		orderedDecisions = decisions.map(copyDecision);
		orderedDecisions.sort((left, right) -> left.localId - right.localId);
		for (decision in orderedDecisions) {
			if (decisionsByLocalId.exists(decision.localId))
				throw 'reflaxe.ocaml [ocaml-lowering:duplicate-local-storage-decision]: local ${decision.localId} was planned more than once';
			decisionsByLocalId.set(decision.localId, decision);
		}
		count = orderedDecisions.length;
		revision = "sha256:" + Sha256.encode(orderedDecisions.map(decisionFingerprint).join("\n"));
	}

	/** Returns whether the local needs one shared mutable cell. */
	public function requiresRef(localId:Int):Bool {
		final decision = decisionsByLocalId.get(localId);
		return decision != null && decision.storage == OcamlLocalStorageKind.RefCell;
	}

	/** Returns a defensive copy of one decision, when the local was mutated. */
	public function decisionFor(localId:Int):Null<OcamlLocalStorageDecision> {
		final decision = decisionsByLocalId.get(localId);
		return decision == null ? null : copyDecision(decision);
	}

	/** Returns all decisions in deterministic local-id order. */
	public function decisions():Array<OcamlLocalStorageDecision> {
		return orderedDecisions.map(copyDecision);
	}

	static function copyDecision(decision:OcamlLocalStorageDecision):OcamlLocalStorageDecision {
		return {
			localId: decision.localId,
			storage: decision.storage,
			reasons: canonicalReasons(decision.reasons)
		};
	}

	static function canonicalReasons(reasons:Array<OcamlLocalStorageReason>):Array<OcamlLocalStorageReason> {
		final byId:Map<String, OcamlLocalStorageReason> = [];
		for (reason in reasons) {
			final reasonId:String = reason;
			byId.set(reasonId, reason);
		}
		final reasonIds = [for (reasonId in byId.keys()) reasonId];
		reasonIds.sort(Reflect.compare);
		return [for (reasonId in reasonIds) cast byId.get(reasonId)];
	}

	static function decisionFingerprint(decision:OcamlLocalStorageDecision):String {
		final storageId:String = decision.storage;
		final reasonIds = decision.reasons.map(reason -> {
			final reasonId:String = reason;
			return reasonId;
		});
		return '${decision.localId}|$storageId|${reasonIds.join(",")}';
	}
}
#end
