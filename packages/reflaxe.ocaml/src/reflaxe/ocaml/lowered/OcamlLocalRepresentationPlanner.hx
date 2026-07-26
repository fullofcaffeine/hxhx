package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalConversionDecision;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalConversionRole;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalCarrierConversion;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalRepresentationChoice;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlUnsafeOperationKind;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlUnsafeOperationRecord;
import reflaxe.ocaml.lowered.OcamlLocalStoragePlan.OcamlLocalStorageDecision;
import reflaxe.ocaml.lowered.OcamlLocalStoragePlan.OcamlLocalStorageKind;
import reflaxe.ocaml.lowered.OcamlLocalStoragePlan.OcamlLocalStorageReason;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;

private typedef PendingNullablePrimitiveConversion = {
	final localId:Int;
	final sourceLocalId:Null<Int>;
	final role:OcamlLocalConversionRole;
	final expression:TypedExpr;
	final inputSemanticTypeId:String;
	final inputCarrierTypeId:String;
	final outputSemanticTypeId:String;
	final outputCarrierTypeId:String;
	final conversion:OcamlLocalCarrierConversion;
}

private typedef ExactBoolCarrierInput = {
	final sourceLocalId:Null<Int>;
}

/**
	Connects local carrier choices to the program representation registry.

	Mutated locals retain the existing exact-Int migration. Exact `Bool` locals
	use one direct carrier decision before they can feed nullable-Bool boxing.
	Exact `Array<Int>`
	locals are admitted only when the declaration and every whole-value
	replacement use the same non-null carrier, including locals shared with nested
	functions. Exact core `Null<Int>` and `Null<Bool>` locals additionally receive
	one immutable conversion per admitted initializer, assignment, or read
	occurrence. Boolean truthiness is admitted only when the typed parent is a
	condition or logical operator. Logical results use the OCaml target's typed
	`Bool` interpretation; the portable oracle fixture separately records that
	Haxe 4.3.7 JavaScript and Neko preserve null for `nullValue && rhs`.
	Unsupported or ambiguous occurrences keep the entire local on the legacy
	path.
**/
class OcamlLocalRepresentationPlanner {
	/**
		Returns whether an expression already produces the exact direct Array<Int>
		carrier selected by the registry.

		Metadata and parentheses do not change a carrier. A cast is eligible only
		when its child already has the same exact type; a cast from Dynamic, a
		typedef, a nullable wrapper, or another representation is a separate
		conversion boundary and stays on the legacy path.
	**/
	static function isExactArrayIntCarrierExpression(expression:TypedExpr):Bool {
		if (!OcamlRepresentationRegistry.isExactArrayInt(expression.t))
			return false;
		return switch (expression.expr) {
			case TConst(TNull):
				false;
			case TMeta(_, child), TParenthesis(child):
				isExactArrayIntCarrierExpression(child);
			case TCast(child, _): OcamlRepresentationRegistry.isExactArrayInt(child.t) && isExactArrayIntCarrierExpression(child);
			case _:
				true;
		}
	}

	/**
		Returns whether one expression is already inside the admitted direct-Bool
		local carrier.

		This deliberately recognizes only literals and previously declared exact
		Bool locals. Calls, operators, field reads, casts, parameters, and nullable
		reads need their own typed conversion owner.
	**/
	static function exactBoolCarrierInput(expression:TypedExpr, declaredLocalIds:Map<Int, Bool>):Null<ExactBoolCarrierInput> {
		return switch (unwrapTransparent(expression).expr) {
			case TConst(TBool(_)):
				{sourceLocalId: null};
			case TLocal(local) if (declaredLocalIds.exists(local.id) && OcamlRepresentationRegistry.isExactBool(local.t)):
				{sourceLocalId: local.id};
			case _:
				null;
		}
	}

