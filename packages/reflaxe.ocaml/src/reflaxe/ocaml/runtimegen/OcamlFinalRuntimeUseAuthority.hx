package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime || eval)
import reflaxe.ocaml.ast.OcamlASTTraversal;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlModuleItem;
import reflaxe.ocaml.ast.OcamlPat;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.ast.OcamlTypeDeclKind;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeReference;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

using StringTools;

private typedef OcamlFinalRuntimeUseExpected = {
	final occurrence:OcamlRuntimeUseOccurrence;
	final activeProfile:String;
}

/**
	Checks how many authorized private-runtime references reach final OCaml output.

	A lowering plan first passes its smaller local check. Only then may it register
	its immutable occurrence facts here. Final module trees and checked generated
	text are observed at their last structured boundary, before printing or file
	writes discard the hidden occurrence identities.

	This authority is owned by one compiler request. It retains target-plan facts,
	not Haxe compiler expressions, and rendered OCaml text never grants permission.
**/
class OcamlFinalRuntimeUseAuthority {
	var programRevision:Null<String>;
	var activeProfile:Null<String>;
	var sealed:Bool = false;
	final expectedByKey:Map<String, OcamlFinalRuntimeUseExpected> = [];
	final expectedByOwner:Map<String, Array<OcamlRuntimeUseOccurrence>> = [];
	final expectedOrderByOwner:Map<String, Map<Int, String>> = [];
	final observedCounts:Map<String, Int> = [];
	final observedIdsByOwner:Map<String, Array<String>> = [];
	final firstObservationByKey:Map<String, String> = [];

	public function new() {}

	/** Clears all prior request facts and binds the ledger to one target profile. */
	public function beginProgram(programRevision:String, activeProfile:String):Void {
		if (programRevision == null || programRevision.length == 0)
			throw "Final runtime-use authority requires a non-empty program revision.";
		if (activeProfile == null || activeProfile.length == 0)
			throw "Final runtime-use authority requires a non-empty target profile.";
		this.programRevision = programRevision;
		this.activeProfile = activeProfile;
		sealed = false;
		expectedByKey.clear();
		expectedByOwner.clear();
		expectedOrderByOwner.clear();
		observedCounts.clear();
		observedIdsByOwner.clear();
		firstObservationByKey.clear();
	}

	/**
		Accepts one plan only after its local expression or generated-text check passed.

		The defensive copies prevent a caller from changing owner, order, profile, or
		cardinality after the plan becomes part of the final-output contract.
	**/
	@:allow(reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority)
	function acceptReconciledPlan(planRevision:String, planProfile:String, occurrences:Array<OcamlRuntimeUseOccurrence>):Void {
		requireOpen();
		if (planProfile != activeProfile)
			throw 'Final runtime-use plan profile $planProfile does not match request profile $activeProfile.';
		for (source in occurrences) {
			if (source.planRevision != planRevision)
				throw 'Final runtime use ${source.id} has stale plan revision ${source.planRevision}; expected $planRevision.';
			if (!source.profileEligibility.contains(planProfile))
				throw 'Final runtime use ${source.id} is not eligible for profile $planProfile.';
			if (source.cardinality != 1)
				throw 'Final runtime use ${source.id} must have cardinality 1.';
			registerExpected(planRevision, planProfile, copyOccurrence(source));
		}
	}

