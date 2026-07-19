package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlAssignmentResultKind;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredConversionKind;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredPlaceKind;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredSimpleAssignment;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlPlaceOccurrenceRole;

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
				case _:
			}
			TypedExprTools.iter(current, visit);
		}
		visit(expression);
		return found;
	}

	public static function validate(plan:OcamlLoweredSimpleAssignment):Array<String> {
		final errors:Array<String> = [];
		if (plan.id.length == 0 || plan.originId.length == 0 || plan.place.id.length == 0)
			errors.push("stable node, origin, and place identities are required");
		if (plan.semanticTypeId != "Int" || plan.carrierTypeId != "int")
			errors.push("the first slice only admits semantic Int on the OCaml int carrier");
		if (plan.place.kind != OcamlLoweredPlaceKind.InstanceField)
			errors.push("the first slice only admits instance-field places");
		if (plan.place.targetSymbolId.length == 0
			|| plan.place.representationId.length == 0
			|| plan.place.receiverRepresentationId.length == 0)
			errors.push("target symbol and representation decisions require stable identities");
		if (plan.place.representationReason.length == 0 || plan.place.receiverRepresentationReason.length == 0)
			errors.push("representation decisions require maintenance-readable reasons");
		if (plan.conversion != OcamlLoweredConversionKind.Identity)
			errors.push("the first slice requires an identity assignment conversion");
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
			for (index in 0...expected.length) {
				final occurrence = plan.schedule[index];
				if (occurrence.role != expected[index])
					errors.push("occurrence " + index + " has the wrong evaluation role");
				if (occurrence.occurrenceCount != 1)
					errors.push("occurrence " + index + " must execute exactly once in this admitted family");
			}
		}
		if (plan.runtimeRequirementIds.length != 0)
			errors.push("direct Int record-field assignment must not require compatibility runtime support");
		if (containsUnsealedAdmittedPlace(plan.receiver) || containsUnsealedAdmittedPlace(plan.rightHandSide))
			errors.push("an admitted nested assignment is hidden inside an unsealed source-shaped child");
		return errors;
	}
}
#end