	/** Plans registry references and initializer conversions from one final typed body. */
	public static function planExpression(expression:TypedExpr, storage:OcamlLocalStoragePlan, representations:OcamlRepresentationRegistry,
			?binding:OcamlFunctionPlanBinding):OcamlLocalRepresentationPlan {
		final typeByLocalId:Map<Int, Type> = [];
		final declaredLocalIds:Map<Int, Bool> = [];
		final identityBoolInitializerByLocalId:Map<Int, Bool> = [];
		final identityBoolAssignmentsByLocalId:Map<Int, Bool> = [];
		final boolSourceLocalIdsByLocalId:Map<Int, Array<Int>> = [];
		final identityArrayInitializerByLocalId:Map<Int, Bool> = [];
		final identityArrayAssignmentsByLocalId:Map<Int, Bool> = [];
		final unsupportedNullableLocalIds:Map<Int, Bool> = [];
		final pendingNullableConversions:Array<PendingNullablePrimitiveConversion> = [];

		function record(localId:Int, type:Type):Void {
			final existing = typeByLocalId.get(localId);
			if (existing != null && TypeTools.toString(existing) != TypeTools.toString(type)) {
				throw 'reflaxe.ocaml [ocaml-representation:conflicting-local-type]: local $localId appears as both ${TypeTools.toString(existing)} and ${TypeTools.toString(type)}';
			}
			typeByLocalId.set(localId, type);
		}

		function addNullIntWrite(localId:Int, role:OcamlLocalConversionRole, value:TypedExpr):Void {
			final input = nullIntWriteInput(value);
			if (input == null) {
				unsupportedNullableLocalIds.set(localId, true);
				return;
			}
			pendingNullableConversions.push({
				localId: localId,
				sourceLocalId: input.sourceLocalId,
				role: role,
				expression: value,
				inputSemanticTypeId: input.semanticTypeId,
				inputCarrierTypeId: input.carrierTypeId,
				outputSemanticTypeId: "Null<Int>",
				outputCarrierTypeId: "Obj.t",
				conversion: input.conversion
			});
		}

		function addNullIntRead(localId:Int, current:TypedExpr, checked:Bool):Void {
			if (checked) {
				pendingNullableConversions.push({
					localId: localId,
					sourceLocalId: localId,
					role: OcamlLocalConversionRole.Read,
					expression: current,
					inputSemanticTypeId: "Null<Int>",
					inputCarrierTypeId: "Obj.t",
					outputSemanticTypeId: "Int",
					outputCarrierTypeId: "int",
					conversion: OcamlLocalCarrierConversion.CheckedUnboxNullableInt
				});
			} else if (OcamlRepresentationRegistry.isExactNullInt(current.t)) {
				pendingNullableConversions.push({
					localId: localId,
					sourceLocalId: localId,
					role: OcamlLocalConversionRole.Read,
					expression: current,
					inputSemanticTypeId: "Null<Int>",
					inputCarrierTypeId: "Obj.t",
					outputSemanticTypeId: "Null<Int>",
					outputCarrierTypeId: "Obj.t",
					conversion: OcamlLocalCarrierConversion.PreserveNullableIntCarrier
				});
			} else if (OcamlRepresentationRegistry.isExactInt(current.t)) {
				pendingNullableConversions.push({
					localId: localId,
					sourceLocalId: localId,
					role: OcamlLocalConversionRole.Read,
					expression: current,
					inputSemanticTypeId: "Null<Int>",
					inputCarrierTypeId: "Obj.t",
					outputSemanticTypeId: "Int",
					outputCarrierTypeId: "int",
					conversion: OcamlLocalCarrierConversion.CheckedUnboxNullableInt
				});
			} else {
				unsupportedNullableLocalIds.set(localId, true);
			}
		}

		function addNullBoolWrite(localId:Int, role:OcamlLocalConversionRole, value:TypedExpr):Void {
			final input = nullBoolWriteInput(value, declaredLocalIds);
			if (input == null) {
				unsupportedNullableLocalIds.set(localId, true);
				return;
			}
			pendingNullableConversions.push({
				localId: localId,
				sourceLocalId: input.sourceLocalId,
				role: role,
				expression: value,
				inputSemanticTypeId: input.semanticTypeId,
				inputCarrierTypeId: input.carrierTypeId,
				outputSemanticTypeId: "Null<Bool>",
				outputCarrierTypeId: "Obj.t",
				conversion: input.conversion
			});
		}

		function addNullBoolRead(localId:Int, current:TypedExpr, truthiness:Bool):Void {
			if (truthiness) {
				pendingNullableConversions.push({
					localId: localId,
					sourceLocalId: localId,
					role: OcamlLocalConversionRole.Read,
					expression: current,
					inputSemanticTypeId: "Null<Bool>",
					inputCarrierTypeId: "Obj.t",
					outputSemanticTypeId: "Bool",
					outputCarrierTypeId: "bool",
					conversion: OcamlLocalCarrierConversion.NullableBoolTruthiness
				});
			} else if (OcamlRepresentationRegistry.isExactNullBool(current.t)) {
				pendingNullableConversions.push({
					localId: localId,
					sourceLocalId: localId,
					role: OcamlLocalConversionRole.Read,
					expression: current,
					inputSemanticTypeId: "Null<Bool>",
					inputCarrierTypeId: "Obj.t",
					outputSemanticTypeId: "Null<Bool>",
					outputCarrierTypeId: "Obj.t",
					conversion: OcamlLocalCarrierConversion.PreserveNullableBoolCarrier
				});
			} else {
				// Concrete-Bool calls, assignments, and returns are separate from
				// condition truthiness and remain unadmitted in this slice.
				unsupportedNullableLocalIds.set(localId, true);
			}
		}

		function rejectDirectNullBoolBoundary(current:TypedExpr):Void {
			final unwrapped = unwrapTransparent(current);
			switch (unwrapped.expr) {
				case TLocal(local) if (OcamlRepresentationRegistry.isExactNullBool(local.t)):
					record(local.id, local.t);
					unsupportedNullableLocalIds.set(local.id, true);
				case _:
			}
		}

		var visit:TypedExpr->Void = null;

		function visitCheckedInt(current:TypedExpr):Void {
			final unwrapped = unwrapTransparent(current);
			switch (unwrapped.expr) {
				case TLocal(local) if (OcamlRepresentationRegistry.isExactNullInt(local.t)):
					record(local.id, local.t);
					addNullIntRead(local.id, current, true);
				case _:
					visit(current);
			}
		}

		function visitBoolTruthiness(current:TypedExpr):Void {
			final unwrapped = unwrapTransparent(current);
			switch (unwrapped.expr) {
				case TLocal(local) if (OcamlRepresentationRegistry.isExactNullBool(local.t)):
					record(local.id, local.t);
					addNullBoolRead(local.id, current, true);
				case _:
					visit(current);
			}
		}

		visit = function(current:TypedExpr):Void {
			var visitChildren = true;
			switch (current.expr) {
				case TVar(local, initializer):
					record(local.id, local.t);
					declaredLocalIds.set(local.id, true);
					if (OcamlRepresentationRegistry.isExactArrayInt(local.t)) {
						final identityInitializer = initializer != null && isExactArrayIntCarrierExpression(initializer);
						identityArrayInitializerByLocalId.set(local.id, identityInitializer);
					}
					if (OcamlRepresentationRegistry.isExactBool(local.t)) {
						final input = initializer == null ? null : exactBoolCarrierInput(initializer, declaredLocalIds);
						identityBoolInitializerByLocalId.set(local.id, input != null);
						if (input != null && input.sourceLocalId != null)
							boolSourceLocalIdsByLocalId.set(local.id, [input.sourceLocalId]);
					}
					if (OcamlRepresentationRegistry.isExactNullInt(local.t) && initializer != null)
						addNullIntWrite(local.id, OcamlLocalConversionRole.Initializer, initializer);
					if (OcamlRepresentationRegistry.isExactNullBool(local.t) && initializer != null)
						addNullBoolWrite(local.id, OcamlLocalConversionRole.Initializer, initializer);
					if (!OcamlRepresentationRegistry.isExactNullBool(local.t) && initializer != null)
						rejectDirectNullBoolBoundary(initializer);
				case TLocal(local):
					record(local.id, local.t);
					if (OcamlRepresentationRegistry.isExactNullInt(local.t))
						addNullIntRead(local.id, current, false);
					if (OcamlRepresentationRegistry.isExactNullBool(local.t))
						addNullBoolRead(local.id, current, false);
				case TBinop(OpAssign, left, right):
					switch (left.expr) {
						case TLocal(local) if (OcamlRepresentationRegistry.isExactArrayInt(local.t)):
							final identityAssignment = isExactArrayIntCarrierExpression(right);
							if (!identityAssignment
								|| !identityArrayAssignmentsByLocalId.exists(local.id)) identityArrayAssignmentsByLocalId.set(local.id, identityAssignment);
						case TLocal(local) if (OcamlRepresentationRegistry.isExactNullInt(local.t)):
							record(local.id, local.t);
							addNullIntWrite(local.id, OcamlLocalConversionRole.Assignment, right);
							visit(right);
							visitChildren = false;
						case TLocal(local) if (OcamlRepresentationRegistry.isExactNullBool(local.t)):
							record(local.id, local.t);
							addNullBoolWrite(local.id, OcamlLocalConversionRole.Assignment, right);
							visit(right);
							visitChildren = false;
						case TLocal(local) if (OcamlRepresentationRegistry.isExactBool(local.t)):
							final input = exactBoolCarrierInput(right, declaredLocalIds);
							final identityAssignment = input != null;
							if (!identityAssignment || !identityBoolAssignmentsByLocalId.exists(local.id))
								identityBoolAssignmentsByLocalId.set(local.id, identityAssignment);
							if (input != null && input.sourceLocalId != null) {
								final sources = boolSourceLocalIdsByLocalId.get(local.id);
								if (sources == null)
									boolSourceLocalIdsByLocalId.set(local.id, [input.sourceLocalId]);
								else if (sources.indexOf(input.sourceLocalId) < 0)
									sources.push(input.sourceLocalId);
							}
						case _:
							rejectDirectNullBoolBoundary(right);
					}
				case TBinop(op = (OpAdd | OpSub | OpMult | OpDiv | OpMod | OpAnd | OpOr | OpXor | OpShl | OpShr | OpUShr), left, right):
					final isStringConcat = op == OpAdd
						&& (TypeTools.toString(left.t) == "String"
							|| TypeTools.toString(right.t) == "String"
							|| TypeTools.toString(current.t) == "String");
					if (!isStringConcat) {
						visitCheckedInt(left);
						visitCheckedInt(right);
						visitChildren = false;
					}
				case TBinop(OpBoolAnd | OpBoolOr, left, right):
					visitBoolTruthiness(left);
					visitBoolTruthiness(right);
					visitChildren = false;
				case TIf(condition, thenExpression, elseExpression):
					visitBoolTruthiness(condition);
					visit(thenExpression);
					if (elseExpression != null)
						visit(elseExpression);
					visitChildren = false;
				case TWhile(condition, body, _):
					visitBoolTruthiness(condition);
					visit(body);
					visitChildren = false;
				case TUnop(OpNot, _, operand):
					visitBoolTruthiness(operand);
					visitChildren = false;
				case TCall(callee, arguments):
					visit(callee);
					for (argument in arguments) {
						rejectDirectNullBoolBoundary(argument);
						visit(argument);
					}
					visitChildren = false;
				case TReturn(value):
					if (value != null) {
						rejectDirectNullBoolBoundary(value);
						visit(value);
					}
					visitChildren = false;
				case TBinop(OpAssignOp(_), left, _), TUnop(OpIncrement | OpDecrement, _, left):
					switch (left.expr) {
						case TLocal(local) if (OcamlRepresentationRegistry.isExactNullInt(local.t)):
							unsupportedNullableLocalIds.set(local.id, true);
						case TLocal(local) if (OcamlRepresentationRegistry.isExactNullBool(local.t)):
							unsupportedNullableLocalIds.set(local.id, true);
						case _:
					}
				case _:
			}
			if (visitChildren)
				TypedExprTools.iter(current, visit);
		};

		visit(expression);
		final unsupportedBoolLocalIds:Map<Int, Bool> = [];
		for (localId in declaredLocalIds.keys()) {
			final type = typeByLocalId.get(localId);
			if (type != null
				&& OcamlRepresentationRegistry.isExactBool(type)
				&& (identityBoolInitializerByLocalId.get(localId) != true || identityBoolAssignmentsByLocalId.get(localId) == false))
				unsupportedBoolLocalIds.set(localId, true);
		}
		var propagatedUnsupportedBool = true;
		while (propagatedUnsupportedBool) {
			propagatedUnsupportedBool = false;
			for (localId in boolSourceLocalIdsByLocalId.keys()) {
				if (unsupportedBoolLocalIds.exists(localId))
					continue;
				final sourceLocalIds:Array<Int> = cast boolSourceLocalIdsByLocalId.get(localId);
				var hasUnsupportedSource = false;
				for (sourceLocalId in sourceLocalIds) {
					if (unsupportedBoolLocalIds.exists(sourceLocalId)) {
						hasUnsupportedSource = true;
						break;
					}
				}
				if (hasUnsupportedSource) {
					unsupportedBoolLocalIds.set(localId, true);
					propagatedUnsupportedBool = true;
				}
			}
		}
		var propagatedUnsupported = true;
		while (propagatedUnsupported) {
			propagatedUnsupported = false;
			for (pending in pendingNullableConversions) {
				final sourceLocalId = pending.sourceLocalId;
				if (sourceLocalId != null
					&& sourceLocalId != pending.localId
					&& (unsupportedNullableLocalIds.exists(sourceLocalId)
						|| (pending.inputSemanticTypeId == "Bool" && unsupportedBoolLocalIds.exists(sourceLocalId)))
					&& !unsupportedNullableLocalIds.exists(pending.localId)) {
					unsupportedNullableLocalIds.set(pending.localId, true);
					propagatedUnsupported = true;
				}
			}
		}
		if (binding != null) {
			final occurrenceOwnerById:Map<String, Int> = [];
			for (pending in pendingNullableConversions) {
				final source = OcamlLoweredOrigin.sourceSpan(pending.expression.pos);
				final occurrenceId = OcamlLocalRepresentationPlan.occurrenceId(binding, pending.localId, pending.role, source);
				final existingLocalId = occurrenceOwnerById.get(occurrenceId);
				if (existingLocalId != null) {
					unsupportedNullableLocalIds.set(existingLocalId, true);
					unsupportedNullableLocalIds.set(pending.localId, true);
				} else {
					occurrenceOwnerById.set(occurrenceId, pending.localId);
				}
			}
		}
		final decisions:Array<OcamlLocalRepresentationDecision> = [];
		final plannedLocalIds:Map<Int, Bool> = [];
		for (decision in storage.decisions()) {
			plannedLocalIds.set(decision.localId, true);
			final type = typeByLocalId.get(decision.localId);
			if (type == null)
				throw 'reflaxe.ocaml [ocaml-representation:missing-local-type]: storage decision for local ${decision.localId} has no typed local occurrence in the sealed function body';
			if (OcamlRepresentationRegistry.isExactArrayInt(type)) {
				if (identityArrayInitializerByLocalId.get(decision.localId) == true
					&& identityArrayAssignmentsByLocalId.get(decision.localId) != false) {
					final domain = localDomain(decision);
					final representation = representations.selectExactArrayInt(domain);
					decisions.push({
						localId: decision.localId,
						choice: OcamlLocalRepresentationChoice.ProgramDecision(representation.id, representation.semanticTypeId, domain),
						initializerConversion: OcamlLocalCarrierConversion.Identity,
						assignmentConversion: OcamlLocalCarrierConversion.Identity,
						readConversion: OcamlLocalCarrierConversion.Identity
					});
				} else {
					decisions.push(unmigratedDecision(decision.localId, TypeTools.toString(type)));
				}
				continue;
			}
			if (OcamlRepresentationRegistry.isExactNullInt(type)) {
				if (binding == null)
					throw 'reflaxe.ocaml [ocaml-representation:missing-nullable-primitive-binding]: local ${decision.localId} needs a function/body binding for occurrence-bound conversions';
				if (unsupportedNullableLocalIds.exists(decision.localId)) {
					decisions.push(unmigratedDecision(decision.localId, "Null<Int>"));
				} else {
					final domain = localDomain(decision);
					final representation = representations.selectExactNullInt(domain);
					decisions.push({
						localId: decision.localId,
						choice: OcamlLocalRepresentationChoice.ProgramDecision(representation.id, representation.semanticTypeId, domain),
						initializerConversion: OcamlLocalCarrierConversion.LegacyCoercion,
						assignmentConversion: OcamlLocalCarrierConversion.LegacyCoercion,
						readConversion: OcamlLocalCarrierConversion.LegacyCoercion
					});
				}
				continue;
			}
			if (OcamlRepresentationRegistry.isExactNullBool(type)) {
				if (binding == null)
					throw 'reflaxe.ocaml [ocaml-representation:missing-nullable-primitive-binding]: local ${decision.localId} needs a function/body binding for occurrence-bound conversions';
				if (unsupportedNullableLocalIds.exists(decision.localId)) {
					decisions.push(unmigratedDecision(decision.localId, "Null<Bool>"));
				} else {
					final domain = localDomain(decision);
					final representation = representations.selectExactNullBool(domain);
					decisions.push({
						localId: decision.localId,
						choice: OcamlLocalRepresentationChoice.ProgramDecision(representation.id, representation.semanticTypeId, domain),
						initializerConversion: OcamlLocalCarrierConversion.LegacyCoercion,
						assignmentConversion: OcamlLocalCarrierConversion.LegacyCoercion,
						readConversion: OcamlLocalCarrierConversion.LegacyCoercion
					});
				}
				continue;
			}
			if (OcamlRepresentationRegistry.isExactBool(type)) {
				if (!unsupportedBoolLocalIds.exists(decision.localId)) {
					final domain = localDomain(decision);
					final representation = representations.selectExactBool(domain);
					decisions.push({
						localId: decision.localId,
						choice: OcamlLocalRepresentationChoice.ProgramDecision(representation.id, representation.semanticTypeId, domain),
						initializerConversion: OcamlLocalCarrierConversion.Identity,
						assignmentConversion: OcamlLocalCarrierConversion.Identity,
						readConversion: OcamlLocalCarrierConversion.Identity
					});
				} else {
					decisions.push(unmigratedDecision(decision.localId, "Bool"));
				}
				continue;
			}
			if (!OcamlRepresentationRegistry.isExactInt(type)) {
				decisions.push(unmigratedDecision(decision.localId, TypeTools.toString(type)));
				continue;
			}
			final domain = localDomain(decision);
			final representation = representations.selectExactInt(domain);
			decisions.push({
				localId: decision.localId,
				choice: OcamlLocalRepresentationChoice.ProgramDecision(representation.id, representation.semanticTypeId, domain),
				initializerConversion: OcamlLocalCarrierConversion.LegacyCoercion,
				assignmentConversion: OcamlLocalCarrierConversion.LegacyCoercion,
				readConversion: OcamlLocalCarrierConversion.LegacyCoercion
			});
		}
		final localIds = [for (localId in typeByLocalId.keys()) localId];
		localIds.sort((left, right) -> left - right);
		for (localId in localIds) {
			if (plannedLocalIds.exists(localId))
				continue;
			final type = cast typeByLocalId.get(localId);
			if (declaredLocalIds.exists(localId)
				&& OcamlRepresentationRegistry.isExactBool(type)
				&& !unsupportedBoolLocalIds.exists(localId)) {
				final representation = representations.selectExactBool(OcamlRepresentationDomain.InternalValue);
				decisions.push({
					localId: localId,
					choice: OcamlLocalRepresentationChoice.ProgramDecision(representation.id, representation.semanticTypeId,
						OcamlRepresentationDomain.InternalValue),
					initializerConversion: OcamlLocalCarrierConversion.Identity,
					assignmentConversion: OcamlLocalCarrierConversion.Identity,
					readConversion: OcamlLocalCarrierConversion.Identity
				});
				continue;
			}
			if (declaredLocalIds.exists(localId)
				&& (OcamlRepresentationRegistry.isExactNullInt(type) || OcamlRepresentationRegistry.isExactNullBool(type))
				&& !unsupportedNullableLocalIds.exists(localId)) {
				if (binding == null)
					throw 'reflaxe.ocaml [ocaml-representation:missing-nullable-primitive-binding]: local $localId needs a function/body binding for occurrence-bound conversions';
				final representation = OcamlRepresentationRegistry.isExactNullInt(type) ? representations.selectExactNullInt(OcamlRepresentationDomain.InternalValue) : representations.selectExactNullBool(OcamlRepresentationDomain.InternalValue);
				decisions.push({
					localId: localId,
					choice: OcamlLocalRepresentationChoice.ProgramDecision(representation.id, representation.semanticTypeId,
						OcamlRepresentationDomain.InternalValue),
					initializerConversion: OcamlLocalCarrierConversion.LegacyCoercion,
					assignmentConversion: OcamlLocalCarrierConversion.LegacyCoercion,
					readConversion: OcamlLocalCarrierConversion.LegacyCoercion
				});
				continue;
			}
			if (!OcamlRepresentationRegistry.isExactArrayInt(type) || identityArrayInitializerByLocalId.get(localId) != true) {
				continue;
			}
			final representation = representations.selectExactArrayInt(OcamlRepresentationDomain.InternalValue);
			decisions.push({
				localId: localId,
				choice: OcamlLocalRepresentationChoice.ProgramDecision(representation.id, representation.semanticTypeId,
					OcamlRepresentationDomain.InternalValue),
				initializerConversion: OcamlLocalCarrierConversion.Identity,
				assignmentConversion: OcamlLocalCarrierConversion.Identity,
				readConversion: OcamlLocalCarrierConversion.Identity
			});
		}
		final admittedNullableLocalIds:Map<Int, Bool> = [];
		for (decision in decisions) {
			switch (decision.choice) {
				case ProgramDecision(_, semanticTypeId, _) if (semanticTypeId == "Null<Int>" || semanticTypeId == "Null<Bool>"):
					admittedNullableLocalIds.set(decision.localId, true);
				case _:
			}
		}
		final conversions:Array<OcamlLocalConversionDecision> = [];
		if (binding != null) {
			for (pending in pendingNullableConversions) {
				if (admittedNullableLocalIds.exists(pending.localId))
					conversions.push(sealNullablePrimitiveConversion(binding, pending));
			}
		}
		return new OcamlLocalRepresentationPlan(decisions, conversions);
	}

