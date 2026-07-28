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

private typedef PendingLocalConversion = {
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

private typedef DynamicCarrierInput = {
	final semanticTypeId:String;
	final carrierTypeId:String;
	final sourceLocalId:Null<Int>;
	final conversion:OcamlLocalCarrierConversion;
}

private typedef ExactBoolCarrierInput = {
	final sourceLocalId:Null<Int>;
}

private typedef ExactStringCarrierInput = {
	final sourceLocalId:Null<Int>;
}

private typedef ExactMonomorphicClassCarrierInput = {
	final sourceLocalId:Null<Int>;
	final semanticTypeId:String;
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
	Exact core `String` locals use the registry's nullable string carrier only
	when omitted initialization or every explicit initializer/replacement already
	produces that carrier. An explicit null expression remains unadmitted because
	it needs its own occurrence-bound unsafe conversion. Immutable `Dynamic`
	locals created by inline parameter expansion use one internal `Obj.t` carrier:
	each final typed initializer either preserves an existing Dynamic/null carrier,
	boxes exact Bool with its distinguishable runtime tag, or records one
	`Obj.repr` conversion for an admitted concrete payload. Unsupported or
	ambiguous occurrences keep the entire local on the legacy path.
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

	/**
		Returns whether an expression already produces the exact String carrier.

		The direct carrier admits literals, concatenations, admitted calls, and
		previously declared exact String locals. Casts from another carrier, field
		reads without a field-plan callback, and unplanned calls remain outside the
		slice. A null literal is deliberately rejected: only an implicit default
		is covered by the representation-level unsafe proof in this slice.
	**/
	static function exactStringCarrierInput(expression:TypedExpr, declaredLocalIds:Map<Int, Bool>,
			producesExactString:Null<TypedExpr->Bool>):Null<ExactStringCarrierInput> {
		if (!OcamlRepresentationRegistry.isExactString(expression.t))
			return null;
		final unwrapped = unwrapTransparent(expression);
		return switch (unwrapped.expr) {
			case TConst(TNull):
				null;
			case TConst(TString(_)):
				{sourceLocalId: null};
			case TLocal(local) if (declaredLocalIds.exists(local.id) && OcamlRepresentationRegistry.isExactString(local.t)):
				{sourceLocalId: local.id};
			case TCast(child, _) if (OcamlRepresentationRegistry.isExactString(child.t)):
				exactStringCarrierInput(child, declaredLocalIds, producesExactString);
			case TCast(_, _):
				null;
			case TBinop(OpAdd, _, _):
				{sourceLocalId: null};
			case TCall(_, _) if (producesExactString != null && producesExactString(unwrapped)):
				{sourceLocalId: null};
			case _:
				null;
		}
	}

	/**
		Returns whether an expression already produces one admitted nominal record.

		Only a direct constructor or a local with the same exact sealed class layout
		is eligible. Immutable capture does not change that carrier: the closure
		retains the same binding. Calls, parameters, fields, null, Dynamic, mutable
		hierarchy conversions, and native values remain explicit future boundaries.
		Whether a local may replace that value is decided separately by the sealed
		local-storage plan.
	**/
	static function exactMonomorphicClassCarrierInput(expression:TypedExpr, declaredLocalIds:Map<Int, Bool>, classSemanticTypeByLocalId:Map<Int, String>,
			representations:OcamlRepresentationRegistry):Null<ExactMonomorphicClassCarrierInput> {
		final layout = representations.monomorphicClassForType(expression.t);
		if (layout == null)
			return null;
		final unwrapped = unwrapTransparent(expression);
		return switch (unwrapped.expr) {
			case TNew(classRef, parameters, _):
				final classType = classRef.get();
				final semanticTypeId = (classType.pack ?? []).concat([classType.name]).join(".");
				if (parameters.length == 0 && semanticTypeId == layout.semanticTypeId) {
					{sourceLocalId: null, semanticTypeId: semanticTypeId};
				} else {
					null;
				}
			case TLocal(local) if (declaredLocalIds.exists(local.id) && classSemanticTypeByLocalId.get(local.id) == layout.semanticTypeId):
				{sourceLocalId: local.id, semanticTypeId: layout.semanticTypeId};
			case TCast(child, _) if (representations.monomorphicClassForType(child.t) != null):
				exactMonomorphicClassCarrierInput(child, declaredLocalIds, classSemanticTypeByLocalId, representations);
			case _:
				null;
		}
	}

	/**
		Classifies the exact payload entering an immutable Dynamic local.

		Haxe exposes an inline concrete-to-Dynamic conversion as `TCast(child)`.
		Keeping the concrete child visible lets the occurrence record name the
		value being boxed. A Dynamic local or the null sentinel already uses the
		selected Obj.t carrier and is preserved.
	**/
	static function dynamicCarrierInput(expression:TypedExpr, declaredLocalIds:Map<Int, Bool>,
			representations:OcamlRepresentationRegistry):Null<DynamicCarrierInput> {
		final unwrapped = unwrapTransparent(expression);
		return switch (unwrapped.expr) {
			case TConst(TNull):
				{
					semanticTypeId: "Dynamic",
					carrierTypeId: "Obj.t",
					sourceLocalId: null,
					conversion: OcamlLocalCarrierConversion.PreserveDynamicCarrier
				};
			case TLocal(local) if (OcamlRepresentationRegistry.isExactDynamic(local.t)):
				{
					semanticTypeId: "Dynamic",
					carrierTypeId: "Obj.t",
					sourceLocalId: local.id,
					conversion: OcamlLocalCarrierConversion.PreserveDynamicCarrier
				};
			case TCast(child, null):
				dynamicConcreteCarrierInput(child, declaredLocalIds, representations);
			case _:
				null;
		}
	}

	/** Returns the closed concrete carrier matrix admitted into Dynamic. */
	static function dynamicConcreteCarrierInput(expression:TypedExpr, declaredLocalIds:Map<Int, Bool>,
			representations:OcamlRepresentationRegistry):Null<DynamicCarrierInput> {
		final unwrapped = unwrapTransparent(expression);
		final sourceLocalId = switch (unwrapped.expr) {
			case TLocal(local) if (declaredLocalIds.exists(local.id)): local.id;
			case _: null;
		}
		if (OcamlRepresentationRegistry.isExactInt(unwrapped.t))
			return dynamicBoxInput("Int", "int", sourceLocalId);
		if (OcamlRepresentationRegistry.isExactFloat(unwrapped.t))
			return dynamicBoxInput("Float", "float", sourceLocalId);
		if (OcamlRepresentationRegistry.isExactBool(unwrapped.t))
			return {
				semanticTypeId: "Bool",
				carrierTypeId: "bool",
				sourceLocalId: sourceLocalId,
				conversion: OcamlLocalCarrierConversion.BoxExactBoolToDynamic
			};
		if (OcamlRepresentationRegistry.isExactString(unwrapped.t))
			return dynamicBoxInput("String", "string", sourceLocalId);
		final layout = representations.monomorphicClassForType(unwrapped.t);
		if (layout != null)
			return dynamicBoxInput(layout.semanticTypeId, layout.targetTypeName, sourceLocalId);
		return switch (unwrapped.t) {
			case TAnonymous(_):
				dynamicBoxInput(TypeTools.toString(unwrapped.t), "Obj.t", sourceLocalId);
			case _:
				null;
		}
	}

	static function dynamicBoxInput(semanticTypeId:String, carrierTypeId:String, sourceLocalId:Null<Int>):DynamicCarrierInput {
		return {
			semanticTypeId: semanticTypeId,
			carrierTypeId: carrierTypeId,
			sourceLocalId: sourceLocalId,
			conversion: OcamlLocalCarrierConversion.BoxConcreteToDynamic
		};
	}

	/** Plans registry references and initializer conversions from one final typed body. */
	public static function planExpression(expression:TypedExpr, storage:OcamlLocalStoragePlan, representations:OcamlRepresentationRegistry,
			?binding:OcamlFunctionPlanBinding, ?preservesNullableBoolArgument:(TypedExpr, Int) -> Bool, ?producesNullableBool:TypedExpr->Bool,
			?producesExactString:TypedExpr->Bool):OcamlLocalRepresentationPlan {
		final typeByLocalId:Map<Int, Type> = [];
		final declaredLocalIds:Map<Int, Bool> = [];
		final identityBoolInitializerByLocalId:Map<Int, Bool> = [];
		final identityBoolAssignmentsByLocalId:Map<Int, Bool> = [];
		final boolSourceLocalIdsByLocalId:Map<Int, Array<Int>> = [];
		final identityStringInitializerByLocalId:Map<Int, Bool> = [];
		final identityStringAssignmentsByLocalId:Map<Int, Bool> = [];
		final stringSourceLocalIdsByLocalId:Map<Int, Array<Int>> = [];
		final classSemanticTypeByLocalId:Map<Int, String> = [];
		final identityClassInitializerByLocalId:Map<Int, Bool> = [];
		final identityClassAssignmentsByLocalId:Map<Int, Bool> = [];
		final classSourceLocalIdsByLocalId:Map<Int, Array<Int>> = [];
		final identityArrayInitializerByLocalId:Map<Int, Bool> = [];
		final identityArrayAssignmentsByLocalId:Map<Int, Bool> = [];
		final unsupportedNullableLocalIds:Map<Int, Bool> = [];
		final pendingNullableConversions:Array<PendingLocalConversion> = [];
		final pendingDynamicConversions:Array<PendingLocalConversion> = [];
		final unsupportedDynamicLocalIds:Map<Int, Bool> = [];

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
			final input = nullBoolWriteInput(value, declaredLocalIds, producesNullableBool);
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

		function addDynamicInitializer(localId:Int, value:TypedExpr):Bool {
			final input = dynamicCarrierInput(value, declaredLocalIds, representations);
			if (input == null) {
				unsupportedDynamicLocalIds.set(localId, true);
				return false;
			}
			pendingDynamicConversions.push({
				localId: localId,
				sourceLocalId: input.sourceLocalId,
				role: OcamlLocalConversionRole.Initializer,
				expression: value,
				inputSemanticTypeId: input.semanticTypeId,
				inputCarrierTypeId: input.carrierTypeId,
				outputSemanticTypeId: "Dynamic",
				outputCarrierTypeId: "Obj.t",
				conversion: input.conversion
			});
			return true;
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

		function isPlannedNullableBoolArgument(callExpression:TypedExpr, argumentIndex:Int):Bool {
			return preservesNullableBoolArgument != null && preservesNullableBoolArgument(callExpression, argumentIndex);
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
					final classLayout = representations.monomorphicClassForType(local.t);
					if (classLayout != null) {
						classSemanticTypeByLocalId.set(local.id, classLayout.semanticTypeId);
						final input = initializer == null ? null : exactMonomorphicClassCarrierInput(initializer, declaredLocalIds,
							classSemanticTypeByLocalId, representations);
						identityClassInitializerByLocalId.set(local.id, input != null
							&& input.semanticTypeId == classLayout.semanticTypeId);
						if (input != null && input.sourceLocalId != null)
							classSourceLocalIdsByLocalId.set(local.id, [input.sourceLocalId]);
					}
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
					if (OcamlRepresentationRegistry.isExactString(local.t)) {
						final input:Null<ExactStringCarrierInput> = initializer == null ? {sourceLocalId: null} : exactStringCarrierInput(initializer,
							declaredLocalIds, producesExactString);
						identityStringInitializerByLocalId.set(local.id, input != null);
						if (input != null && input.sourceLocalId != null)
							stringSourceLocalIdsByLocalId.set(local.id, [input.sourceLocalId]);
					}
					if (OcamlRepresentationRegistry.isExactNullInt(local.t) && initializer != null)
						addNullIntWrite(local.id, OcamlLocalConversionRole.Initializer, initializer);
					if (OcamlRepresentationRegistry.isExactNullBool(local.t) && initializer != null)
						addNullBoolWrite(local.id, OcamlLocalConversionRole.Initializer, initializer);
					if (OcamlRepresentationRegistry.isExactDynamic(local.t)) {
						if (initializer == null)
							unsupportedDynamicLocalIds.set(local.id, true);
						else
							addDynamicInitializer(local.id, initializer);
					}
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
						case TLocal(local) if (OcamlRepresentationRegistry.isExactDynamic(local.t)):
							record(local.id, local.t);
							unsupportedDynamicLocalIds.set(local.id, true);
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
						case TLocal(local) if (OcamlRepresentationRegistry.isExactString(local.t)):
							final input = exactStringCarrierInput(right, declaredLocalIds, producesExactString);
							final identityAssignment = input != null;
							if (!identityAssignment || !identityStringAssignmentsByLocalId.exists(local.id))
								identityStringAssignmentsByLocalId.set(local.id, identityAssignment);
							if (input != null && input.sourceLocalId != null) {
								final sources = stringSourceLocalIdsByLocalId.get(local.id);
								if (sources == null)
									stringSourceLocalIdsByLocalId.set(local.id, [input.sourceLocalId]);
								else if (sources.indexOf(input.sourceLocalId) < 0)
									sources.push(input.sourceLocalId);
							}
						case TLocal(local) if (classSemanticTypeByLocalId.exists(local.id)):
							final expectedSemanticTypeId:String = cast classSemanticTypeByLocalId.get(local.id);
							final input = exactMonomorphicClassCarrierInput(right, declaredLocalIds, classSemanticTypeByLocalId, representations);
							final identityAssignment = input != null && input.semanticTypeId == expectedSemanticTypeId;
							if (!identityAssignment || !identityClassAssignmentsByLocalId.exists(local.id))
								identityClassAssignmentsByLocalId.set(local.id, identityAssignment);
							if (input != null && input.sourceLocalId != null) {
								final sources = classSourceLocalIdsByLocalId.get(local.id);
								if (sources == null)
									classSourceLocalIdsByLocalId.set(local.id, [input.sourceLocalId]);
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
					for (index in 0...arguments.length) {
						final argument = arguments[index];
						if (!isPlannedNullableBoolArgument(current, index))
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
				case TBinop(OpAssignOp(op), left, right):
					switch (left.expr) {
						case TLocal(local) if (OcamlRepresentationRegistry.isExactNullInt(local.t)):
							unsupportedNullableLocalIds.set(local.id, true);
						case TLocal(local) if (OcamlRepresentationRegistry.isExactNullBool(local.t)):
							unsupportedNullableLocalIds.set(local.id, true);
						case TLocal(local) if (OcamlRepresentationRegistry.isExactDynamic(local.t)):
							unsupportedDynamicLocalIds.set(local.id, true);
						case _:
					}
					final isNumericOperation = switch (op) {
						case OpAdd | OpSub | OpMult | OpDiv | OpMod | OpAnd | OpOr | OpXor | OpShl | OpShr | OpUShr:
							true;
						case _:
							false;
					}
					final isStringConcat = op == OpAdd
						&& (TypeTools.toString(left.t) == "String"
							|| TypeTools.toString(right.t) == "String"
							|| TypeTools.toString(current.t) == "String");
					visit(left);
					if (isNumericOperation && !isStringConcat)
						visitCheckedInt(right);
					else
						visit(right);
					visitChildren = false;
				case TUnop(OpIncrement | OpDecrement, _, left):
					switch (left.expr) {
						case TLocal(local) if (OcamlRepresentationRegistry.isExactNullInt(local.t)):
							unsupportedNullableLocalIds.set(local.id, true);
						case TLocal(local) if (OcamlRepresentationRegistry.isExactNullBool(local.t)):
							unsupportedNullableLocalIds.set(local.id, true);
						case TLocal(local) if (OcamlRepresentationRegistry.isExactDynamic(local.t)):
							unsupportedDynamicLocalIds.set(local.id, true);
						case _:
					}
				case _:
			}
			if (visitChildren)
				TypedExprTools.iter(current, visit);
		};

		visit(expression);
		final unsupportedBoolLocalIds:Map<Int, Bool> = [];
		final unsupportedStringLocalIds:Map<Int, Bool> = [];
		final unsupportedClassLocalIds:Map<Int, Bool> = [];
		for (localId in declaredLocalIds.keys()) {
			final type = typeByLocalId.get(localId);
			if (type != null
				&& OcamlRepresentationRegistry.isExactBool(type)
				&& (identityBoolInitializerByLocalId.get(localId) != true || identityBoolAssignmentsByLocalId.get(localId) == false))
				unsupportedBoolLocalIds.set(localId, true);
			if (type != null
				&& OcamlRepresentationRegistry.isExactString(type)
				&& (identityStringInitializerByLocalId.get(localId) != true || identityStringAssignmentsByLocalId.get(localId) == false))
				unsupportedStringLocalIds.set(localId, true);
			if (classSemanticTypeByLocalId.exists(localId)
				&& (identityClassInitializerByLocalId.get(localId) != true
					|| identityClassAssignmentsByLocalId.get(localId) == false
					|| (storage.decisionFor(localId) != null && !storage.isCaptured(localId))))
				unsupportedClassLocalIds.set(localId, true);
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
		var propagatedUnsupportedString = true;
		while (propagatedUnsupportedString) {
			propagatedUnsupportedString = false;
			for (localId in stringSourceLocalIdsByLocalId.keys()) {
				if (unsupportedStringLocalIds.exists(localId))
					continue;
				final sourceLocalIds:Array<Int> = cast stringSourceLocalIdsByLocalId.get(localId);
				for (sourceLocalId in sourceLocalIds) {
					if (unsupportedStringLocalIds.exists(sourceLocalId)) {
						unsupportedStringLocalIds.set(localId, true);
						propagatedUnsupportedString = true;
						break;
					}
				}
			}
		}
		var propagatedUnsupportedClass = true;
		while (propagatedUnsupportedClass) {
			propagatedUnsupportedClass = false;
			for (localId in classSourceLocalIdsByLocalId.keys()) {
				if (unsupportedClassLocalIds.exists(localId))
					continue;
				final sourceLocalIds:Array<Int> = cast classSourceLocalIdsByLocalId.get(localId);
				for (sourceLocalId in sourceLocalIds) {
					if (unsupportedClassLocalIds.exists(sourceLocalId)
						|| classSemanticTypeByLocalId.get(sourceLocalId) != classSemanticTypeByLocalId.get(localId)) {
						unsupportedClassLocalIds.set(localId, true);
						propagatedUnsupportedClass = true;
						break;
					}
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
			for (pending in pendingNullableConversions.concat(pendingDynamicConversions)) {
				final source = OcamlLoweredOrigin.sourceSpan(pending.expression.pos);
				final occurrenceId = OcamlLocalRepresentationPlan.occurrenceId(binding, pending.localId, pending.role, source);
				final existingLocalId = occurrenceOwnerById.get(occurrenceId);
				if (existingLocalId != null) {
					if (pending.outputSemanticTypeId == "Dynamic") {
						unsupportedDynamicLocalIds.set(existingLocalId, true);
						unsupportedDynamicLocalIds.set(pending.localId, true);
					} else {
						unsupportedNullableLocalIds.set(existingLocalId, true);
						unsupportedNullableLocalIds.set(pending.localId, true);
					}
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
			if (classSemanticTypeByLocalId.exists(decision.localId)) {
				final domain = localDomain(decision);
				if (unsupportedClassLocalIds.exists(decision.localId) || domain != OcamlRepresentationDomain.CapturedLocalStorage) {
					decisions.push(unmigratedDecision(decision.localId, TypeTools.toString(type)));
				} else {
					final representation = representations.selectMonomorphicClassValue(type, domain);
					if (representation == null)
						throw 'reflaxe.ocaml [ocaml-representation:missing-class-layout]: local ${decision.localId} lost its admitted monomorphic class decision';
					decisions.push({
						localId: decision.localId,
						choice: OcamlLocalRepresentationChoice.ProgramDecision(representation.id, representation.semanticTypeId, domain),
						initializerConversion: OcamlLocalCarrierConversion.Identity,
						assignmentConversion: OcamlLocalCarrierConversion.Identity,
						readConversion: OcamlLocalCarrierConversion.Identity
					});
				}
				continue;
			}
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
			if (OcamlRepresentationRegistry.isExactString(type)) {
				if (!unsupportedStringLocalIds.exists(decision.localId)) {
					final domain = localDomain(decision);
					final representation = representations.selectExactString(domain);
					decisions.push({
						localId: decision.localId,
						choice: OcamlLocalRepresentationChoice.ProgramDecision(representation.id, representation.semanticTypeId, domain),
						initializerConversion: OcamlLocalCarrierConversion.Identity,
						assignmentConversion: OcamlLocalCarrierConversion.Identity,
						readConversion: OcamlLocalCarrierConversion.Identity
					});
				} else {
					decisions.push(unmigratedDecision(decision.localId, "String"));
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
				&& OcamlRepresentationRegistry.isExactString(type)
				&& !unsupportedStringLocalIds.exists(localId)) {
				final representation = representations.selectExactString(OcamlRepresentationDomain.InternalValue);
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
				&& classSemanticTypeByLocalId.exists(localId)
				&& !unsupportedClassLocalIds.exists(localId)) {
				final representation = representations.selectMonomorphicClassValue(type, OcamlRepresentationDomain.InternalValue);
				if (representation == null)
					throw 'reflaxe.ocaml [ocaml-representation:missing-class-layout]: local $localId lost its admitted monomorphic class decision';
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
			if (declaredLocalIds.exists(localId)
				&& OcamlRepresentationRegistry.isExactDynamic(type)
				&& !unsupportedDynamicLocalIds.exists(localId)) {
				if (binding == null)
					throw 'reflaxe.ocaml [ocaml-representation:missing-dynamic-binding]: local $localId needs a function/body binding for its concrete-to-Dynamic occurrence';
				final representation = representations.selectExactDynamic(OcamlRepresentationDomain.InternalValue);
				decisions.push({
					localId: localId,
					choice: OcamlLocalRepresentationChoice.ProgramDecision(representation.id, representation.semanticTypeId,
						OcamlRepresentationDomain.InternalValue),
					initializerConversion: OcamlLocalCarrierConversion.LegacyCoercion,
					assignmentConversion: OcamlLocalCarrierConversion.LegacyCoercion,
					readConversion: OcamlLocalCarrierConversion.Identity
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
		final admittedDynamicLocalIds:Map<Int, Bool> = [];
		for (decision in decisions) {
			switch (decision.choice) {
				case ProgramDecision(_, semanticTypeId, _) if (semanticTypeId == "Null<Int>" || semanticTypeId == "Null<Bool>"):
					admittedNullableLocalIds.set(decision.localId, true);
				case ProgramDecision(_, "Dynamic", _):
					admittedDynamicLocalIds.set(decision.localId, true);
				case _:
			}
		}
		final conversions:Array<OcamlLocalConversionDecision> = [];
		if (binding != null) {
			for (pending in pendingNullableConversions) {
				if (admittedNullableLocalIds.exists(pending.localId))
					conversions.push(sealLocalConversion(binding, pending));
			}
			for (pending in pendingDynamicConversions) {
				if (admittedDynamicLocalIds.exists(pending.localId))
					conversions.push(sealLocalConversion(binding, pending));
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

	static function nullBoolWriteInput(expression:TypedExpr, declaredLocalIds:Map<Int, Bool>, producesNullableBool:Null<TypedExpr->Bool>):Null<{
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
			case TCall(_, _):
				if (producesNullableBool != null && producesNullableBool(unwrapTransparent(expression))) {
					{
						semanticTypeId: "Null<Bool>",
						carrierTypeId: "Obj.t",
						sourceLocalId: null,
						conversion: OcamlLocalCarrierConversion.PreserveNullableBoolCarrier
					};
				} else {
					null;
				}
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

	static function sealLocalConversion(binding:OcamlFunctionPlanBinding, pending:PendingLocalConversion):OcamlLocalConversionDecision {
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
			case PreserveDynamicCarrier: {
					id: "dynamic-carrier-preserve-v1",
					claim: "The typed occurrence already produces Dynamic in Obj.t, including the canonical Haxe null sentinel, so copying that carrier preserves the stored value without another box."
				};
			case BoxConcreteToDynamic: {
					id: "dynamic-box-concrete-value-v1",
					claim: "The typed cast child produces one concrete target value. Obj.repr embeds that already-produced value in Dynamic's Obj.t carrier without rebuilding primitive payloads or reference-bearing objects."
				};
			case BoxExactBoolToDynamic: {
					id: "dynamic-box-exact-bool-v1",
					claim: "OCaml uses immediate values for both Bool and Int, so the runtime's tagged Bool box preserves the exact Haxe Bool identity when it enters Dynamic's Obj.t carrier."
				};
			case LegacyCoercion, Identity:
				throw 'reflaxe.ocaml [ocaml-representation:invalid-local-conversion]: occurrence "$id" cannot seal ${pending.conversion}';
		}
		final reason = switch (pending.conversion) {
			case PreserveNullableIntCarrier: "The source occurrence already produces the selected exact Null<Int> Obj.t carrier.";
			case BoxExactIntToNullableInt: "The source occurrence produces exact Int and must cross into the selected exact Null<Int> carrier once.";
			case CheckedUnboxNullableInt: "The typed read consumes a Null<Int> local as exact Int and must reject the null sentinel before use.";
			case PreserveNullableBoolCarrier: "The source occurrence already produces the selected exact Null<Bool> Obj.t carrier.";
			case BoxExactBoolToNullableBool: "The source occurrence produces exact Bool and must cross into the selected exact Null<Bool> carrier once.";
			case NullableBoolTruthiness: "The typed parent consumes an exact Null<Bool> local as condition truthiness without changing its stored nullable value.";
			case PreserveDynamicCarrier: "The source occurrence already produces the selected Dynamic Obj.t carrier.";
			case BoxConcreteToDynamic: "The source occurrence produces one concrete typed value and must enter the selected Dynamic Obj.t carrier once.";
			case BoxExactBoolToDynamic: "The source occurrence produces exact Bool and must enter Dynamic through the distinguishable runtime Bool box.";
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
			case PreserveDynamicCarrier:
				null;
			case BoxConcreteToDynamic:
				unsafeRecord(id, OcamlUnsafeOperationKind.ObjReprConcreteToDynamic, source, pending, reason, proof.id, proof.claim, binding);
			case BoxExactBoolToDynamic:
				unsafeRecord(id, OcamlUnsafeOperationKind.BoxExactBoolToDynamic, source, pending, reason, proof.id, proof.claim, binding);
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
			source:reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan, pending:PendingLocalConversion, reason:String, proofId:String,
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
