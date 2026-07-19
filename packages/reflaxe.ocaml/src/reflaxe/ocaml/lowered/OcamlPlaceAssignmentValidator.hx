package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlAssignmentResultKind;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredCompoundAssignment;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredConversionKind;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredInstanceFieldPlace;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredIntOperator;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredIntUpdate;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredPlaceKind;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredSimpleAssignment;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredStaticFieldAccess;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredStaticSimpleAssignment;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredUpdateFixity;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredUpdateOperator;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlPlaceOccurrenceRole;

private typedef OcamlPlaceValidationFacts = {
	final id:String;
	final originId:String;
	final semanticTypeId:String;
	final carrierTypeId:String;
	final place:OcamlLoweredInstanceFieldPlace;
	final conversion:OcamlLoweredConversionKind;
}

/** Checks semantic completeness before an admitted plan reaches target syntax. */
class OcamlPlaceAssignmentValidator {
	static function containsUnsealedAdmittedPlace(expression:TypedExpr):Bool {
		var found = false;
		function visit(current:TypedExpr):Void {
			if (found)
				return;
			switch (current.expr) {
				case TMeta(metadata, _) if (OcamlLoweredOrigin.readPlaceId(metadata) != null):
					// A nested admitted operation has its own stable node and will be
					// recursively lowered when the emitter visits this child.
					return;
				case TBinop(OpAssign, left, right) if (OcamlPlaceInputPolicy.admitsSimpleInstanceField(left, right)):
					found = true;
					return;
				case TBinop(OpAssignOp(operation), left, right) if (OcamlPlaceInputPolicy.admitsCompoundIntAddInstanceField(operation, left, right)):
					found = true;
					return;
				case TUnop(operation, _, operand) if (OcamlPlaceInputPolicy.admitsIntUpdateInstanceField(operation, operand)):
					found = true;
					return;
				case _:
			}
			TypedExprTools.iter(current, visit);
		}
		visit(expression);
		return found;
	}

	static function validateIdentityAndPlace(plan:OcamlPlaceValidationFacts):Array<String> {
		final errors:Array<String> = [];
		if (plan.id.length == 0 || plan.originId.length == 0 || plan.place.id.length == 0)
			errors.push("stable node, origin, and place identities are required");
		if (plan.semanticTypeId != "Int" || plan.carrierTypeId != "int")
			errors.push("the first slice only admits semantic Int on the OCaml int carrier");
		if (plan.place.semanticTypeId != plan.semanticTypeId || plan.place.carrierTypeId != plan.carrierTypeId)
			errors.push("place and expression semantic/carrier types must agree in the first slice");
		if (plan.place.kind != OcamlLoweredPlaceKind.InstanceField)
			errors.push("the first slice only admits instance-field places");
		if (plan.place.targetSymbolId.length == 0
			|| plan.place.representationId.length == 0
			|| plan.place.receiverRepresentationId.length == 0)
			errors.push("target symbol and representation decisions require stable identities");
		if (plan.place.representationReason.length == 0 || plan.place.receiverRepresentationReason.length == 0)
			errors.push("representation decisions require maintenance-readable reasons");
		if (plan.place.receiverSemanticTypeId.length == 0 || plan.place.receiverCarrierTypeId.length == 0)
			errors.push("receiver semantic and carrier types are required");
		if (plan.conversion != OcamlLoweredConversionKind.Identity)
			errors.push("the first slice requires an identity assignment conversion");
		return errors;
	}

	public static function validateSimple(plan:OcamlLoweredSimpleAssignment):Array<String> {
		final errors = validateIdentityAndPlace(plan);
		if (plan.result != OcamlAssignmentResultKind.AssignedValue)
			errors.push("simple assignment must return its assigned value");

		final expected = [
			OcamlPlaceOccurrenceRole.Receiver,
			OcamlPlaceOccurrenceRole.RightHandSide,
			OcamlPlaceOccurrenceRole.Store,
			OcamlPlaceOccurrenceRole.Result
		];
		if (plan.schedule.length != expected.length) {
			errors.push("simple field assignment requires receiver, rhs, store, and result occurrences");
		} else {
			final expectedSharing = ["receiver", "rhs", null, "rhs"];
			for (index in 0...expected.length) {
				final occurrence = plan.schedule[index];
				if (occurrence.role != expected[index])
					errors.push("occurrence " + index + " has the wrong evaluation role");
				if (occurrence.occurrenceCount != 1)
					errors.push("occurrence " + index + " must execute exactly once in this admitted family");
				if (occurrence.sharedAs != expectedSharing[index])
					errors.push("occurrence " + index + " has the wrong simple-assignment sharing identity");
			}
		}
		if (plan.runtimeRequirementIds.length != 0)
			errors.push("direct Int record-field assignment must not require compatibility runtime support");
		if (containsUnsealedAdmittedPlace(plan.receiver) || containsUnsealedAdmittedPlace(plan.rightHandSide))
			errors.push("an admitted nested assignment is hidden inside an unsealed source-shaped child");
		return errors;
	}

