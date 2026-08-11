package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime || eval)
import reflaxe.ocaml.ast.OcamlASTTraversal;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlPat;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeReference;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseReceipt;

using StringTools;

/**
	Creates and reconciles private-runtime identifiers for one sealed plan.

	For example, two planned uses can both print as `HxArray.set`. A text or
	module scan cannot tell U1/U2 from the corrupted U2/U2 sequence. This class
	checks the hidden use IDs carried by the structured target tree, then seals
	itself so no additional identifier can be authorized after reconciliation.

	The class is request-local. It retains only immutable plan and requirement
	facts; it does not retain Haxe compiler expressions or make lowering choices.
**/
class OcamlRuntimeUseAuthority {
	final planRevision:String;
	final activeProfile:String;
	final occurrencesById:Map<String, OcamlRuntimeUseOccurrence> = [];
	final occurrencesInOrder:Array<OcamlRuntimeUseOccurrence> = [];
	final requirementsById:Map<String, OcamlRuntimeRequirement> = [];
	final constructed:Map<String, Bool> = [];
	final receipts:Array<OcamlRuntimeUseReceipt> = [];
	final finalOutputAuthority:Null<OcamlFinalRuntimeUseAuthority>;
	var sealed:Bool = false;

	public function new(planRevision:String, activeProfile:String, requirements:Array<OcamlRuntimeRequirement>, occurrences:Array<OcamlRuntimeUseOccurrence>,
			?finalOutputAuthority:OcamlFinalRuntimeUseAuthority) {
		if (planRevision == null || planRevision.length == 0)
			throw "Runtime-use authority requires a non-empty plan revision.";
		if (activeProfile == null || activeProfile.length == 0)
			throw "Runtime-use authority requires an active target profile.";
		this.planRevision = planRevision;
		this.activeProfile = activeProfile;
		this.finalOutputAuthority = finalOutputAuthority;

		for (requirement in requirements) {
			if (requirementsById.exists(requirement.id))
				throw 'Duplicate runtime requirement ${requirement.id}.';
			requirementsById.set(requirement.id, requirement);
		}
		for (occurrence in occurrences) {
			if (occurrence.id == null || occurrence.id.length == 0)
				throw "Runtime-use occurrence requires a non-empty identity.";
			if (occurrencesById.exists(occurrence.id))
				throw 'Duplicate planned runtime use ${occurrence.id}.';
			if (occurrence.planRevision != planRevision)
				throw 'Planned runtime use ${occurrence.id} has stale plan revision ${occurrence.planRevision}; expected $planRevision.';
			if (occurrence.cardinality != 1)
				throw 'Planned runtime use ${occurrence.id} must have cardinality 1.';
			if (occurrence.order < 0)
				throw 'Planned runtime use ${occurrence.id} has a negative owner-local order.';
			occurrencesById.set(occurrence.id, occurrence);
			occurrencesInOrder.push(occurrence);
		}
		occurrencesInOrder.sort((left, right) -> left.order - right.order);
		for (index in 1...occurrencesInOrder.length)
			if (occurrencesInOrder[index - 1].order == occurrencesInOrder[index].order)
				throw 'Planned runtime uses ${occurrencesInOrder[index - 1].id} and ${occurrencesInOrder[index].id} share owner-local order ${occurrencesInOrder[index].order}.';
	}

	/** Creates one expression identifier after checking all sealed facts. */
	public function expressionIdentifier(id:String, requestedPlanRevision:String, exactSymbol:String):OcamlRuntimeReference {
		return reference(id, requestedPlanRevision, OcamlRuntimeUseDomain.ExpressionIdentifier, exactSymbol);
	}

	/** Creates one pattern constructor after checking all sealed catch-use facts. */
	public function patternIdentifier(id:String, requestedPlanRevision:String, exactSymbol:String):OcamlRuntimeReference {
		return reference(id, requestedPlanRevision, OcamlRuntimeUseDomain.PatternConstructor, exactSymbol);
	}

