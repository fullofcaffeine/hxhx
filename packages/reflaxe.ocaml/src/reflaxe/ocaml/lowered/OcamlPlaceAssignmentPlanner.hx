package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Expr.MetadataEntry;
import haxe.macro.Expr.Binop;
import haxe.macro.Expr.Unop;
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypeTools;
import reflaxe.lifecycle.LexicalLocalIdentityPlan;
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
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredPlaceOperation;
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
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalRepresentationChoice;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/** Builds typed semantic plans for the place-operation families admitted so far. */
class OcamlPlaceAssignmentPlanner {
	final context:CompilationContext;
	final currentModuleId:String;
	final currentTypeName:String;
	final representations:OcamlRepresentationRegistry;
	final localRepresentations:OcamlLocalRepresentationPlan;
	final localIdentities:LexicalLocalIdentityPlan;
	final staticStorage:OcamlStaticStoragePlan;
	final binding:OcamlFunctionPlanBinding;

	public function new(context:CompilationContext, currentModuleId:String, currentTypeName:String, representations:OcamlRepresentationRegistry,
			localRepresentations:OcamlLocalRepresentationPlan, localIdentities:LexicalLocalIdentityPlan, staticStorage:OcamlStaticStoragePlan,
			binding:OcamlFunctionPlanBinding) {
		this.context = context;
		this.currentModuleId = currentModuleId;
		this.currentTypeName = currentTypeName;
		this.representations = representations;
		this.localRepresentations = localRepresentations;
		this.localIdentities = localIdentities;
		this.staticStorage = staticStorage;
		this.binding = binding;
	}

	/**
		Authorizes the one Haxe Int32 addition call chosen by a sealed mutation plan.

		The `order` is the operator step in that plan's evaluation schedule. Syntax
		generation may use `HxInt.add` only by consuming this exact record.
	**/
	function intAdditionRuntimeUse(originId:String, ownerId:String, requirementId:String, order:Int, source:OcamlLoweredSourceSpan):OcamlRuntimeUseOccurrence {
		return {
			id: originId + ":runtime-use:int-add",
			planRevision: OcamlRuntimeUseModel.planRevision(binding),
			ownerId: ownerId,
			requirementId: requirementId,
			domain: OcamlRuntimeUseDomain.ExpressionIdentifier,
			exactSymbol: "HxInt.add",
			role: "int-add",
			order: order,
			source: source,
			profileEligibility: ["metal", "portable"],
			cardinality: 1
		};
	}

	/** Selects one complete place plan from a final origin-bearing operation. */
	public function plan(metadata:MetadataEntry, expression:TypedExpr):Null<OcamlLoweredPlaceOperation> {
		return switch (expression.expr) {
			case TBinop(OpAssign, left, right):
				final instancePlan = planSimpleAssignment(metadata, expression, left, right);
				if (instancePlan != null) {
					OcamlLoweredPlaceOperation.Simple(instancePlan);
				} else {
					final staticPlan = planStaticSimpleAssignment(metadata, expression, left, right);
					if (staticPlan != null) {
						OcamlLoweredPlaceOperation.StaticSimple(staticPlan);
					} else {
						final arrayPlan = planArraySimpleAssignment(metadata, expression, left, right);
						arrayPlan == null ? null : OcamlLoweredPlaceOperation.ArraySimple(arrayPlan);
					}
				}
			case TBinop(OpAssignOp(OpAdd), left, right):
				final instancePlan = planCompoundIntAdd(metadata, expression, left, right);
				if (instancePlan != null) {
					OcamlLoweredPlaceOperation.Compound(instancePlan);
				} else {
					final staticPlan = planStaticCompoundIntAdd(metadata, expression, left, right);
					if (staticPlan != null) {
						OcamlLoweredPlaceOperation.StaticCompound(staticPlan);
					} else {
						final arrayPlan = planArrayCompoundIntAdd(metadata, expression, left, right);
						arrayPlan == null ? null : OcamlLoweredPlaceOperation.ArrayCompound(arrayPlan);
					}
				}
			case TUnop(operation = (OpIncrement | OpDecrement), postFix, operand):
				final instancePlan = planIntUpdate(metadata, expression, operation, postFix, operand);
				if (instancePlan != null) {
					OcamlLoweredPlaceOperation.Update(instancePlan);
				} else {
					final staticPlan = planStaticIntUpdate(metadata, expression, operation, postFix, operand);
					if (staticPlan != null) {
						OcamlLoweredPlaceOperation.StaticUpdate(staticPlan);
					} else {
						final arrayPlan = planArrayIntUpdate(metadata, expression, operation, postFix, operand);
						arrayPlan == null ? null : OcamlLoweredPlaceOperation.ArrayUpdate(arrayPlan);
					}
				}
			case _:
				null;
		}
	}