	/** Validates a receiver-free static ref assignment and its selected symbol access. */
	public static function validateStaticSimple(plan:OcamlLoweredStaticSimpleAssignment):Array<String> {
		final errors:Array<String> = [];
		if (plan.id.length == 0 || plan.originId.length == 0 || plan.place.id.length == 0)
			errors.push("stable node, origin, and static-place identities are required");
		if (plan.semanticTypeId != "Int" || plan.carrierTypeId != "int")
			errors.push("the first static slice only admits semantic Int on the OCaml int carrier");
		if (plan.place.semanticTypeId != plan.semanticTypeId || plan.place.carrierTypeId != plan.carrierTypeId)
			errors.push("static place and expression semantic/carrier types must agree");
		if (plan.place.kind != OcamlLoweredPlaceKind.StaticField)
			errors.push("the static assignment slice requires a static-field place");
		if (plan.place.targetSymbolId.length == 0
			|| plan.place.targetModuleName.length == 0
			|| plan.place.targetValueName.length == 0
			|| plan.place.representationId.length == 0)
			errors.push("static symbol and representation decisions require stable names and identities");
		if (plan.place.representationReason.length == 0)
			errors.push("the static representation decision requires a maintenance-readable reason");
		if (plan.place.staticAccess != OcamlLoweredStaticFieldAccess.Local
			&& plan.place.staticAccess != OcamlLoweredStaticFieldAccess.Qualified)
			errors.push("static access must be selected as local or qualified before syntax construction");
		if (plan.place.forwardDeclarationRequired)
			errors.push("same-module cross-type static storage requires the program-level declaration plan before this family can be admitted");
		if (plan.conversion != OcamlLoweredConversionKind.Identity)
			errors.push("the first static slice requires an identity assignment conversion");
		if (plan.result != OcamlAssignmentResultKind.AssignedValue)
			errors.push("static simple assignment must return its assigned value");

		final expected = [
			OcamlPlaceOccurrenceRole.RightHandSide,
			OcamlPlaceOccurrenceRole.Store,
			OcamlPlaceOccurrenceRole.Result
		];
		if (plan.schedule.length != expected.length) {
			errors.push("static simple assignment requires rhs, store, and result occurrences without a receiver");
		} else {
			final expectedSharing = ["rhs", null, "rhs"];
			for (index in 0...expected.length) {
				final occurrence = plan.schedule[index];
				if (occurrence.role != expected[index])
					errors.push("occurrence " + index + " has the wrong static-assignment evaluation role");
				if (occurrence.occurrenceCount != 1)
					errors.push("occurrence " + index + " must execute exactly once in the static assignment family");
				if (occurrence.sharedAs != expectedSharing[index])
					errors.push("occurrence " + index + " has the wrong static-assignment sharing identity");
			}
			if (plan.schedule[1].sourceId != plan.place.id)
				errors.push("the static store must refer to the sealed static place");
			if (plan.schedule[0].sourceId != plan.schedule[2].sourceId)
				errors.push("the static assignment result must reuse the evaluated RHS");
		}
		if (plan.runtimeRequirementIds.length != 0)
			errors.push("direct Int static ref assignment must not require compatibility runtime support");
		if (containsUnsealedAdmittedPlace(plan.rightHandSide))
			errors.push("an admitted nested assignment is hidden inside an unsealed static-assignment RHS");
		return errors;
	}

