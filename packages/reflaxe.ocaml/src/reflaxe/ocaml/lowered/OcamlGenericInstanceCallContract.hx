package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
#if (macro || reflaxe_runtime)
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.parameterId as genericValueParameterId;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.shape as genericValueShape;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import haxe.crypto.Sha256;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallDecision;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallKind;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallResultKind;
#end
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.crossing as genericValueCrossing;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.matchInstantiation as genericValueMatchInstantiation;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.shapeId as genericValueShapeId;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueShape;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueConversion;

/** Exact method and storage facts for an ordinary generic instance call. */
typedef OcamlGenericInstanceCallTarget = {
	final moduleId:String;
	final typeName:String;
	final fieldName:String;
	final receiverTypeId:String;
	final receiverRepresentationId:String;
	final ownedParameterIds:Array<String>;
	final declaration:OcamlGenericValueShape;
	final instantiation:OcamlGenericValueShape;
	final argumentShapes:Array<OcamlGenericValueShape>;
	final arguments:Array<OcamlGenericValueConversion>;
	final resultShape:OcamlGenericValueShape;
	final result:OcamlGenericValueConversion;
}

/** Selects generic calls only when the receiver and every storage crossing are proved. */
final PROOF_ID = "generic-instance-storage-crossing-v1";

final PROOF_CLAIM = "One ordinary generic instance method owns the erased type parameters. Its exact concrete instantiation fixes directional argument and result conversions, and a registered monomorphic receiver fixes direct dispatch. The source receiver and arguments are evaluated once in order before invocation.";

#if (macro || reflaxe_runtime)
/** Creates a decision bound to the final caller, source occurrence, and target facts. */
function decision(expression:TypedExpr, target:OcamlGenericInstanceCallTarget, binding:OcamlFunctionPlanBinding):OcamlCallDecision {
	require(target);
	final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
	final id = decisionId(source, target, binding);
	return {
		id: id,
		source: source,
		calleeId: '${target.moduleId}|${target.typeName}::${target.fieldName}',
		sourceModuleId: target.moduleId,
		sourceTypeName: target.typeName,
		sourceFieldName: target.fieldName,
		kind: OcamlCallKind.GenericInstanceHaxeMethod,
		receiver: null,
		arguments: [],
		result: null,
		resultKind: target.resultShape == EffectOnly ? OcamlCallResultKind.EffectOnlyVoid : OcamlCallResultKind.Value,
		evaluationSchedule: OcamlCallPlan.evaluationSchedule(id, target.arguments.length, [], false, true),
		profileEligibility: ["metal", "portable"],
		reason: PROOF_CLAIM,
		proofId: PROOF_ID,
		proofClaim: PROOF_CLAIM,
		functionId: binding.functionId,
		programRevision: binding.programRevision,
		bodyRevision: binding.bodyRevision,
		pipelineRevision: binding.pipelineRevision,
		genericInstanceTarget: copy(target)
	};
}

private function decisionId(source:reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan, target:OcamlGenericInstanceCallTarget,
		binding:OcamlFunctionPlanBinding):String {
	return "call:" + Sha256.encode([
		binding.functionId,
		binding.programRevision,
		binding.bodyRevision,
		binding.pipelineRevision,
		OcamlCallPlan.sourceKey(source),
		fingerprint(target)
	].join("|")).substr(0, 24);
}

/** Checks identity, exact source schedule, and exclusion of unrelated call targets. */
function requireCall(call:OcamlCallDecision):Void {
	final target = call.genericInstanceTarget;
	if (target == null)
		throw "reflaxe.ocaml [ocaml-generic-call:invalid-plan]: missing target";
	require(target);
	final binding:OcamlFunctionPlanBinding = {
		functionId: call.functionId,
		programRevision: call.programRevision,
		bodyRevision: call.bodyRevision,
		pipelineRevision: call.pipelineRevision
	};
	if (call.kind != OcamlCallKind.GenericInstanceHaxeMethod
		|| call.id != decisionId(call.source, target, binding)
		|| call.calleeId != '${target.moduleId}|${target.typeName}::${target.fieldName}'
		|| call.sourceModuleId != target.moduleId
		|| call.sourceTypeName != target.typeName
		|| call.sourceFieldName != target.fieldName
		|| call.receiver != null
		|| call.arguments.length != 0
		|| call.result != null
		|| call.resultMaterialization != null
		|| call.dynamicFunctionTarget != null
		|| call.standardArrayTarget != null
		|| call.standardIMapTarget != null
		|| call.structuralIteratorTarget != null
		|| call.resultKind != (target.resultShape == EffectOnly ? OcamlCallResultKind.EffectOnlyVoid : OcamlCallResultKind.Value)
		|| call.proofId != PROOF_ID
		|| call.proofClaim != PROOF_CLAIM
		|| call.reason.length == 0
		|| call.functionId.length == 0
		|| call.programRevision.length == 0
		|| call.bodyRevision.length == 0
		|| call.pipelineRevision.length == 0
		|| call.source.file.length == 0
		|| call.source.min < 0
		|| call.source.max < call.source.min
		|| call.profileEligibility.join(",") != "metal,portable")
		throw "reflaxe.ocaml [ocaml-generic-call:invalid-plan]: stale or conflicting call facts";
	final expected = OcamlCallPlan.evaluationSchedule(call.id, target.arguments.length, [], false, true);
	if (expected.length != call.evaluationSchedule.length)
		throw "reflaxe.ocaml [ocaml-generic-call:invalid-plan]: incomplete evaluation schedule";
	for (index in 0...expected.length) {
		final actual = call.evaluationSchedule[index];
		final step = expected[index];
		if (actual.kind != step.kind
			|| actual.argumentIndex != step.argumentIndex
			|| actual.sourceArgumentIndex != step.sourceArgumentIndex
			|| actual.slotId != step.slotId)
			throw "reflaxe.ocaml [ocaml-generic-call:invalid-plan]: changed evaluation order";
	}
}
#end