	function selectDirectPrimitive(type:Type, domain:OcamlRepresentationDomain):OcamlRepresentationDecision {
		if (OcamlRepresentationRegistry.isExactInt(type))
			return representations.selectExactInt(domain);
		if (OcamlRepresentationRegistry.isExactBool(type))
			return representations.selectExactBool(domain);
		if (OcamlRepresentationRegistry.isExactString(type))
			return representations.selectExactString(domain);
		throw 'reflaxe.ocaml [ocaml-place:unsupported-direct-primitive]: no admitted direct primitive field representation exists for ${TypeTools.toString(type)} in $domain';
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
				final receiverLayout = representations.monomorphicClassForType(receiver.t);
				final receiverRepresentation = receiverLayout == null ? null : representations.monomorphicClassValue(receiverLayout.semanticTypeId);
				final receiverAdmitted = if (receiverLayout == null
					|| receiverRepresentation == null
					|| receiverLayout.sourceModuleId != currentModuleId) {
					false;
				} else {
					switch (receiver.expr) {
						case TConst(TThis): currentModuleId == receiverLayout.sourceModuleId && currentTypeName == receiverLayout.sourceTypeName;
						case TLocal(local):
							switch (localRepresentations.choiceFor(localIdentities.requireHostId(local.id).id)) {
								case ProgramDecision(representationId, representationRevision, semanticTypeId, OcamlRepresentationDomain.InternalValue):
									representationId == receiverRepresentation.id
									&& representationRevision == receiverRepresentation.revision
									&& semanticTypeId == receiverLayout.semanticTypeId;
								case _:
									false;
							}
						case _:
							false;
					}
				}
				final moduleName = context.ocamlModuleNameForModuleId(receiverClass.module);
				final currentModuleName = context.ocamlModuleNameForModuleId(currentModuleId);
				final scopedType = context.scopedInstanceTypeName(receiverClass.module, receiverClass.name);
				final receiverCarrier = currentModuleName == moduleName ? scopedType : moduleName + "." + scopedType;
				final valueRepresentation = selectDirectPrimitive(left.t, OcamlRepresentationDomain.InstanceField);
				{
					place: {
						id: originId + ":place",
						kind: OcamlLoweredPlaceKind.InstanceField,
						ownerModuleId: classType.module,
						ownerTypeName: classType.name,
						targetSymbolId: classType.module + "::" + classType.name + "::field::" + field.name,
						receiverSemanticTypeId: TypeTools.toString(receiver.t),
						receiverCarrierTypeId: receiverCarrier,
						receiverRepresentationId: receiverAdmitted ? receiverRepresentation.id : originId + ":representation:receiver",
						receiverRepresentationReason: receiverAdmitted ? receiverRepresentation.reason : "legacy record-backed carrier selected from the semantic receiver type; no sealed class representation owns this receiver yet",
						fieldName: field.name,
						targetFieldName: context.ocamlRecordLabel(field.name),
						semanticTypeId: TypeTools.toString(left.t),
						carrierTypeId: valueRepresentation.carrierTypeId,
						representationId: valueRepresentation.id,
						representationReason: valueRepresentation.reason
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
				final staticAccess = currentModuleId == classType.module ? OcamlLoweredStaticFieldAccess.Local : OcamlLoweredStaticFieldAccess.Qualified;
				final storage = staticStorage.require(classType.module, classType.name, field.name);
				final valueRepresentation = selectDirectPrimitive(left.t, OcamlRepresentationDomain.StaticField);
				if (storage.representationId != null && storage.representationId != valueRepresentation.id)
					throw 'reflaxe.ocaml [ocaml-static-storage:representation-mismatch]: "${storage.key}" uses ${storage.representationId}, but place lowering selected ${valueRepresentation.id}';
				{
					id: originId + ":place",
					kind: OcamlLoweredPlaceKind.StaticField,
					ownerModuleId: classType.module,
					ownerTypeName: classType.name,
					targetSymbolId: storage.key,
					fieldName: field.name,
					targetModuleName: targetModuleName,
					targetValueName: storage.targetValueName,
					staticAccess: staticAccess,
					forwardDeclarationRequired: false,
					semanticTypeId: TypeTools.toString(left.t),
					carrierTypeId: valueRepresentation.carrierTypeId,
					representationId: valueRepresentation.id,
					representationReason: valueRepresentation.reason
				};
			case _: null;
		}
	}

	function planArrayElement(originId:String, left:TypedExpr):Null<{place:OcamlLoweredArrayElementPlace, receiver:TypedExpr, index:TypedExpr}> {
		return switch (left.expr) {
			case TArray(receiver, index):
				final receiverRepresentation = representations.selectRepresentedArray(receiver.t, OcamlRepresentationDomain.InternalValue);
				final descriptor = representations.requireRepresentedArray(receiverRepresentation.arrayDescriptorId,
					receiverRepresentation.arrayDescriptorRevision, receiverRepresentation.programRevision);
				final indexRepresentation = representations.selectExactInt(OcamlRepresentationDomain.InternalValue);
				final valueRepresentation = representations.require(descriptor.elementRepresentationId, receiverRepresentation.programRevision);
				if (valueRepresentation.revision != descriptor.elementRepresentationRevision)
					throw 'reflaxe.ocaml [ocaml-place:stale-array-element-representation]: ${descriptor.id} no longer matches ${valueRepresentation.id}@${valueRepresentation.revision}';
				{
					place: {
						id: originId + ":place",
						kind: OcamlLoweredPlaceKind.ArrayElement,
						ownerModuleId: "Array",
						ownerTypeName: "Array",
						targetSymbolId: "runtime::HxArray::element",
						receiverSemanticTypeId: "Array<Int>",
						receiverDisplayType: TypeTools.toString(receiver.t),
						receiverCarrierTypeId: receiverRepresentation.carrierTypeId,
						receiverRepresentationId: receiverRepresentation.id,
						receiverRepresentationReason: receiverRepresentation.reason,
						indexSemanticTypeId: "Int",
						indexDisplayType: TypeTools.toString(index.t),
						indexCarrierTypeId: indexRepresentation.carrierTypeId,
						indexRepresentationId: indexRepresentation.id,
						indexRepresentationReason: indexRepresentation.reason,
						fieldName: "[]",
						targetModuleName: "HxArray",
						targetLoadName: "get",
						targetStoreName: "set",
						semanticTypeId: "Int",
						carrierTypeId: valueRepresentation.carrierTypeId,
						representationId: valueRepresentation.id,
						representationReason: valueRepresentation.reason
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
			carrierTypeId: target.place.carrierTypeId,
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
		if (!OcamlPlaceInputPolicy.admitsSimpleStaticField(left, right, currentModuleId, currentTypeName, staticStorage))
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
			carrierTypeId: place.carrierTypeId,
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
		if (!OcamlPlaceInputPolicy.admitsCompoundIntAddStaticField(OpAdd, left, right, currentModuleId, currentTypeName, staticStorage))
			return null;
		final originId = OcamlLoweredOrigin.readPlaceId(metadata);
		if (originId == null)
			return null;
		final place = planStaticField(originId, left);
		if (place == null)
			return null;
		final newValueId = originId + ":new-value";
		final planId = originId + ":static-compound-assignment";
		final requirementId = originId + ":runtime:haxe-int32-add";
		final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
		return {
			id: planId,
			originId: originId,
			source: source,
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
			runtimeRequirementIds: [requirementId],
			runtimeUseOccurrences: [intAdditionRuntimeUse(originId, planId, requirementId, 2, source)]
		};
	}

	/** Plans an already-visible exact-Int static update and its old/new result. */
	public function planStaticIntUpdate(metadata:MetadataEntry, expression:TypedExpr, operation:Unop, postFix:Bool,
			operand:TypedExpr):Null<OcamlLoweredStaticIntUpdate> {
		if (!OcamlPlaceInputPolicy.admitsIntUpdateStaticField(operation, operand, currentModuleId, currentTypeName, staticStorage))
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
		final planId = originId + ":static-int-" + sourceOperator;
		final requirementId = originId + ":runtime:haxe-int32-add";
		final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
		return {
			id: planId,
			originId: originId,
			source: source,
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
			runtimeRequirementIds: [requirementId],
			runtimeUseOccurrences: [intAdditionRuntimeUse(originId, planId, requirementId, 1, source)]
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
		final planId = originId + ":array-simple-assignment";
		final requirementId = originId + ":runtime:haxe-array-element-set";
		final planRevision = OcamlRuntimeUseModel.planRevision(binding);
		return {
			id: planId,
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
			runtimeRequirementIds: [requirementId],
			runtimeUseOccurrences: [
				{
					id: originId + ":runtime-use:array-set",
					planRevision: planRevision,
					ownerId: planId,
					requirementId: requirementId,
					domain: OcamlRuntimeUseDomain.ExpressionIdentifier,
					exactSymbol: target.place.targetModuleName + "." + target.place.targetStoreName,
					role: "store",
					order: 3,
					source: OcamlLoweredOrigin.sourceSpan(expression.pos),
					profileEligibility: ["metal", "portable"],
					cardinality: 1
				}
			]
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
		final planId = originId + ":array-compound-assignment";
		final requirementId = originId + ":runtime:haxe-int32-add";
		final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
		return {
			id: planId,
			originId: originId,
			source: source,
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
				originId + ":runtime:haxe-array-element-get",
				requirementId,
				originId + ":runtime:haxe-array-element-set"
			],
			runtimeUseOccurrences: [intAdditionRuntimeUse(originId, planId, requirementId, 4, source)]
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
		final planId = originId + ":array-int-" + sourceOperator;
		final requirementId = originId + ":runtime:haxe-int32-add";
		final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
		return {
			id: planId,
			originId: originId,
			source: source,
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
				originId + ":runtime:haxe-array-element-get",
				requirementId,
				originId + ":runtime:haxe-array-element-set"
			],
			runtimeUseOccurrences: [intAdditionRuntimeUse(originId, planId, requirementId, 3, source)]
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
		final planId = originId + ":compound-assignment";
		final requirementId = originId + ":runtime:haxe-int32-add";
		final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
		return {
			id: planId,
			originId: originId,
			source: source,
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
			runtimeRequirementIds: [requirementId],
			runtimeUseOccurrences: [intAdditionRuntimeUse(originId, planId, requirementId, 3, source)]
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
		final planId = originId + ":int-" + sourceOperator;
		final requirementId = originId + ":runtime:haxe-int32-add";
		final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
		return {
			id: planId,
			originId: originId,
			source: source,
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
			runtimeRequirementIds: [requirementId],
			runtimeUseOccurrences: [intAdditionRuntimeUse(originId, planId, requirementId, 2, source)]
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