	/**
		Declares one intentional compiler-output copy of an accepted expression.

		Some OCaml scaffolding repeats a Haxe-authored body in two target functions.
		For example, a class constructor body appears in both `create` and the
		dispatch constructor used by `super()`. Reusing the same hidden runtime ID
		would spend one permission twice. This operation clones only already-accepted
		references and gives the second output site its own exact identities. The
		optional callback prepares a staged reference before this class copies it. If
		the copied subtree already contains one source reference more than once, each
		occurrence receives a stable numbered identity within this copy operation.
	**/
	public function copyExpressionForOutput(expression:OcamlExpr, outputRole:String, ?beforeReference:OcamlRuntimeReference->Void):OcamlExpr {
		requireOpen();
		final stableRole = requiredOutputRole(outputRole);
		final copiedSourceKeys:Map<String, Bool> = [];
		final copyCountsBySource:Map<String, Int> = [];
		function copy(reference:OcamlRuntimeReference):OcamlRuntimeReference {
			final sourceKey = occurrenceKey(reference.planRevision, reference.id);
			final previousCount = copyCountsBySource.get(sourceKey);
			final count = previousCount == null ? 0 : previousCount;
			copyCountsBySource.set(sourceKey, count + 1);
			final copyRole = count == 0 ? stableRole : '$stableRole:repeat:$count';
			return copyReferenceForOutput(reference, copyRole, copiedSourceKeys, beforeReference);
		}
		final copiedExpression = OcamlASTTraversal.mapExprTree(expression, current -> switch (current) {
			case ERuntimeIdent(reference):
				ERuntimeIdent(copy(reference));
			case _:
				current;
		}, pattern -> switch (pattern) {
			case PRuntimeConstructor(reference, args):
				PRuntimeConstructor(copy(reference), args);
			case _:
				pattern;
		}, type -> switch (type) {
			case TRuntimeIdent(reference):
				TRuntimeIdent(copy(reference));
			case TRuntimeApp(reference, params):
				TRuntimeApp(copy(reference), params);
			case _:
				type;
		});
		OcamlASTTraversal.walkExprPre(copiedExpression, current -> switch (current) {
			case ERuntimeIdent(reference):
				if (copiedSourceKeys.exists(occurrenceKey(reference.planRevision,
					reference.id))) throw 'Final runtime-use output copy $stableRole retained original occurrence ${reference.id}.';
			case _:
		}, current -> switch (current) {
			case PRuntimeConstructor(reference, _):
				if (copiedSourceKeys.exists(occurrenceKey(reference.planRevision,
					reference.id))) throw 'Final runtime-use output copy $stableRole retained original occurrence ${reference.id}.';
			case _:
		}, current -> switch (current) {
			case TRuntimeIdent(reference) | TRuntimeApp(reference, _):
				if (copiedSourceKeys.exists(occurrenceKey(reference.planRevision,
					reference.id))) throw 'Final runtime-use output copy $stableRole retained original occurrence ${reference.id}.';
			case _:
		});
		return copiedExpression;
	}

	/**
		Gives repeated references of one selected role separate output identities.

		Haxe can place one typed occurrence more than once in the final function tree.
		For example, control-flow expansion can repeat an early return, and inline
		expansion can repeat one String-null check. The first reference still represents
		that source occurrence. Each later reference is a distinct generated output site
		and receives a checked copy. Callers must use this only after a complete output
		owner, such as one function body, has been assembled. References with every other
		role remain unchanged, so the final-output walk still rejects unexplained
		duplicates.
	**/
	public function distinctRepeatedRoleReferencesForOutput(expression:OcamlExpr, occurrenceRole:String, outputRole:String,
			?beforeReference:OcamlRuntimeReference->Void):OcamlExpr {
		requireOpen();
		final requiredRole = requiredOutputRole(occurrenceRole);
		final stableRole = requiredOutputRole(outputRole);
		final countsBySource:Map<String, Int> = [];
		function distinct(reference:OcamlRuntimeReference):OcamlRuntimeReference {
			final sourceKey = occurrenceKey(reference.planRevision, reference.id);
			final sourceExpected = expectedByKey.get(sourceKey);
			if (sourceExpected == null || sourceExpected.occurrence.role != requiredRole)
				return reference;
			final previousCount = countsBySource.get(sourceKey);
			final count = previousCount == null ? 0 : previousCount;
			countsBySource.set(sourceKey, count + 1);
			if (count == 0)
				return reference;
			return copyReferenceForOutput(reference, '$stableRole:repeat:$count', [], beforeReference);
		}
		return OcamlASTTraversal.mapExprTree(expression, current -> switch (current) {
			case ERuntimeIdent(reference): ERuntimeIdent(distinct(reference));
			case _: current;
		}, pattern -> switch (pattern) {
			case PRuntimeConstructor(reference, args): PRuntimeConstructor(distinct(reference), args);
			case _: pattern;
		}, type -> switch (type) {
			case TRuntimeIdent(reference): TRuntimeIdent(distinct(reference));
			case TRuntimeApp(reference, params): TRuntimeApp(distinct(reference), params);
			case _: type;
		});
	}

