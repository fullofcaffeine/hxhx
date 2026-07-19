package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Expr.MetadataEntry;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypeTools;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlAssignmentResultKind;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredConversionKind;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredEffect;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredInstanceFieldPlace;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredPlaceKind;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredSimpleAssignment;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlPlaceOccurrence;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlPlaceOccurrenceRole;

/** Builds the typed semantic plan for the first admitted assignment family. */
class OcamlPlaceAssignmentPlanner {
	final context:CompilationContext;

	public function new(context:CompilationContext) {
		this.context = context;
	}

	/** Returns `null` when the expression is outside the deliberately narrow slice. */
	public function planSimpleAssignment(metadata:MetadataEntry, expression:TypedExpr, left:TypedExpr, right:TypedExpr):Null<OcamlLoweredSimpleAssignment> {
		if (!OcamlPlaceInputPolicy.admitsSimpleInstanceField(left, right))
			return null;
		final originId = OcamlLoweredOrigin.readPlaceId(metadata);
		if (originId == null)
			return null;

		return switch (left.expr) {
			case TField(receiver, FInstance(classRef, _, fieldRef)):
				final classType = classRef.get();
				final field = fieldRef.get();
				final moduleName = context.ocamlModuleNameForModuleId(classType.module);
				final currentModuleName = context.currentModuleId == null ? null : context.ocamlModuleNameForModuleId(context.currentModuleId);
				final scopedType = context.scopedInstanceTypeName(classType.module, classType.name);
				final receiverCarrier = currentModuleName == moduleName ? scopedType : moduleName + "." + scopedType;
				final placeId = originId + ":place";
				final place:OcamlLoweredInstanceFieldPlace = {
					id: placeId,
					kind: OcamlLoweredPlaceKind.InstanceField,
					ownerModuleId: classType.module,
					ownerTypeName: classType.name,
					targetSymbolId: classType.module + "::" + classType.name + "::field::" + field.name,
					receiverSemanticTypeId: TypeTools.toString(receiver.t),
					receiverCarrierTypeId: receiverCarrier,
					receiverRepresentationId: originId + ":representation:receiver",
					receiverRepresentationReason: "record-backed class receiver selected by the current OCaml representation policy",
					fieldName: field.name,
					targetFieldName: context.ocamlRecordLabel(field.name),
					semanticTypeId: TypeTools.toString(left.t),
					carrierTypeId: "int",
					representationId: originId + ":representation:field",
					representationReason: "exact Haxe Int field uses the direct OCaml int carrier"
				};
				final schedule:Array<OcamlPlaceOccurrence> = [
					occurrence(originId, 0, OcamlPlaceOccurrenceRole.Receiver, originId + ":receiver", "receiver",
						[OcamlLoweredEffect.Read, OcamlLoweredEffect.Call, OcamlLoweredEffect.Throw]),
					occurrence(originId, 1, OcamlPlaceOccurrenceRole.RightHandSide, originId + ":rhs", "rhs",
						[OcamlLoweredEffect.Read, OcamlLoweredEffect.Call, OcamlLoweredEffect.Throw]),
					occurrence(originId, 2, OcamlPlaceOccurrenceRole.Store, placeId, null, [OcamlLoweredEffect.Write, OcamlLoweredEffect.Throw]),
					occurrence(originId, 3, OcamlPlaceOccurrenceRole.Result, originId + ":rhs", "rhs", [])
				];
				{
					id: originId + ":simple-assignment",
					originId: originId,
					source: OcamlLoweredOrigin.sourceSpan(expression.pos),
					semanticTypeId: TypeTools.toString(expression.t),
					carrierTypeId: "int",
					place: place,
					receiver: receiver,
					rightHandSide: right,
					conversion: OcamlLoweredConversionKind.Identity,
					result: OcamlAssignmentResultKind.AssignedValue,
					schedule: schedule,
					effects: [
						OcamlLoweredEffect.Read,
						OcamlLoweredEffect.Call,
						OcamlLoweredEffect.Throw,
						OcamlLoweredEffect.Write
					],
					runtimeRequirementIds: []
				};
			case _:
				null;
		}
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
