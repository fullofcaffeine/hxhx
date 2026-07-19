package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Expr.MetadataEntry;
import haxe.macro.Expr.Binop;
import haxe.macro.Expr.Unop;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypeTools;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlAssignmentResultKind;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredCompoundAssignment;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredConversionKind;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredEffect;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredInstanceFieldPlace;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredIntOperator;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredIntUpdate;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredPlaceKind;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredSimpleAssignment;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredUpdateFixity;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredUpdateOperator;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlPlaceOccurrence;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlPlaceOccurrenceRole;

/** Builds the typed semantic plan for the first admitted assignment family. */
class OcamlPlaceAssignmentPlanner {
	final context:CompilationContext;

	public function new(context:CompilationContext) {
		this.context = context;
	}

	function planInstanceField(originId:String, left:TypedExpr):Null<{place:OcamlLoweredInstanceFieldPlace, receiver:TypedExpr}> {
		return switch (left.expr) {
			case TField(receiver, FInstance(classRef, _, fieldRef)):
				final classType = classRef.get();
				final field = fieldRef.get();
				final receiverClass = switch (receiver.t) {
					case TInst(receiverClassRef, _): receiverClassRef.get();
					case _: null;
				}
				if (receiverClass == null)
					return null;
				final moduleName = context.ocamlModuleNameForModuleId(receiverClass.module);
				final currentModuleName = context.currentModuleId == null ? null : context.ocamlModuleNameForModuleId(context.currentModuleId);
				final scopedType = context.scopedInstanceTypeName(receiverClass.module, receiverClass.name);
				final receiverCarrier = currentModuleName == moduleName ? scopedType : moduleName + "." + scopedType;
				{
					place: {
						id: originId + ":place",
						kind: OcamlLoweredPlaceKind.InstanceField,
						ownerModuleId: classType.module,
						ownerTypeName: classType.name,
						targetSymbolId: classType.module + "::" + classType.name + "::field::" + field.name,
						receiverSemanticTypeId: TypeTools.toString(receiver.t),
						receiverCarrierTypeId: receiverCarrier,
						receiverRepresentationId: originId + ":representation:receiver",
						receiverRepresentationReason: "record-backed carrier selected from the semantic receiver type; inherited field ownership remains separate",
						fieldName: field.name,
						targetFieldName: context.ocamlRecordLabel(field.name),
						semanticTypeId: TypeTools.toString(left.t),
						carrierTypeId: "int",
						representationId: originId + ":representation:field",
						representationReason: "exact Haxe Int field uses the direct OCaml int carrier"
					},
					receiver: receiver
				};
			case _: null;
		}
	}

	/** Returns `null` when a simple assignment is outside the admitted slice. */
	public function planSimpleAssignment(metadata:MetadataEntry, expression:TypedExpr, left:TypedExpr, right:TypedExpr):Null<OcamlLoweredSimpleAssignment> {
		if (!OcamlPlaceInputPolicy.admitsSimpleInstanceField(left, right))
			return null;
		final originId = OcamlLoweredOrigin.readPlaceId(metadata);
		if (originId == null)
			return null;
		final target = planInstanceField(originId, left);
		if (target == null)
			return null;
		final placeId = target.place.id;
		return {
			id: originId + ":simple-assignment",
			originId: originId,
			source: OcamlLoweredOrigin.sourceSpan(expression.pos),
			semanticTypeId: TypeTools.toString(expression.t),
			carrierTypeId: "int",
			place: target.place,
			receiver: target.receiver,
			rightHandSide: right,
			conversion: OcamlLoweredConversionKind.Identity,
			result: OcamlAssignmentResultKind.AssignedValue,
			schedule: [
				occurrence(originId, 0, OcamlPlaceOccurrenceRole.Receiver, originId + ":receiver", "receiver",
					[OcamlLoweredEffect.Read, OcamlLoweredEffect.Call, OcamlLoweredEffect.Throw]),
				occurrence(originId, 1, OcamlPlaceOccurrenceRole.RightHandSide, originId + ":rhs", "rhs",
					[OcamlLoweredEffect.Read, OcamlLoweredEffect.Call, OcamlLoweredEffect.Throw]),
				occurrence(originId, 2, OcamlPlaceOccurrenceRole.Store, placeId, null, [OcamlLoweredEffect.Write, OcamlLoweredEffect.Throw]),
				occurrence(originId, 3, OcamlPlaceOccurrenceRole.Result, originId + ":rhs", "rhs", [])
			],
			effects: [
				OcamlLoweredEffect.Read,
				OcamlLoweredEffect.Call,
				OcamlLoweredEffect.Throw,
				OcamlLoweredEffect.Write
			],
			runtimeRequirementIds: []
		};
	}