	static function nullIntWriteInput(expression:TypedExpr):Null<{
		semanticTypeId:String,
		carrierTypeId:String,
		sourceLocalId:Null<Int>,
		conversion:OcamlLocalCarrierConversion
	}> {
		return switch (unwrapTransparent(expression).expr) {
			case TConst(TNull): {
					semanticTypeId: "Null<Int>",
					carrierTypeId: "Obj.t",
					sourceLocalId: null,
					conversion: OcamlLocalCarrierConversion.PreserveNullableIntCarrier
				};
			case TConst(TInt(_)): {
					semanticTypeId: "Int",
					carrierTypeId: "int",
					sourceLocalId: null,
					conversion: OcamlLocalCarrierConversion.BoxExactIntToNullableInt
				};
			case TLocal(local) if (OcamlRepresentationRegistry.isExactInt(local.t)): {
					semanticTypeId: "Int",
					carrierTypeId: "int",
					sourceLocalId: local.id,
					conversion: OcamlLocalCarrierConversion.BoxExactIntToNullableInt
				};
			case TLocal(local) if (OcamlRepresentationRegistry.isExactNullInt(local.t)): {
					semanticTypeId: "Null<Int>",
					carrierTypeId: "Obj.t",
					sourceLocalId: local.id,
					conversion: OcamlLocalCarrierConversion.PreserveNullableIntCarrier
				};
			case _:
				if (OcamlRepresentationRegistry.isExactInt(expression.t)) {
					{
						semanticTypeId: "Int",
						carrierTypeId: "int",
						sourceLocalId: null,
						conversion: OcamlLocalCarrierConversion.BoxExactIntToNullableInt
					};
				} else if (OcamlRepresentationRegistry.isExactNullInt(expression.t)) {
					{
						semanticTypeId: "Null<Int>",
						carrierTypeId: "Obj.t",
						sourceLocalId: null,
						conversion: OcamlLocalCarrierConversion.PreserveNullableIntCarrier
					};
				} else {
					null;
				}
		}
	}

