package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import reflaxe.lifecycle.LexicalLocalIdentityPlan;

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
	final localId:String;
	final storage:OcamlLocalStorageKind;
	final reasons:Array<OcamlLocalStorageReason>;
}

/**
	Immutable result of local-storage analysis for one expression or block.

	Only mutated locals appear in this first model. The plan records whether each
	write can use a newer immutable binding or needs one shared `ref` cell, plus
	the source-language reason for that choice. It retains only reusable lexical
	identities; request-local Haxe `TVar.id` lookups stay in the planning and
	rendering contexts. Callers receive copies so they cannot mutate the retained
	decisions accidentally.
**/
class OcamlLocalStoragePlan {
	final orderedDecisions:Array<OcamlLocalStorageDecision>;
	final decisionsByLocalId:Map<String, OcamlLocalStorageDecision> = [];
	final orderedCapturedLocalIds:Array<String>;
	final capturedLocalIds:Map<String, Bool> = [];

	public final count:Int;

	/** Deterministic digest of the selected local-storage decisions. */
	public final revision:String;

	public function new(decisions:Array<OcamlLocalStorageDecision>, ?captured:Array<String>) {
		orderedDecisions = decisions.map(decision -> ({
			localId: decision.localId,
			storage: decision.storage,
			reasons: canonicalReasons(decision.reasons)
		}));
		orderedDecisions.sort((left, right) -> Reflect.compare(left.localId, right.localId));
		for (decision in orderedDecisions) {
			requireReusableLocalId(decision.localId);
			if (decisionsByLocalId.exists(decision.localId))
				throw 'reflaxe.ocaml [ocaml-lowering:duplicate-local-storage-decision]: local ${decision.localId} was planned more than once';
			decisionsByLocalId.set(decision.localId, decision);
		}
		for (localId in captured ?? []) {
			requireReusableLocalId(localId);
			capturedLocalIds.set(localId, true);
		}
		orderedCapturedLocalIds = [for (localId in capturedLocalIds.keys()) localId];
		orderedCapturedLocalIds.sort(Reflect.compare);
		for (decision in orderedDecisions) {
			final capturedAndMutated = hasReason(decision, OcamlLocalStorageReason.CapturedAndMutated);
			if (capturedAndMutated != capturedLocalIds.exists(decision.localId)) {
				throw 'reflaxe.ocaml [ocaml-lowering:contradictory-capture-storage]: local ${decision.localId} must record capture and ${OcamlLocalStorageReason.CapturedAndMutated} together';
			}
			if (capturedAndMutated && decision.storage != OcamlLocalStorageKind.RefCell)
				throw 'reflaxe.ocaml [ocaml-lowering:captured-mutation-without-cell]: captured and mutated local ${decision.localId} must use ${OcamlLocalStorageKind.RefCell}';
		}
		count = orderedDecisions.length;
		final fingerprints = orderedDecisions.map(decision -> "storage|" + decisionFingerprint(decision));
		for (localId in orderedCapturedLocalIds)
			fingerprints.push('capture|$localId');
		revision = "sha256:" + Sha256.encode(fingerprints.join("\n"));
	}

	/** Returns whether the local needs one shared mutable cell. */
	public function requiresRef(localId:String):Bool {
		final decision = decisionsByLocalId.get(localId);
		return decision != null && decision.storage == OcamlLocalStorageKind.RefCell;
	}

	/**
		Returns whether a nested function closes over the local.

		Immutable captures do not need a storage decision of their own, but later
		representation planners still need the fact so a deliberately narrow
		carrier slice cannot admit them accidentally.
	**/
	public function isCaptured(localId:String):Bool {
		return capturedLocalIds.exists(localId);
	}

	/**
		Returns whether a closure keeps the local alive without sharing mutable
		whole-local storage.

		The referenced value may still be a mutable object or array. This answer
		only proves that the Haxe local itself is never assigned a replacement, so
		the closure can retain the same immutable OCaml binding directly.
	**/
	public function isImmutableCapture(localId:String):Bool {
		return capturedLocalIds.exists(localId) && !decisionsByLocalId.exists(localId);
	}

	/** Returns captured local identities in deterministic order. */
	public function capturedIds():Array<String> {
		return orderedCapturedLocalIds.copy();
	}

	/** Returns a defensive copy for one reusable lexical identity. */
	public function decisionFor(localId:String):Null<OcamlLocalStorageDecision> {
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

	static function requireReusableLocalId(localId:String):Void {
		if (!LexicalLocalIdentityPlan.isReusableId(localId)) {
			throw 'reflaxe.ocaml [ocaml-lowering:invalid-lexical-local-identity]: "$localId" is not one complete reusable lexical-local identity';
		}
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

	static function hasReason(decision:OcamlLocalStorageDecision, expected:OcamlLocalStorageReason):Bool {
		final expectedId:String = expected;
		for (reason in decision.reasons) {
			final reasonId:String = reason;
			if (reasonId == expectedId)
				return true;
		}
		return false;
	}
}
#end