	/** Validates the exact load-before-RHS schedule and runtime intent for `+=`. */
	public static function validateCompoundIntAdd(plan:OcamlLoweredCompoundAssignment):Array<String> {
		final errors = validateIdentityAndPlace(plan);
		if (plan.operation != OcamlLoweredIntOperator.Add)
			errors.push("the first compound slice only admits ordinary primitive-Int addition");
		if (plan.result != OcamlAssignmentResultKind.ComputedValue)
			errors.push("compound assignment must return its computed and stored value");

		final expected = [
			OcamlPlaceOccurrenceRole.Receiver,
			OcamlPlaceOccurrenceRole.Load,
			OcamlPlaceOccurrenceRole.RightHandSide,
			OcamlPlaceOccurrenceRole.Operator,
			OcamlPlaceOccurrenceRole.Store,
			OcamlPlaceOccurrenceRole.Result
		];
		if (plan.schedule.length != expected.length) {
			errors.push("compound field assignment requires receiver, load, rhs, operator, store, and result occurrences");
		} else {
			final expectedSharing = ["receiver", "old_value", "rhs", "new_value", null, "new_value"];
			for (index in 0...expected.length) {
				final occurrence = plan.schedule[index];
				if (occurrence.role != expected[index])
					errors.push("occurrence " + index + " has the wrong compound evaluation role");
				if (occurrence.occurrenceCount != 1)
					errors.push("occurrence " + index + " must execute exactly once in this admitted family");
				if (occurrence.sharedAs != expectedSharing[index])
					errors.push("occurrence " + index + " has the wrong compound-assignment sharing identity");
			}
			if (plan.schedule[1].sourceId != plan.schedule[4].sourceId)
				errors.push("compound load and store must refer to the same original place");
			if (plan.schedule[3].sourceId != plan.schedule[5].sourceId)
				errors.push("compound result must reuse the computed operator value");
		}
		final expectedRuntimeId = plan.originId + ":runtime:haxe-int32-add";
		if (plan.runtimeRequirementIds.length != 1 || plan.runtimeRequirementIds[0] != expectedRuntimeId)
			errors.push("primitive-Int += must record its Haxe Int addition runtime requirement");
		if (containsUnsealedAdmittedPlace(plan.receiver) || containsUnsealedAdmittedPlace(plan.rightHandSide))
			errors.push("an admitted nested assignment is hidden inside an unsealed source-shaped child");
		return errors;
	}

	/** Validates exact update token/fixity, mutation order, and old/new result choice. */
	public static function validateIntUpdate(plan:OcamlLoweredIntUpdate):Array<String> {
		final errors = validateIdentityAndPlace(plan);
		final expectedDelta = if (plan.sourceOperator == OcamlLoweredUpdateOperator.Increment) {
			1;
		} else if (plan.sourceOperator == OcamlLoweredUpdateOperator.Decrement) {
			-1;
		} else {
			errors.push("ordinary primitive-Int updates require an increment or decrement source token");
			0;
		}
		if (plan.operation != OcamlLoweredIntOperator.Add || plan.delta != expectedDelta)
			errors.push("ordinary primitive-Int updates require Haxe Int addition with the token-selected delta");
		final expectedResult = plan.fixity == OcamlLoweredUpdateFixity.Postfix ? OcamlAssignmentResultKind.OldValue : OcamlAssignmentResultKind.ComputedValue;
		if (plan.result != expectedResult)
			errors.push("postfix update must return the old value and prefix update the computed value");

		final expected = [
			OcamlPlaceOccurrenceRole.Receiver,
			OcamlPlaceOccurrenceRole.Load,
			OcamlPlaceOccurrenceRole.Operator,
			OcamlPlaceOccurrenceRole.Store,
			OcamlPlaceOccurrenceRole.Result
		];
		if (plan.schedule.length != expected.length) {
			errors.push("field update requires receiver, load, operator, store, and result occurrences");
		} else {
			final resultSharing = plan.fixity == OcamlLoweredUpdateFixity.Postfix ? "old_value" : "new_value";
			final expectedSharing = ["receiver", "old_value", "new_value", null, resultSharing];
			for (index in 0...expected.length) {
				final occurrence = plan.schedule[index];
				if (occurrence.role != expected[index])
					errors.push("occurrence " + index + " has the wrong update evaluation role");
				if (occurrence.occurrenceCount != 1)
					errors.push("occurrence " + index + " must execute exactly once in this admitted family");
				if (occurrence.sharedAs != expectedSharing[index])
					errors.push("occurrence " + index + " has the wrong update sharing identity");
			}
			if (plan.schedule[1].sourceId != plan.schedule[3].sourceId)
				errors.push("update load and store must refer to the same original place");
			final expectedResultSource = plan.fixity == OcamlLoweredUpdateFixity.Postfix ? plan.originId + ":old-value" : plan.schedule[2].sourceId;
			if (plan.schedule[4].sourceId != expectedResultSource)
				errors.push("update result must reuse the fixity-selected old or computed value");
		}
		final expectedRuntimeId = plan.originId + ":runtime:haxe-int32-add";
		if (plan.runtimeRequirementIds.length != 1 || plan.runtimeRequirementIds[0] != expectedRuntimeId)
			errors.push("primitive-Int update must record its Haxe Int addition runtime requirement");
		if (containsUnsealedAdmittedPlace(plan.receiver))
			errors.push("an admitted nested assignment or update is hidden inside an unsealed source-shaped child");
		return errors;
	}
}
#end