	static function nullBoolWriteInput(expression:TypedExpr, declaredLocalIds:Map<Int, Bool>):Null<{
		semanticTypeId:String,
		carrierTypeId:String,
		sourceLocalId:Null<Int>,
		conversion:OcamlLocalCarrierConversion
	}> {
		return switch (unwrapTransparent(expression).expr) {
			case TConst(TNull): {
					semanticTypeId: "Null<Bool>",
					carrierTypeId: "Obj.t",
					sourceLocalId: null,
					conversion: OcamlLocalCarrierConversion.PreserveNullableBoolCarrier
				};
			case TConst(TBool(_)): {
					semanticTypeId: "Bool",
					carrierTypeId: "bool",
					sourceLocalId: null,
					conversion: OcamlLocalCarrierConversion.BoxExactBoolToNullableBool
				};
			case TLocal(local) if (declaredLocalIds.exists(local.id) && OcamlRepresentationRegistry.isExactNullBool(local.t)): {
					semanticTypeId: "Null<Bool>",
					carrierTypeId: "Obj.t",
					sourceLocalId: local.id,
					conversion: OcamlLocalCarrierConversion.PreserveNullableBoolCarrier
				};
			case TLocal(local) if (declaredLocalIds.exists(local.id) && OcamlRepresentationRegistry.isExactBool(local.t)): {
					semanticTypeId: "Bool",
					carrierTypeId: "bool",
					sourceLocalId: local.id,
					conversion: OcamlLocalCarrierConversion.BoxExactBoolToNullableBool
				};
			case _:
				null;
		}
	}