	/** Creates one private-runtime type name after checking its sealed owner. */
	public function typeIdentifier(id:String, requestedPlanRevision:String, exactSymbol:String):OcamlRuntimeReference {
		return reference(id, requestedPlanRevision, OcamlRuntimeUseDomain.TypeIdentifier, exactSymbol);
	}

	/** Creates one generated-text placeholder after checking all sealed facts. */
	public function generatedTextIdentifier(id:String, requestedPlanRevision:String, exactSymbol:String):OcamlRuntimeReference {
		return reference(id, requestedPlanRevision, OcamlRuntimeUseDomain.GeneratedText, exactSymbol);
	}

	function reference(id:String, requestedPlanRevision:String, domain:OcamlRuntimeUseDomain, exactSymbol:String):OcamlRuntimeReference {
		if (sealed)
			throw 'Cannot authorize runtime use $id after reconciliation sealed this plan.';
		final occurrence = occurrencesById.get(id);
		if (occurrence == null)
			throw 'unknown runtime use $id.';
		if (requestedPlanRevision != planRevision || occurrence.planRevision != requestedPlanRevision)
			throw 'stale runtime use $id: expected plan $planRevision, received $requestedPlanRevision.';
		if (occurrence.domain != domain)
			throw 'runtime use $id has the wrong target domain: planned ${occurrence.domain}, requested $domain.';
		if (occurrence.exactSymbol != exactSymbol)
			throw 'runtime use $id requested the wrong target symbol $exactSymbol; expected ${occurrence.exactSymbol}.';
		if (!occurrence.profileEligibility.contains(activeProfile))
			throw 'runtime use $id is not eligible for profile $activeProfile.';
		validateRequirement(occurrence);
		if (constructed.exists(id))
			throw 'Runtime use $id was constructed more than once.';
		constructed.set(id, true);
		final result = new OcamlRuntimeReference(id, requestedPlanRevision, occurrence.ownerId, domain, exactSymbol);
		receipts.push({
			id: id,
			planRevision: requestedPlanRevision,
			ownerId: occurrence.ownerId,
			domain: domain,
			exactSymbol: exactSymbol
		});
		return result;
	}

	function validateRequirement(occurrence:OcamlRuntimeUseOccurrence):Void {
		final requirement = requirementsById.get(occurrence.requirementId);
		if (requirement == null)
			throw 'Runtime use ${occurrence.id} has no exact requirement ${occurrence.requirementId}.';
		if (!requirement.profileEligibility.contains(activeProfile))
			throw 'Runtime requirement ${requirement.id} is not eligible for profile $activeProfile.';
		final separator = occurrence.exactSymbol.indexOf(".");
		final directRoot = separator < 0 ? occurrence.exactSymbol : occurrence.exactSymbol.substr(0, separator);
		if (!requirement.rootModules.contains(directRoot))
			throw 'Runtime use ${occurrence.id} requires direct runtime root $directRoot, but ${requirement.id} declares ${requirement.rootModules.join(",")}.';
	}

	/** Returns construction receipts in planned order for diagnostics and tests. */
	public function receiptsSorted():Array<OcamlRuntimeUseReceipt> {
		final byId:Map<String, OcamlRuntimeUseReceipt> = [];
		for (receipt in receipts)
			byId.set(receipt.id, receipt);
		final out:Array<OcamlRuntimeUseReceipt> = [];
		for (occurrence in occurrencesInOrder) {
			final receipt = byId.get(occurrence.id);
			if (receipt != null)
				out.push(receipt);
		}
		return out;
	}