/** Every nested Bool crossing gets one exact helper role, shared by planning and emission. */
function runtimeHelpers(target:OcamlGenericInstanceCallTarget):Array<{role:String, symbol:String}> {
	final helpers:Array<{role:String, symbol:String}> = [];
	function visit(conversion:OcamlGenericValueConversion, role:String):Void {
		switch (conversion) {
			case BoxBoolean:
				helpers.push({role: role, symbol: "HxRuntime.box_bool"});
			case UnboxBoolean:
				helpers.push({role: role, symbol: "HxRuntime.unbox_bool_or_obj"});
			case BoxNullableBoolean, UnboxNullableBoolean:
				helpers.push({role: '$role/null', symbol: "HxRuntime.hx_null"});
				helpers.push({role: '$role/value', symbol: conversion == BoxNullableBoolean ? "HxRuntime.box_bool" : "HxRuntime.unbox_bool_or_obj"});
			case AdaptFunction(arguments, result):
				for (index in 0...arguments.length)
					visit(arguments[index], '$role/argument:$index');
				visit(result, '$role/result');
			case _:
		}
	}
	for (index in 0...target.arguments.length)
		visit(target.arguments[index], 'generic-call:argument:$index');
	visit(target.result, "generic-call:result");
	return helpers;
}

#if (macro || reflaxe_runtime)
/** Resolves one final call without inferring storage from generated syntax. */
function select(expression:TypedExpr, representations:OcamlRepresentationRegistry):Null<OcamlGenericInstanceCallTarget> {
	final receiverType = switch (expression.expr) {
		case TCall({expr: TField(_, FInstance(reference, [], field))}, _) if (field.get().params.length > 0):
			final owner = reference.get();
			(owner.pack ?? []).concat([owner.name]).join(".");
		case _: return null;
	};
	final representation = representations.monomorphicClassValue(receiverType);
	return representation == null ? null : selectWithReceiverProof(expression, representation.id);
}

/** Rechecks final typed facts; the call's program revision owns the registered receiver proof. */
function matches(target:OcamlGenericInstanceCallTarget, expression:TypedExpr):Bool {
	final selected = selectWithReceiverProof(expression, target.receiverRepresentationId);
	return selected != null && fingerprint(selected) == fingerprint(target);
}

private function selectWithReceiverProof(expression:TypedExpr, receiverProof:String):Null<OcamlGenericInstanceCallTarget> {
	return switch (expression.expr) {
		case TCall(callee = {expr: TField(receiver, FInstance(classRef, [], fieldRef))}, arguments):
			final owner = classRef.get();
			final field = fieldRef.get();
			if (owner.isExtern || owner.isInterface || owner.params.length != 0 || owner.meta.has(":native") || field.isExtern || field.meta.has(":native")
				|| field.params.length == 0 || field.overloads.get().length != 0 || !(switch (field.kind) {
					case FMethod(MethNormal): true;
					case _: false;
				}))
				return null;
			final receiverType = (owner.pack ?? []).concat([owner.name]).join(".");
			if (TypeTools.toString(TypeTools.follow(receiver.t)) != receiverType)
				return null;
			final declared = genericValueShape(field.type);
			final instantiated = genericValueShape(callee.t);
			final resultShape = genericValueShape(expression.t);
			final owned:Array<String> = [];
			for (parameter in field.params) {
				final id = genericValueParameterId(parameter.t);
				if (id == null)
					return null;
				owned.push(id);
			}
			if (declared == null
				|| instantiated == null
				|| resultShape == null
				|| !genericValueMatchInstantiation(declared, instantiated, owned, new Map()))
				return null;
			switch ([declared, instantiated]) {
				case [FunctionValue(parameters, result), FunctionValue(actualParameters, actualResult)]
					if (parameters.length == arguments.length && sameShape(resultShape, actualResult)):
					final shapes:Array<OcamlGenericValueShape> = [];
					final conversions:Array<OcamlGenericValueConversion> = [];
					for (index in 0...arguments.length) {
						final shape = genericValueShape(arguments[index].t);
						if (shape == null || !sameShape(shape, actualParameters[index]))
							return null;
						final conversion = genericValueCrossing(shape, parameters[index]);
						if (conversion == null)
							return null;
						shapes.push(shape);
						conversions.push(conversion);
					}
					final convertedResult = genericValueCrossing(result, resultShape);
					if (convertedResult == null)
						return null;
					final target:OcamlGenericInstanceCallTarget = {
						moduleId: owner.module,
						typeName: owner.name,
						fieldName: field.name,
						receiverTypeId: receiverType,
						receiverRepresentationId: receiverProof,
						ownedParameterIds: owned,
						declaration: declared,
						instantiation: instantiated,
						argumentShapes: shapes,
						arguments: conversions,
						resultShape: resultShape,
						result: convertedResult
					};
					require(target);
					target;
				case _: null;
			}
		case _: null;
	}
}
#end