	/** Copies one already-accepted private name into a separately counted output site. */
	function copyReferenceForOutput(reference:OcamlRuntimeReference, stableRole:String, copiedSourceKeys:Map<String, Bool>,
			beforeReference:Null<OcamlRuntimeReference->Void>):OcamlRuntimeReference {
		if (beforeReference != null)
			beforeReference(reference);
		final sourceExpected = expectedByKey.get(occurrenceKey(reference.planRevision, reference.id));
		if (sourceExpected == null)
			throw 'Cannot copy unplanned final runtime use ${reference.id} for output role $stableRole.';
		final source = sourceExpected.occurrence;
		if (reference.ownerId != source.ownerId || reference.domain != source.domain || reference.exactSymbol != source.exactSymbol)
			throw 'Cannot copy corrupted final runtime use ${reference.id} for output role $stableRole.';
		copiedSourceKeys.set(occurrenceKey(reference.planRevision, reference.id), true);
		final copied:OcamlRuntimeUseOccurrence = {
			id: source.id + ":output-copy:" + stableRole,
			planRevision: source.planRevision,
			ownerId: source.ownerId + ":output-copy:" + stableRole,
			requirementId: source.requirementId,
			domain: source.domain,
			exactSymbol: source.exactSymbol,
			role: source.role + ":output-copy:" + stableRole,
			order: source.order,
			source: {
				file: source.source.file,
				min: source.source.min,
				max: source.source.max
			},
			profileEligibility: source.profileEligibility.copy(),
			cardinality: source.cardinality
		};
		registerExpected(copied.planRevision, sourceExpected.activeProfile, copied);
		return new OcamlRuntimeReference(copied.id, copied.planRevision, copied.ownerId, copied.domain, copied.exactSymbol);
	}

	/**
		Observes every runtime reference in one complete structured module.

		The optional callback runs before each observation. A caller can use it to
		activate a checked, request-local plan that was not known to reach output.
	**/
	public function observeModuleItems(items:Array<OcamlModuleItem>, ?outputUnitId:String, ?beforeReference:OcamlRuntimeReference->Void):Void {
		requireOpen();
		final unitId = outputUnitId == null ? "anonymous-structured-output" : requiredOutputRole(outputUnitId);
		for (item in items)
			switch (item) {
				case ILet(bindings, _):
					for (binding in bindings)
						observeExpression(binding.expr, unitId + "::let:" + binding.name, beforeReference);
				case IType(declarations, _):
					for (declaration in declarations) {
						final location = unitId + "::type:" + declaration.name;
						switch (declaration.kind) {
							case Alias(type):
								observeType(type, location, beforeReference);
							case Record(fields):
								for (field in fields)
									observeType(field.typ, location + "::field:" + field.name, beforeReference);
							case Variant(constructors):
								for (constructor in constructors)
									for (argument in constructor.args)
										observeType(argument, location + "::constructor:" + constructor.name, beforeReference);
						}
					}
			}
	}

	/** Observes checked private names stored in one final OCaml type tree. */
	function observeType(type:OcamlTypeExpr, outputLocation:String, beforeReference:Null<OcamlRuntimeReference->Void>):Void {
		OcamlASTTraversal.walkTypePre(type, current -> switch (current) {
			case TRuntimeIdent(reference) | TRuntimeApp(reference, _):
				if (beforeReference != null)
					beforeReference(reference);
				observeReference(reference, outputLocation);
			case _:
		});
	}