	static function unwrapTransparent(expression:TypedExpr):TypedExpr {
		var current = expression;
		while (true) {
			switch (current.expr) {
				case TMeta(_, child), TParenthesis(child):
					current = child;
				case _:
					return current;
			}
		}
	}

	static function sealNullablePrimitiveConversion(binding:OcamlFunctionPlanBinding, pending:PendingNullablePrimitiveConversion):OcamlLocalConversionDecision {
		final source = OcamlLoweredOrigin.sourceSpan(pending.expression.pos);
		final id = OcamlLocalRepresentationPlan.occurrenceId(binding, pending.localId, pending.role, source);
		final proof = switch (pending.conversion) {
			case PreserveNullableIntCarrier: {
					id: "nullable-int-carrier-preserve-v1",
					claim: "The typed occurrence is either the canonical Haxe null sentinel or an existing exact Null<Int> value, so copying its Obj.t carrier preserves the value without another box."
				};
			case BoxExactIntToNullableInt: {
					id: "nullable-int-box-exact-int-v1",
					claim: "The typed input is an exact non-null Haxe Int represented by OCaml int. Obj.repr stores that value in the selected nullable Obj.t carrier without changing its integer value."
				};
			case CheckedUnboxNullableInt: {
					id: "nullable-int-checked-read-v1",
					claim: "Haxe flow typing requires an exact Int at this read. HxRuntime.nullable_int_unwrap rejects the null sentinel before returning the boxed OCaml int."
				};
			case PreserveNullableBoolCarrier: {
					id: "nullable-bool-carrier-preserve-v1",
					claim: "The typed occurrence is either the canonical Haxe null sentinel or an existing exact Null<Bool> value, so copying its Obj.t carrier preserves null, false, or true without another box."
				};
			case BoxExactBoolToNullableBool: {
					id: "nullable-bool-box-exact-bool-v1",
					claim: "The typed input is an exact non-null Haxe Bool represented by OCaml bool. Obj.repr stores false or true in the selected nullable Obj.t carrier without conflating either value with the null sentinel."
				};
			case NullableBoolTruthiness: {
					id: "nullable-bool-truthiness-v1",
					claim: "The typed parent consumes this exact Null<Bool> occurrence as a condition. The runtime null sentinel produces false, while an existing boxed bool produces its bool value without mutating the stored carrier."
				};
			case LegacyCoercion, Identity:
				throw 'reflaxe.ocaml [ocaml-representation:invalid-nullable-primitive-conversion]: occurrence "$id" cannot seal ${pending.conversion}';
		}
		final reason = switch (pending.conversion) {
			case PreserveNullableIntCarrier: "The source occurrence already produces the selected exact Null<Int> Obj.t carrier.";
			case BoxExactIntToNullableInt: "The source occurrence produces exact Int and must cross into the selected exact Null<Int> carrier once.";
			case CheckedUnboxNullableInt: "The typed read consumes a Null<Int> local as exact Int and must reject the null sentinel before use.";
			case PreserveNullableBoolCarrier: "The source occurrence already produces the selected exact Null<Bool> Obj.t carrier.";
			case BoxExactBoolToNullableBool: "The source occurrence produces exact Bool and must cross into the selected exact Null<Bool> carrier once.";
			case NullableBoolTruthiness: "The typed parent consumes an exact Null<Bool> local as condition truthiness without changing its stored nullable value.";
			case LegacyCoercion, Identity: "";
		}
		final unsafeOperation:Null<OcamlUnsafeOperationRecord> = switch (pending.conversion) {
			case PreserveNullableIntCarrier:
				null;
			case BoxExactIntToNullableInt:
				unsafeRecord(id, OcamlUnsafeOperationKind.ObjReprExactInt, source, pending, reason, proof.id, proof.claim, binding);
			case CheckedUnboxNullableInt:
				unsafeRecord(id, OcamlUnsafeOperationKind.CheckedNullableIntUnwrap, source, pending, reason, proof.id, proof.claim, binding);
			case PreserveNullableBoolCarrier:
				null;
			case BoxExactBoolToNullableBool:
				unsafeRecord(id, OcamlUnsafeOperationKind.ObjReprExactBool, source, pending, reason, proof.id, proof.claim, binding);
			case NullableBoolTruthiness:
				unsafeRecord(id, OcamlUnsafeOperationKind.NullableBoolTruthiness, source, pending, reason, proof.id, proof.claim, binding);
			case LegacyCoercion, Identity:
				null;
		}
		return {
			id: id,
			localId: pending.localId,
			role: pending.role,
			source: source,
			inputSemanticTypeId: pending.inputSemanticTypeId,
			inputCarrierTypeId: pending.inputCarrierTypeId,
			outputSemanticTypeId: pending.outputSemanticTypeId,
			outputCarrierTypeId: pending.outputCarrierTypeId,
			conversion: pending.conversion,
			reason: reason,
			proofId: proof.id,
			proofClaim: proof.claim,
			profileEligibility: ["metal", "portable"],
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision,
			unsafeOperation: unsafeOperation
		};
	}