/** Reconstructs conversions from the retained type facts to reject corrupt decisions. */
function require(target:OcamlGenericInstanceCallTarget):Void {
	if (target == null
		|| target.moduleId.length == 0
		|| target.typeName.length == 0
		|| target.fieldName.length == 0
		|| target.receiverTypeId.length == 0
		|| target.receiverRepresentationId.length == 0
		|| target.ownedParameterIds.length == 0
		|| !genericValueMatchInstantiation(target.declaration, target.instantiation, target.ownedParameterIds, new Map()))
		throw "reflaxe.ocaml [ocaml-generic-call:invalid-plan]: incomplete method or inconsistent instantiation";
	switch ([target.declaration, target.instantiation]) {
		case [FunctionValue(parameters, result), FunctionValue(actualParameters, actualResult)]:
			if (parameters.length != target.arguments.length
				|| actualParameters.length != target.argumentShapes.length
				|| !sameShape(actualResult, target.resultShape)
				|| !sameConversion(genericValueCrossing(result, actualResult), target.result))
				throw "reflaxe.ocaml [ocaml-generic-call:invalid-plan]: inconsistent argument or result crossing";
			for (index in 0...parameters.length)
				if (!sameShape(actualParameters[index], target.argumentShapes[index])
					|| !sameConversion(genericValueCrossing(actualParameters[index], parameters[index]), target.arguments[index]))
					throw "reflaxe.ocaml [ocaml-generic-call:invalid-plan]: inconsistent argument conversion";
		case _:
			throw "reflaxe.ocaml [ocaml-generic-call:invalid-plan]: missing function shape";
	}
}

function fingerprint(target:OcamlGenericInstanceCallTarget):String {
	return [
		target.moduleId,
		target.typeName,
		target.fieldName,
		target.receiverTypeId,
		target.receiverRepresentationId,
		target.ownedParameterIds.join(","),
		genericValueShapeId(target.declaration),
		genericValueShapeId(target.instantiation),
		target.argumentShapes.map(genericValueShapeId).join(";"),
		target.arguments.map(value -> Std.string(value)).join(";"),
		genericValueShapeId(target.resultShape),
		Std.string(target.result)
	].join("|");
}

/** Detached copies prevent a caller from changing a stored function or array shape. */
function copy(target:OcamlGenericInstanceCallTarget):OcamlGenericInstanceCallTarget {
	return {
		moduleId: target.moduleId,
		typeName: target.typeName,
		fieldName: target.fieldName,
		receiverTypeId: target.receiverTypeId,
		receiverRepresentationId: target.receiverRepresentationId,
		ownedParameterIds: target.ownedParameterIds.copy(),
		declaration: copyShape(target.declaration),
		instantiation: copyShape(target.instantiation),
		argumentShapes: target.argumentShapes.map(copyShape),
		arguments: target.arguments.map(copyConversion),
		resultShape: copyShape(target.resultShape),
		result: copyConversion(target.result)
	};
}

private function copyShape(value:OcamlGenericValueShape):OcamlGenericValueShape {
	return switch (value) {
		case FunctionValue(arguments, result): FunctionValue(arguments.map(copyShape), copyShape(result));
		case ArrayValue(element): ArrayValue(copyShape(element));
		case _: value;
	}
}

private function copyConversion(value:OcamlGenericValueConversion):OcamlGenericValueConversion {
	return switch (value) {
		case AdaptFunction(arguments, result): AdaptFunction(arguments.map(copyConversion), copyConversion(result));
		case _: value;
	}
}

private function sameShape(left:OcamlGenericValueShape, right:OcamlGenericValueShape):Bool {
	return genericValueShapeId(left) == genericValueShapeId(right);
}

private function sameConversion(left:Null<OcamlGenericValueConversion>, right:OcamlGenericValueConversion):Bool {
	return left != null && Std.string(left) == Std.string(right);
}
#end