	/**
		Observes one final structured expression before its hidden identities are printed.

		The optional callback has the same staged-plan contract as module observation.
	**/
	public function observeExpression(expression:OcamlExpr, ?outputLocation:String, ?beforeReference:OcamlRuntimeReference->Void):Void {
		requireOpen();
		final location = outputLocation == null ? "anonymous-structured-expression" : requiredOutputRole(outputLocation);
		OcamlASTTraversal.walkExprPre(expression, current -> switch (current) {
			case ERuntimeIdent(reference):
				if (beforeReference != null)
					beforeReference(reference);
				observeReference(reference, location);
			case _:
		}, current -> switch (current) {
			case PRuntimeConstructor(reference, _):
				if (beforeReference != null)
					beforeReference(reference);
				observeReference(reference, location);
			case _:
		}, current -> switch (current) {
			case TRuntimeIdent(reference) | TRuntimeApp(reference, _):
				if (beforeReference != null)
					beforeReference(reference);
				observeReference(reference, location);
			case _:
		});
	}

	/** Observes the hidden references retained by one checked generated-text record. */
	public function observeGeneratedText(references:Array<OcamlRuntimeReference>, ?outputLocation:String):Void {
		requireOpen();
		final location = outputLocation == null ? "anonymous-checked-generated-text" : requiredOutputRole(outputLocation);
		for (reference in references)
			observeReference(reference, location);
	}

	/** Seals the request and rejects any missing or reordered final occurrence. */
	public function finishProgram():Void {
		requireOpen();
		sealed = true;
		final errors:Array<String> = [];
		for (expected in expectedByKey) {
			final occurrence = expected.occurrence;
			final count = observedCounts.get(occurrenceKey(occurrence.planRevision, occurrence.id));
			if (count == null || count < occurrence.cardinality)
				errors.push('missing final runtime use ${occurrence.id}');
		}
		for (ownerKey => expected in expectedByOwner) {
			expected.sort(compareOccurrenceOrder);
			final expectedIds = expected.map(occurrence -> occurrence.id);
			final observed = observedIdsByOwner.get(ownerKey);
			final observedIds = observed == null ? [] : observed;
			if (observedIds.join("|") != expectedIds.join("|"))
				errors.push('final runtime use order ${observedIds.join(",")} does not match planned owner-local order ${expectedIds.join(",")}');
		}
		if (errors.length > 0)
			throw "OCaml final runtime-use reconciliation failed: " + errors.join("; ") + ".";
	}

	function observeReference(reference:OcamlRuntimeReference, outputLocation:String):Void {
		final key = occurrenceKey(reference.planRevision, reference.id);
		final expected = expectedByKey.get(key);
		if (expected == null)
			throw 'OCaml final runtime-use reconciliation failed: unplanned final runtime use ${reference.id}.';
		final occurrence = expected.occurrence;
		if (reference.ownerId != occurrence.ownerId)
			throw 'OCaml final runtime-use reconciliation failed: final runtime use ${reference.id} has wrong owner ${reference.ownerId}; expected ${occurrence.ownerId}.';
		if (reference.domain != occurrence.domain)
			throw 'OCaml final runtime-use reconciliation failed: final runtime use ${reference.id} has the wrong target domain.';
		if (reference.exactSymbol != occurrence.exactSymbol)
			throw 'OCaml final runtime-use reconciliation failed: final runtime use ${reference.id} has wrong target symbol ${reference.exactSymbol}; expected ${occurrence.exactSymbol}.';
		if (expected.activeProfile != activeProfile || !occurrence.profileEligibility.contains(cast activeProfile))
			throw 'OCaml final runtime-use reconciliation failed: final runtime use ${reference.id} has the wrong target profile.';
		final previousCount = observedCounts.get(key);
		final count = (previousCount == null ? 0 : previousCount) + 1;
		observedCounts.set(key, count);
		if (count == 1)
			firstObservationByKey.set(key, outputLocation);
		if (count > occurrence.cardinality) {
			final firstLocation = firstObservationByKey.get(key);
			throw 'OCaml final runtime-use reconciliation failed: duplicate final runtime use ${reference.id}; first observed in $firstLocation, then in $outputLocation.';
		}
		final ownerKey = ownerPlanKey(reference.planRevision, reference.ownerId);
		var observed = observedIdsByOwner.get(ownerKey);
		if (observed == null) {
			observed = [];
			observedIdsByOwner.set(ownerKey, observed);
		}
		observed.push(reference.id);
	}