	static function unsafeRecord(conversionId:String, operation:OcamlUnsafeOperationKind,
			source:reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan, pending:PendingNullablePrimitiveConversion, reason:String, proofId:String,
			proofClaim:String, binding:OcamlFunctionPlanBinding):OcamlUnsafeOperationRecord {
		return {
			id: conversionId + ":unsafe:" + (operation : String),
			conversionId: conversionId,
			operation: operation,
			source: source,
			inputSemanticTypeId: pending.inputSemanticTypeId,
			inputCarrierTypeId: pending.inputCarrierTypeId,
			outputSemanticTypeId: pending.outputSemanticTypeId,
			outputCarrierTypeId: pending.outputCarrierTypeId,
			reason: reason,
			proofId: proofId,
			proofClaim: proofClaim,
			profileEligibility: ["metal", "portable"],
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision
		};
	}

	static function unmigratedDecision(localId:Int, semanticTypeId:String):OcamlLocalRepresentationDecision {
		return {
			localId: localId,
			choice: OcamlLocalRepresentationChoice.Unmigrated(semanticTypeId),
			initializerConversion: OcamlLocalCarrierConversion.LegacyCoercion,
			assignmentConversion: OcamlLocalCarrierConversion.LegacyCoercion,
			readConversion: OcamlLocalCarrierConversion.LegacyCoercion
		};
	}

	static function localDomain(decision:OcamlLocalStorageDecision):OcamlRepresentationDomain {
		if (decision.storage == OcamlLocalStorageKind.ImmutableRebinding)
			return OcamlRepresentationDomain.InternalValue;
		for (reason in decision.reasons) {
			if (reason == OcamlLocalStorageReason.CapturedAndMutated)
				return OcamlRepresentationDomain.CapturedLocalStorage;
		}
		return OcamlRepresentationDomain.MutableLocalStorage;
	}
}
#end