	/**
		Seals the authority and checks the completed structured expression.

		The printer is deliberately not involved. A plain private reference, a
		missing or duplicate use, stale provenance, or owner-local reordering fails
		here, before any OCaml text can be published.
	**/
	public function reconcileExpression(expression:OcamlExpr):Void {
		beginReconciliation();
		final errors:Array<String> = [];
		final observedIds:Array<String> = [];
		final counts:Map<String, Int> = [];

		OcamlASTTraversal.walkExprPre(expression, current -> switch (current) {
			case ERuntimeIdent(reference):
				observeReference(reference, observedIds, counts, errors);
			case EIdent(name) if (isPlainPrivateReference(name) || isPlannedExactReference(name)):
				errors.push('plain private runtime reference $name');
			case EField(EIdent(moduleName), field) if (isPlainPrivateReference(moduleName + "." + field)
				|| isPlannedExactReference(moduleName + "." + field)):
				errors.push('plain private runtime reference $moduleName.$field');
			case _:
		}, current -> switch (current) {
			case PRuntimeConstructor(reference, _):
				observeReference(reference, observedIds, counts, errors);
			case PConstructor(name, _) if (isPlainPrivateReference(name) || isPlannedExactReference(name)):
				errors.push('plain private runtime reference $name');
			case _:
		}, current -> switch (current) {
			case TRuntimeIdent(reference) | TRuntimeApp(reference, _):
				observeReference(reference, observedIds, counts, errors);
			case TIdent(name) | TApp(name, _) if (isPlainPrivateReference(name) || isPlannedExactReference(name)):
				errors.push('plain private runtime reference $name');
			case _:
		});
		finishReconciliation(observedIds, counts, errors);
	}

	/** Seals and reconciles one complete private-runtime type subtree. */
	public function reconcileType(type:OcamlTypeExpr):Void {
		beginReconciliation();
		final errors:Array<String> = [];
		final observedIds:Array<String> = [];
		final counts:Map<String, Int> = [];
		OcamlASTTraversal.walkTypePre(type, current -> switch (current) {
			case TRuntimeIdent(reference) | TRuntimeApp(reference, _):
				observeReference(reference, observedIds, counts, errors);
			case TIdent(name) | TApp(name, _) if (isPlainPrivateReference(name) || isPlannedExactReference(name)):
				errors.push('plain private runtime reference $name');
			case _:
		});
		finishReconciliation(observedIds, counts, errors);
	}

	/**
		Seals and reconciles the runtime placeholders in one generated text record.

		The checked text builder separately proves that each placeholder occurs in
		OCaml code rather than inside a string or comment. This method owns the same
		identity, requirement, cardinality, and owner-local order checks used by the
		structured target tree.
	**/
	public function reconcileGeneratedText(references:Array<OcamlRuntimeReference>):Void {
		beginReconciliation();
		final errors:Array<String> = [];
		final observedIds:Array<String> = [];
		final counts:Map<String, Int> = [];
		for (reference in references)
			observeReference(reference, observedIds, counts, errors);
		finishReconciliation(observedIds, counts, errors);
	}

	function beginReconciliation():Void {
		if (sealed)
			throw "Runtime-use authority can reconcile its plan only once.";
		sealed = true;
	}

	function observeReference(reference:OcamlRuntimeReference, observedIds:Array<String>, counts:Map<String, Int>, errors:Array<String>):Void {
		final occurrence = occurrencesById.get(reference.id);
		if (occurrence == null) {
			errors.push('unknown runtime use ${reference.id}');
		} else if (reference.planRevision != planRevision) {
			errors.push('stale runtime use ${reference.id}: expected plan $planRevision, received ${reference.planRevision}');
		} else if (reference.ownerId != occurrence.ownerId) {
			errors.push('runtime use ${reference.id} has the wrong owner ${reference.ownerId}; expected ${occurrence.ownerId}');
		} else if (reference.domain != occurrence.domain) {
			errors.push('runtime use ${reference.id} has the wrong target domain');
		} else if (reference.exactSymbol != occurrence.exactSymbol) {
			errors.push('runtime use ${reference.id} has the wrong target symbol ${reference.exactSymbol}');
		} else {
			observedIds.push(reference.id);
			final previousCount = counts.get(reference.id);
			counts.set(reference.id, (previousCount == null ? 0 : previousCount) + 1);
			validateRequirementForReconciliation(occurrence, errors);
		}
	}

