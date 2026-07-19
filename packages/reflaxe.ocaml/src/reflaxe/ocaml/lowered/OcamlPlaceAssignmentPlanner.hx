package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Expr.MetadataEntry;
import haxe.macro.Expr.Binop;
import haxe.macro.Expr.Unop;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypeTools;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlAssignmentResultKind;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredArrayCompoundAssignment;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredArrayElementPlace;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredArrayIntUpdate;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredArraySimpleAssignment;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredCompoundAssignment;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredConversionKind;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredEffect;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredInstanceFieldPlace;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredIntOperator;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredIntUpdate;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredPlaceKind;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredSimpleAssignment;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredStaticFieldAccess;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredStaticFieldPlace;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredStaticCompoundAssignment;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredStaticIntUpdate;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredStaticSimpleAssignment;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredUpdateFixity;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredUpdateOperator;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlPlaceOccurrence;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlPlaceOccurrenceRole;

/** Builds typed semantic plans for the place-operation families admitted so far. */
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

	function planStaticField(originId:String, left:TypedExpr):Null<OcamlLoweredStaticFieldPlace> {
		return switch (left.expr) {
			case TField(_, FStatic(classRef, fieldRef)):
				final classType = classRef.get();
				final field = fieldRef.get();
				final targetModuleName = context.ocamlModuleNameForModuleId(classType.module);
				final staticAccess = context.currentModuleId == classType.module ? OcamlLoweredStaticFieldAccess.Local : OcamlLoweredStaticFieldAccess.Qualified;
				final forwardDeclarationRequired = context.currentModuleId != null
					&& context.currentModuleId == classType.module
					&& context.currentTypeName != null
					&& context.currentTypeName != classType.name;
				{
					id: originId + ":place",
					kind: OcamlLoweredPlaceKind.StaticField,
					ownerModuleId: classType.module,
					ownerTypeName: classType.name,
					targetSymbolId: context.staticFieldKey(classType.module, classType.name, field.name),
					fieldName: field.name,
					targetModuleName: targetModuleName,
					targetValueName: context.scopedValueName(classType.module, classType.name, field.name),
					staticAccess: staticAccess,
					forwardDeclarationRequired: forwardDeclarationRequired,
					semanticTypeId: TypeTools.toString(left.t),
					carrierTypeId: "int",
					representationId: originId + ":representation:static-field",
					representationReason: "mutable exact Haxe Int static uses an OCaml int ref cell"
				};
			case _: null;
		}
	}

	function planArrayElement(originId:String, left:TypedExpr):Null<{place:OcamlLoweredArrayElementPlace, receiver:TypedExpr, index:TypedExpr}> {
		return switch (left.expr) {
			case TArray(receiver, index):
				{
					place: {
						id: originId + ":place",
						kind: OcamlLoweredPlaceKind.ArrayElement,
						ownerModuleId: "Array",
						ownerTypeName: "Array",
						targetSymbolId: "runtime::HxArray::element",
						receiverSemanticTypeId: "Array<Int>",
						receiverDisplayType: TypeTools.toString(receiver.t),
						receiverCarrierTypeId: "int HxArray.t",
						receiverRepresentationId: originId + ":representation:array-receiver",
						receiverRepresentationReason: "exact Array<Int> element operations consume the direct typed HxArray carrier inside place lowering",
						indexSemanticTypeId: "Int",
						indexDisplayType: TypeTools.toString(index.t),
						indexCarrierTypeId: "int",
						indexRepresentationId: originId + ":representation:array-index",
						indexRepresentationReason: "exact Haxe Int index uses the direct OCaml int carrier",
						fieldName: "[]",
						targetModuleName: "HxArray",
						targetLoadName: "get",
						targetStoreName: "set",
						semanticTypeId: "Int",
						carrierTypeId: "int",
						representationId: originId + ":representation:array-element",
						representationReason: "exact Array<Int> elements use the direct OCaml int carrier inside HxArray"
					},
					receiver: receiver,
					index: index
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

	/** Returns `null` when a static simple assignment is outside the admitted slice. */
	public function planStaticSimpleAssignment(metadata:MetadataEntry, expression:TypedExpr, left:TypedExpr,
			right:TypedExpr):Null<OcamlLoweredStaticSimpleAssignment> {
		if (!OcamlPlaceInputPolicy.admitsSimpleStaticField(left, right, context.currentModuleId, context.currentTypeName))
			return null;
		final originId = OcamlLoweredOrigin.readPlaceId(metadata);
		if (originId == null)
			return null;
		final place = planStaticField(originId, left);
		if (place == null)
			return null;
		return {
			id: originId + ":static-simple-assignment",
			originId: originId,
			source: OcamlLoweredOrigin.sourceSpan(expression.pos),
			semanticTypeId: TypeTools.toString(expression.t),
			carrierTypeId: "int",
			place: place,
			rightHandSide: right,
			conversion: OcamlLoweredConversionKind.Identity,
			result: OcamlAssignmentResultKind.AssignedValue,
			schedule: [
				occurrence(originId, 0, OcamlPlaceOccurrenceRole.RightHandSide, originId + ":rhs", "rhs",
					[OcamlLoweredEffect.Read, OcamlLoweredEffect.Call, OcamlLoweredEffect.Throw]),
				occurrence(originId, 1, OcamlPlaceOccurrenceRole.Store, place.id, null, [OcamlLoweredEffect.Write]),
				occurrence(originId, 2, OcamlPlaceOccurrenceRole.Result, originId + ":rhs", "rhs", [])
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

	/** Plans an already-visible exact-Int static `+=` and its load-before-RHS order. */
	public function planStaticCompoundIntAdd(metadata:MetadataEntry, expression:TypedExpr, left:TypedExpr,
			right:TypedExpr):Null<OcamlLoweredStaticCompoundAssignment> {
		if (!OcamlPlaceInputPolicy.admitsCompoundIntAddStaticField(OpAdd, left, right, context.currentModuleId, context.currentTypeName))
			return null;
		final originId = OcamlLoweredOrigin.readPlaceId(metadata);
		if (originId == null)
			return null;
		final place = planStaticField(originId, left);
		if (place == null)
			return null;
		final newValueId = originId + ":new-value";
		return {
			id: originId + ":static-compound-assignment",
			originId: originId,
			source: OcamlLoweredOrigin.sourceSpan(expression.pos),
			semanticTypeId: "Int",
			carrierTypeId: "int",
			place: place,
			rightHandSide: right,
			operation: OcamlLoweredIntOperator.Add,
			conversion: OcamlLoweredConversionKind.Identity,
			result: OcamlAssignmentResultKind.ComputedValue,
			schedule: [
				occurrence(originId, 0, OcamlPlaceOccurrenceRole.Load, place.id, "old_value", [OcamlLoweredEffect.Read]),
				occurrence(originId, 1, OcamlPlaceOccurrenceRole.RightHandSide, originId + ":rhs", "rhs",
					[OcamlLoweredEffect.Read, OcamlLoweredEffect.Call, OcamlLoweredEffect.Throw]),
				occurrence(originId, 2, OcamlPlaceOccurrenceRole.Operator, newValueId, "new_value", [OcamlLoweredEffect.Call, OcamlLoweredEffect.Throw]),
				occurrence(originId, 3, OcamlPlaceOccurrenceRole.Store, place.id, null, [OcamlLoweredEffect.Write]),
				occurrence(originId, 4, OcamlPlaceOccurrenceRole.Result, newValueId, "new_value", [])
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

	/** Plans an already-visible exact-Int static update and its old/new result. */
	public function planStaticIntUpdate(metadata:MetadataEntry, expression:TypedExpr, operation:Unop, postFix:Bool,
			operand:TypedExpr):Null<OcamlLoweredStaticIntUpdate> {
		if (!OcamlPlaceInputPolicy.admitsIntUpdateStaticField(operation, operand, context.currentModuleId, context.currentTypeName))
			return null;
		final originId = OcamlLoweredOrigin.readPlaceId(metadata);
		if (originId == null)
			return null;
		final place = planStaticField(originId, operand);
		if (place == null)
			return null;
		if (operation != OpIncrement && operation != OpDecrement)
			return null;
		final oldValueId = originId + ":old-value";
		final newValueId = originId + ":new-value";
		final fixity = postFix ? OcamlLoweredUpdateFixity.Postfix : OcamlLoweredUpdateFixity.Prefix;
		final result = postFix ? OcamlAssignmentResultKind.OldValue : OcamlAssignmentResultKind.ComputedValue;
		final isIncrement = operation == OpIncrement;
		final sourceOperator = isIncrement ? OcamlLoweredUpdateOperator.Increment : OcamlLoweredUpdateOperator.Decrement;
		final delta = isIncrement ? 1 : -1;
		return {
			id: originId + ":static-int-" + sourceOperator,
			originId: originId,
			source: OcamlLoweredOrigin.sourceSpan(expression.pos),
			semanticTypeId: "Int",
			carrierTypeId: "int",
			place: place,
			sourceOperator: sourceOperator,
			fixity: fixity,
			operation: OcamlLoweredIntOperator.Add,
			delta: delta,
			conversion: OcamlLoweredConversionKind.Identity,
			result: result,
			schedule: [
				occurrence(originId, 0, OcamlPlaceOccurrenceRole.Load, place.id, "old_value", [OcamlLoweredEffect.Read]),
				occurrence(originId, 1, OcamlPlaceOccurrenceRole.Operator, newValueId, "new_value", [OcamlLoweredEffect.Call, OcamlLoweredEffect.Throw]),
				occurrence(originId, 2, OcamlPlaceOccurrenceRole.Store, place.id, null, [OcamlLoweredEffect.Write]),
				occurrence(originId, 3, OcamlPlaceOccurrenceRole.Result, postFix ? oldValueId : newValueId, postFix ? "old_value" : "new_value", [])
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

	/** Returns `null` when an array simple assignment is outside the admitted slice. */
	public function planArraySimpleAssignment(metadata:MetadataEntry, expression:TypedExpr, left:TypedExpr,
			right:TypedExpr):Null<OcamlLoweredArraySimpleAssignment> {
		if (!OcamlPlaceInputPolicy.admitsSimpleArrayElement(left, right))
			return null;
		final originId = OcamlLoweredOrigin.readPlaceId(metadata);
		if (originId == null)
			return null;
		final target = planArrayElement(originId, left);
		if (target == null)
			return null;
		return {
			id: originId + ":array-simple-assignment",
			originId: originId,
			source: OcamlLoweredOrigin.sourceSpan(expression.pos),
			semanticTypeId: "Int",
			carrierTypeId: "int",
			place: target.place,
			receiver: target.receiver,
			index: target.index,
			rightHandSide: right,
			conversion: OcamlLoweredConversionKind.Identity,
			result: OcamlAssignmentResultKind.AssignedValue,
			schedule: [
				occurrence(originId, 0, OcamlPlaceOccurrenceRole.Receiver, originId + ":receiver", "receiver",
					[OcamlLoweredEffect.Read, OcamlLoweredEffect.Call, OcamlLoweredEffect.Throw]),
				occurrence(originId, 1, OcamlPlaceOccurrenceRole.Index, originId + ":index", "index",
					[OcamlLoweredEffect.Read, OcamlLoweredEffect.Call, OcamlLoweredEffect.Throw]),
				occurrence(originId, 2, OcamlPlaceOccurrenceRole.RightHandSide, originId + ":rhs", "rhs",
					[OcamlLoweredEffect.Read, OcamlLoweredEffect.Call, OcamlLoweredEffect.Throw]),
				occurrence(originId, 3, OcamlPlaceOccurrenceRole.Store, target.place.id, null, [OcamlLoweredEffect.Write, OcamlLoweredEffect.Throw]),
				occurrence(originId, 4, OcamlPlaceOccurrenceRole.Result, originId + ":rhs", "rhs", [])
			],
			effects: [
				OcamlLoweredEffect.Read,
				OcamlLoweredEffect.Call,
				OcamlLoweredEffect.Throw,
				OcamlLoweredEffect.Write
			],
			runtimeRequirementIds: ["haxe-array-element-set"]
		};
	}

	/** Plans exact primitive-Int array `+=` with the Oracle-proven load order. */
	public function planArrayCompoundIntAdd(metadata:MetadataEntry, expression:TypedExpr, left:TypedExpr,
			right:TypedExpr):Null<OcamlLoweredArrayCompoundAssignment> {
		if (!OcamlPlaceInputPolicy.admitsCompoundIntAddArrayElement(OpAdd, left, right))
			return null;
		final originId = OcamlLoweredOrigin.readPlaceId(metadata);
		if (originId == null)
			return null;
		final target = planArrayElement(originId, left);
		if (target == null)
			return null;
		final placeId = target.place.id;
		final newValueId = originId + ":new-value";
		return {
			id: originId + ":array-compound-assignment",
			originId: originId,
			source: OcamlLoweredOrigin.sourceSpan(expression.pos),
			semanticTypeId: "Int",
			carrierTypeId: "int",
			place: target.place,
			receiver: target.receiver,
			index: target.index,
			rightHandSide: right,
			operation: OcamlLoweredIntOperator.Add,
			conversion: OcamlLoweredConversionKind.Identity,
			result: OcamlAssignmentResultKind.ComputedValue,
			schedule: [
				occurrence(originId, 0, OcamlPlaceOccurrenceRole.Receiver, originId + ":receiver", "receiver",
					[OcamlLoweredEffect.Read, OcamlLoweredEffect.Call, OcamlLoweredEffect.Throw]),
				occurrence(originId, 1, OcamlPlaceOccurrenceRole.Index, originId + ":index", "index",
					[OcamlLoweredEffect.Read, OcamlLoweredEffect.Call, OcamlLoweredEffect.Throw]),
				occurrence(originId, 2, OcamlPlaceOccurrenceRole.Load, placeId, "old_value", [OcamlLoweredEffect.Read, OcamlLoweredEffect.Throw]),
				occurrence(originId, 3, OcamlPlaceOccurrenceRole.RightHandSide, originId + ":rhs", "rhs",
					[OcamlLoweredEffect.Read, OcamlLoweredEffect.Call, OcamlLoweredEffect.Throw]),
				occurrence(originId, 4, OcamlPlaceOccurrenceRole.Operator, newValueId, "new_value", [OcamlLoweredEffect.Call, OcamlLoweredEffect.Throw]),
				occurrence(originId, 5, OcamlPlaceOccurrenceRole.Store, placeId, null, [OcamlLoweredEffect.Write, OcamlLoweredEffect.Throw]),
				occurrence(originId, 6, OcamlPlaceOccurrenceRole.Result, newValueId, "new_value", [])
			],
			effects: [
				OcamlLoweredEffect.Read,
				OcamlLoweredEffect.Call,
				OcamlLoweredEffect.Throw,
				OcamlLoweredEffect.Write
			],
			runtimeRequirementIds: [
				"haxe-array-element-get",
				originId + ":runtime:haxe-int32-add",
				"haxe-array-element-set"
			]
		};
	}

	/** Plans exact primitive-Int array update without leaving fixity to emission. */
	public function planArrayIntUpdate(metadata:MetadataEntry, expression:TypedExpr, operation:Unop, postFix:Bool,
			operand:TypedExpr):Null<OcamlLoweredArrayIntUpdate> {
		if (!OcamlPlaceInputPolicy.admitsIntUpdateArrayElement(operation, operand))
			return null;
		final originId = OcamlLoweredOrigin.readPlaceId(metadata);
		if (originId == null)
			return null;
		final target = planArrayElement(originId, operand);
		if (target == null)
			return null;
		if (operation != OpIncrement && operation != OpDecrement)
			return null;
		final placeId = target.place.id;
		final oldValueId = originId + ":old-value";
		final newValueId = originId + ":new-value";
		final fixity = postFix ? OcamlLoweredUpdateFixity.Postfix : OcamlLoweredUpdateFixity.Prefix;
		final result = postFix ? OcamlAssignmentResultKind.OldValue : OcamlAssignmentResultKind.ComputedValue;
		final isIncrement = operation == OpIncrement;
		final sourceOperator = isIncrement ? OcamlLoweredUpdateOperator.Increment : OcamlLoweredUpdateOperator.Decrement;
		final delta = isIncrement ? 1 : -1;
		return {
			id: originId + ":array-int-" + sourceOperator,
			originId: originId,
			source: OcamlLoweredOrigin.sourceSpan(expression.pos),
			semanticTypeId: "Int",
			carrierTypeId: "int",
			place: target.place,
			receiver: target.receiver,
			index: target.index,
			sourceOperator: sourceOperator,
			fixity: fixity,
			operation: OcamlLoweredIntOperator.Add,
			delta: delta,
			conversion: OcamlLoweredConversionKind.Identity,
			result: result,
			schedule: [
				occurrence(originId, 0, OcamlPlaceOccurrenceRole.Receiver, originId + ":receiver", "receiver",
					[OcamlLoweredEffect.Read, OcamlLoweredEffect.Call, OcamlLoweredEffect.Throw]),
				occurrence(originId, 1, OcamlPlaceOccurrenceRole.Index, originId + ":index", "index",
					[OcamlLoweredEffect.Read, OcamlLoweredEffect.Call, OcamlLoweredEffect.Throw]),
				occurrence(originId, 2, OcamlPlaceOccurrenceRole.Load, placeId, "old_value", [OcamlLoweredEffect.Read, OcamlLoweredEffect.Throw]),
				occurrence(originId, 3, OcamlPlaceOccurrenceRole.Operator, newValueId, "new_value", [OcamlLoweredEffect.Call, OcamlLoweredEffect.Throw]),
				occurrence(originId, 4, OcamlPlaceOccurrenceRole.Store, placeId, null, [OcamlLoweredEffect.Write, OcamlLoweredEffect.Throw]),
				occurrence(originId, 5, OcamlPlaceOccurrenceRole.Result, postFix ? oldValueId : newValueId, postFix ? "old_value" : "new_value", [])
			],
			effects: [
				OcamlLoweredEffect.Read,
				OcamlLoweredEffect.Call,
				OcamlLoweredEffect.Throw,
				OcamlLoweredEffect.Write
			],
			runtimeRequirementIds: [
				"haxe-array-element-get",
				originId + ":runtime:haxe-int32-add",
				"haxe-array-element-set"
			]
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