	/** Plans exact primitive-Int `+=`, including the Oracle-proven old-value load order. */
	public function planCompoundIntAdd(metadata:MetadataEntry, expression:TypedExpr, left:TypedExpr, right:TypedExpr):Null<OcamlLoweredCompoundAssignment> {
		if (!OcamlPlaceInputPolicy.admitsCompoundIntAddInstanceField(OpAdd, left, right))
			return null;
		final originId = OcamlLoweredOrigin.readPlaceId(metadata);
		if (originId == null)
			return null;
		final target = planInstanceField(originId, left);
		if (target == null)
			return null;
		final placeId = target.place.id;
		final newValueId = originId + ":new-value";
		return {
			id: originId + ":compound-assignment",
			originId: originId,
			source: OcamlLoweredOrigin.sourceSpan(expression.pos),
			semanticTypeId: TypeTools.toString(expression.t),
			carrierTypeId: "int",
			place: target.place,
			receiver: target.receiver,
			rightHandSide: right,
			operation: OcamlLoweredIntOperator.Add,
			conversion: OcamlLoweredConversionKind.Identity,
			result: OcamlAssignmentResultKind.ComputedValue,
			schedule: [
				occurrence(originId, 0, OcamlPlaceOccurrenceRole.Receiver, originId + ":receiver", "receiver",
					[OcamlLoweredEffect.Read, OcamlLoweredEffect.Call, OcamlLoweredEffect.Throw]),
				occurrence(originId, 1, OcamlPlaceOccurrenceRole.Load, placeId, "old_value", [OcamlLoweredEffect.Read, OcamlLoweredEffect.Throw]),
				occurrence(originId, 2, OcamlPlaceOccurrenceRole.RightHandSide, originId + ":rhs", "rhs",
					[OcamlLoweredEffect.Read, OcamlLoweredEffect.Call, OcamlLoweredEffect.Throw]),
				occurrence(originId, 3, OcamlPlaceOccurrenceRole.Operator, newValueId, "new_value", [OcamlLoweredEffect.Call, OcamlLoweredEffect.Throw]),
				occurrence(originId, 4, OcamlPlaceOccurrenceRole.Store, placeId, null, [OcamlLoweredEffect.Write, OcamlLoweredEffect.Throw]),
				occurrence(originId, 5, OcamlPlaceOccurrenceRole.Result, newValueId, "new_value", [])
			],
			effects: [
				OcamlLoweredEffect.Read,
				OcamlLoweredEffect.Call,
				OcamlLoweredEffect.Throw,
				OcamlLoweredEffect.Write
			],
			runtimeRequirementIds: [originId + ":runtime:haxe-int32-add"]
		};
	}

	/** Plans exact primitive-Int update without deriving result semantics in the emitter. */
	public function planIntUpdate(metadata:MetadataEntry, expression:TypedExpr, operation:Unop, postFix:Bool, operand:TypedExpr):Null<OcamlLoweredIntUpdate> {
		if (!OcamlPlaceInputPolicy.admitsIntUpdateInstanceField(operation, operand))
			return null;
		final originId = OcamlLoweredOrigin.readPlaceId(metadata);
		if (originId == null)
			return null;
		final target = planInstanceField(originId, operand);
		if (target == null)
			return null;
		final placeId = target.place.id;
		final oldValueId = originId + ":old-value";
		final newValueId = originId + ":new-value";
		final fixity = postFix ? OcamlLoweredUpdateFixity.Postfix : OcamlLoweredUpdateFixity.Prefix;
		final result = postFix ? OcamlAssignmentResultKind.OldValue : OcamlAssignmentResultKind.ComputedValue;
		if (operation != OpIncrement && operation != OpDecrement)
			return null;
		final isIncrement = operation == OpIncrement;
		final sourceOperator = isIncrement ? OcamlLoweredUpdateOperator.Increment : OcamlLoweredUpdateOperator.Decrement;
		final delta = isIncrement ? 1 : -1;
		return {
			id: originId + ":int-" + sourceOperator,
			originId: originId,
			source: OcamlLoweredOrigin.sourceSpan(expression.pos),
			semanticTypeId: TypeTools.toString(expression.t),
			carrierTypeId: "int",
			place: target.place,
			receiver: target.receiver,
			sourceOperator: sourceOperator,
			fixity: fixity,
			operation: OcamlLoweredIntOperator.Add,
			delta: delta,
			conversion: OcamlLoweredConversionKind.Identity,
			result: result,
			schedule: [
				occurrence(originId, 0, OcamlPlaceOccurrenceRole.Receiver, originId + ":receiver", "receiver",
					[OcamlLoweredEffect.Read, OcamlLoweredEffect.Call, OcamlLoweredEffect.Throw]),
				occurrence(originId, 1, OcamlPlaceOccurrenceRole.Load, placeId, "old_value", [OcamlLoweredEffect.Read, OcamlLoweredEffect.Throw]),
				occurrence(originId, 2, OcamlPlaceOccurrenceRole.Operator, newValueId, "new_value", [OcamlLoweredEffect.Call, OcamlLoweredEffect.Throw]),
				occurrence(originId, 3, OcamlPlaceOccurrenceRole.Store, placeId, null, [OcamlLoweredEffect.Write, OcamlLoweredEffect.Throw]),
				occurrence(originId, 4, OcamlPlaceOccurrenceRole.Result, postFix ? oldValueId : newValueId, postFix ? "old_value" : "new_value", [])
			],
			effects: [
				OcamlLoweredEffect.Read,
				OcamlLoweredEffect.Call,
				OcamlLoweredEffect.Throw,
				OcamlLoweredEffect.Write
			],
			runtimeRequirementIds: [originId + ":runtime:haxe-int32-add"]
		};
	}

	static function occurrence(originId:String, index:Int, role:OcamlPlaceOccurrenceRole, sourceId:String, sharedAs:Null<String>,
			effects:Array<OcamlLoweredEffect>):OcamlPlaceOccurrence {
		return {
			id: originId + ":occurrence:" + index,
			role: role,
			sourceId: sourceId,
			occurrenceCount: 1,
			sharedAs: sharedAs,
			effects: effects
		};
	}
}
#end