	function finishReconciliation(observedIds:Array<String>, counts:Map<String, Int>, errors:Array<String>):Void {
		for (occurrence in occurrencesInOrder) {
			final observedCount = counts.get(occurrence.id);
			final count = observedCount == null ? 0 : observedCount;
			if (count > occurrence.cardinality)
				errors.push('duplicate runtime use ${occurrence.id}');
		}
		for (occurrence in occurrencesInOrder) {
			final observedCount = counts.get(occurrence.id);
			final count = observedCount == null ? 0 : observedCount;
			if (count < occurrence.cardinality)
				errors.push('missing runtime use ${occurrence.id}');
		}
		final expectedIds = occurrencesInOrder.map(occurrence -> occurrence.id);
		if (observedIds.join("|") != expectedIds.join("|"))
			errors.push('runtime use order ${observedIds.join(",")} does not match planned owner-local order ${expectedIds.join(",")}');
		if (errors.length > 0)
			throw "OCaml runtime-use reconciliation failed: " + errors.join("; ") + ".";
		if (finalOutputAuthority != null)
			finalOutputAuthority.acceptReconciledPlan(planRevision, activeProfile, occurrencesInOrder);
	}

	function validateRequirementForReconciliation(occurrence:OcamlRuntimeUseOccurrence, errors:Array<String>):Void {
		try {
			validateRequirement(occurrence);
		} catch (error:Dynamic) {
			errors.push(Std.string(error));
		}
	}

	/**
		Reports whether this sealed plan owns the exact plain name being inspected.

		Some private names still have legacy sites that are not migrated yet, so they
		cannot enter the global reserved-name list all at once. A plan can still reject
		an unproven plain copy of its own symbol without changing those unrelated sites.
	**/
	function isPlannedExactReference(name:String):Bool {
		for (occurrence in occurrencesInOrder)
			if (occurrence.exactSymbol == name)
				return true;
		return false;
	}

	/**
		Reports whether an unchecked name belongs to the migrated private-runtime set.

		The string switch is also a compile-time performance boundary. Expressing this
		closed set as one long Boolean `or` chain makes Haxe 4.3.7 null-safety explore
		a rapidly growing number of condition paths before it can check this class.
	**/
	public static function isPlainPrivateReference(name:String):Bool {
		return switch (name) {
			case "HxInt.add", "HxArray.set", "HxArray.create", "HxArray.push", "HxAnon.get", "HxAnon.set", "HxRuntime.box_bool", "HxRuntime.Hx_break",
				"HxRuntime.Hx_continue", "HxRuntime.unbox_bool_or_obj", "HxIterator.hasNext", "HxIterator.next", "HxBytes.fill", "HxBytes.blit",
				"HxBytes.get", "HxBytes.set", "HxBytes.getUInt16", "HxBytes.setUInt16", "HxBytes.getInt32", "HxBytes.setInt32", "HxBytes.getInt64",
				"HxBytes.setInt64", "HxBytes.getFloat", "HxBytes.setFloat", "HxBytes.getDouble", "HxBytes.setDouble", "HxBytes.getData", "HxBytes.fastGet",
				"HxBytes.requireMultiByteInt", "HxBytes.length", "HxBytes.sub", "HxBytes.compare", "HxBytes.getString", "HxBytes.toString", "HxBytes.toHex",
				"HxBytes.create", "HxBytes.alloc", "HxBytes.ofString", "HxBytes.ofData", "HxBytes.ofHex", "HxString.hx_null_string",
				"HxRuntime.nullable_int_unwrap", "HxRuntime.is_null", "HxRuntime.hx_throw_typed", "HxRuntime.tags_has":
				true;
			case _:
				false;
		}
	}
}
#end