	function registerExpected(planRevision:String, planProfile:String, occurrence:OcamlRuntimeUseOccurrence):Void {
		final key = occurrenceKey(planRevision, occurrence.id);
		final existing = expectedByKey.get(key);
		if (existing != null) {
			if (existing.activeProfile != planProfile || !sameOccurrence(existing.occurrence, occurrence))
				throw 'Final runtime use ${occurrence.id} was registered with conflicting facts.';
			return;
		}
		expectedByKey.set(key, {occurrence: occurrence, activeProfile: planProfile});

		final ownerKey = ownerPlanKey(planRevision, occurrence.ownerId);
		var ownerOccurrences = expectedByOwner.get(ownerKey);
		if (ownerOccurrences == null) {
			ownerOccurrences = [];
			expectedByOwner.set(ownerKey, ownerOccurrences);
		}
		var ownerOrders = expectedOrderByOwner.get(ownerKey);
		if (ownerOrders == null) {
			ownerOrders = [];
			expectedOrderByOwner.set(ownerKey, ownerOrders);
		}
		final existingOrder = ownerOrders.get(occurrence.order);
		if (existingOrder != null)
			throw 'Final runtime uses $existingOrder and ${occurrence.id} share owner-local order ${occurrence.order} for ${occurrence.ownerId}.';
		ownerOrders.set(occurrence.order, occurrence.id);
		ownerOccurrences.push(occurrence);
	}

	function requireOpen():Void {
		if (programRevision == null)
			throw "Final runtime-use authority has not started a compiler request.";
		if (sealed)
			throw "Final runtime-use authority is already sealed for this request.";
	}

	static function occurrenceKey(planRevision:String, id:String):String {
		return planRevision.length + ":" + planRevision + id.length + ":" + id;
	}

	static function ownerPlanKey(planRevision:String, ownerId:String):String {
		return planRevision.length + ":" + planRevision + ownerId.length + ":" + ownerId;
	}

	static function requiredOutputRole(value:String):String {
		final normalized = value == null ? "" : StringTools.trim(value);
		if (normalized.length == 0)
			throw "Final runtime-use output copy requires a non-empty logical role.";
		if (normalized.startsWith("/")
			|| ~/^[A-Za-z]:[\\\/]/.match(normalized)
			|| normalized.indexOf("\\") >= 0
			|| normalized.indexOf("../") >= 0)
			throw "Final runtime-use output copy role must be a logical identity, not a machine-local path.";
		return normalized;
	}

	static function compareOccurrenceOrder(left:OcamlRuntimeUseOccurrence, right:OcamlRuntimeUseOccurrence):Int {
		return left.order - right.order;
	}

	static function sameOccurrence(left:OcamlRuntimeUseOccurrence, right:OcamlRuntimeUseOccurrence):Bool {
		return left.id == right.id
			&& left.planRevision == right.planRevision
			&& left.ownerId == right.ownerId
			&& left.requirementId == right.requirementId
			&& left.domain == right.domain
			&& left.exactSymbol == right.exactSymbol
			&& left.role == right.role
			&& left.order == right.order
			&& left.source.file == right.source.file
			&& left.source.min == right.source.min
			&& left.source.max == right.source.max
			&& left.profileEligibility.join("|") == right.profileEligibility.join("|")
			&& left.cardinality == right.cardinality;
	}

	static function copyOccurrence(source:OcamlRuntimeUseOccurrence):OcamlRuntimeUseOccurrence {
		return {
			id: source.id,
			planRevision: source.planRevision,
			ownerId: source.ownerId,
			requirementId: source.requirementId,
			domain: source.domain,
			exactSymbol: source.exactSymbol,
			role: source.role,
			order: source.order,
			source: {
				file: source.source.file,
				min: source.source.min,
				max: source.source.max
			},
			profileEligibility: source.profileEligibility.copy(),
			cardinality: source.cardinality
		};
	}
}
#end
