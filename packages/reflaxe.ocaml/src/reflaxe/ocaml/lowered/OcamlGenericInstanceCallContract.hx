package reflaxe.ocaml.lowered;

#if macro
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

/** The nominal type's existing storage owner, retained separately from its semantic name. */
enum abstract OcamlGenericNominalKind(String) to String {
	final ClassRecord = "class";
	final EnumArgument = "enum-argument";
}

typedef OcamlGenericNominalProof = {
	final kind:OcamlGenericNominalKind;
	final typeId:String;
	final representationId:String;
}

/** Exact method and storage facts for an ordinary generic instance call. */
typedef OcamlGenericInstanceCallTarget = {
	final moduleId:String;
	final typeName:String;
	final fieldName:String;
	final receiverTypeId:String;
	final receiverRepresentationId:String;
	final ownedParameterIds:Array<String>;
	final optionalParameterIndices:Array<Int>;
	final declaration:OcamlGenericValueShape;
	final instantiation:OcamlGenericValueShape;
	final argumentShapes:Array<OcamlGenericValueShape>;
	final arguments:Array<OcamlGenericValueConversion>;
	final resultShape:OcamlGenericValueShape;
	final result:OcamlGenericValueConversion;
}

/** Selects generic calls only when the receiver and every storage crossing are proved. */
final PROOF_ID = "generic-instance-storage-crossing-v3";

final PROOF_CLAIM = "One ordinary generic instance method owns the erased type parameters. Its exact instantiation fixes directional conversions. Registered nominal proofs distinguish class transport from unchanged native enum arguments. The source receiver and supplied arguments are evaluated once in order. Recorded optional slots materialize owned null inputs before invocation. Enum argument proofs do not authorize enum results or callback leaves.";

#if macro
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
		evaluationSchedule: OcamlCallPlan.evaluationSchedule(id, parameterCount(target), omittedIndices(target), false, true),
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
	final expected = OcamlCallPlan.evaluationSchedule(call.id, parameterCount(target), omittedIndices(target), false, true);
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
	for (index in 0...target.arguments.length)
		for (helper in reflaxe.ocaml.lowered.OcamlGenericCallConversion.runtimeHelpers(target.arguments[index], 'generic-call:argument:$index'))
			helpers.push(helper);
	for (index in omittedIndices(target))
		helpers.push({role: 'generic-call:omitted:$index', symbol: "HxRuntime.hx_null"});
	for (helper in reflaxe.ocaml.lowered.OcamlGenericCallConversion.runtimeHelpers(target.result, "generic-call:result"))
		helpers.push(helper);
	return helpers;
}

/** Omitted trailing slots have no source expression but still require one native argument. */
function omittedIndices(target:OcamlGenericInstanceCallTarget):Array<Int> {
	return [for (index in target.arguments.length...parameterCount(target)) index];
}

private function parameterCount(target:OcamlGenericInstanceCallTarget):Int {
	return switch (target.declaration) {
		case FunctionValue(parameters, _): parameters.length;
		case _: 0;
	}
}

#if macro
/** Resolves one final call without inferring storage from generated syntax. */
function select(expression:TypedExpr, representations:OcamlRepresentationRegistry):Null<OcamlGenericInstanceCallTarget> {
	final receiverType = switch (expression.expr) {
		case TCall({expr: TField(_, FInstance(reference, [], field))}, _) if (field.get().params.length > 0):
			final owner = reference.get();
			(owner.pack ?? []).concat([owner.name]).join(".");
		case _: return null;
	};
	final representation = representations.genericClassValue(receiverType);
	return representation == null ? null : selectWithReceiverProof(expression, representation.id, typeId -> {
		final value = representations.genericClassValue(typeId);
		return value == null ? null : value.id;
	}, typeId -> {
		final value = representations.nativeEnumValue(typeId);
		return value == null ? null : value.id;
	});
}

/** Rechecks final typed facts; the call's program revision owns the registered receiver proof. */
function representationsMatch(target:OcamlGenericInstanceCallTarget, representations:OcamlRepresentationRegistry, programRevision:String):Bool {
	final receiver = representations.genericClassValue(target.receiverTypeId);
	if (receiver == null || receiver.id != target.receiverRepresentationId || receiver.programRevision != programRevision)
		return false;
	for (proof in nominalProofs(target)) {
		final value = proof.kind == OcamlGenericNominalKind.EnumArgument ? representations.nativeEnumValue(proof.typeId) : representations.genericClassValue(proof.typeId);
		if (value == null || value.id != proof.representationId || value.programRevision != programRevision)
			return false;
	}
	return true;
}

/** Rechecks the final typed occurrence using only retained class identities. */
function matches(target:OcamlGenericInstanceCallTarget, expression:TypedExpr):Bool {
	final proofs = nominalProofs(target);
	final selected = selectWithReceiverProof(expression, target.receiverRepresentationId, typeId -> {
		for (proof in proofs)
			if (proof.kind == OcamlGenericNominalKind.ClassRecord && proof.typeId == typeId)
				return proof.representationId;
		return null;
	}, typeId -> {
		for (proof in proofs)
			if (proof.kind == OcamlGenericNominalKind.EnumArgument && proof.typeId == typeId)
				return proof.representationId;
		return null;
	});
	return selected != null && fingerprint(selected) == fingerprint(target);
}

/**
	Classifies the argument slots of a direct method call after Haxe binds omissions.

	The selector below checks supplied arguments and records omitted optional slots.
	The syntax emitter materializes each omitted slot before calling the method.
	Each slot still uses the value classifier, so optional parameters inside a
	callback remain unsupported. This does not change the ABI of function values.
**/
private function boundMethodShape(type:Type, nominalProof:String->Null<String>, enumProof:String->Null<String>):Null<OcamlGenericValueShape> {
	return switch (TypeTools.follow(type)) {
		case TFun(arguments, result):
			final parameters:Array<OcamlGenericValueShape> = [];
			for (argument in arguments) {
				final selected = boundArgumentShape(argument.t, nominalProof, enumProof);
				if (selected == null || selected == EffectOnly)
					return null;
				parameters.push(selected);
			}
			final selectedResult = genericValueShape(result, nominalProof);
			selectedResult == null ? null : FunctionValue(parameters, selectedResult);
		case _: null;
	}
}

/**
	Admits a registered enum only as an unchanged direct method input.

	This does not classify enum results or callback leaves. Those need their own
	producer evidence. Nullable, generic, foreign and renamed enum types also
	remain outside this boundary.
**/
private function boundArgumentShape(type:Type, nominalProof:String->Null<String>, enumProof:String->Null<String>):Null<OcamlGenericValueShape> {
	final ordinary = genericValueShape(type, nominalProof);
	if (ordinary != null)
		return ordinary;
	return switch (type) {
		case TEnum(reference, []):
			final declaration = reference.get();
			if (declaration.params.length != 0
				|| declaration.isExtern
				|| declaration.meta.has(":native")
				|| (declaration.pack.length > 0 && declaration.pack[0] == "ocaml"))
				return null;
			final typeId = declaration.pack.concat([declaration.name]).join(".");
			final proof = enumProof(typeId);
			proof == null ? null : NativeEnumArgument(typeId, proof);
		case TType(reference, parameters):
			final declaration = reference.get();
			boundArgumentShape(TypeTools.applyTypeParameters(declaration.type, declaration.params, parameters), nominalProof, enumProof);
		case TLazy(resolve): boundArgumentShape(resolve(), nominalProof, enumProof);
		case TMono(reference):
			final resolved = reference.get();
			resolved == null ? null : boundArgumentShape(resolved, nominalProof, enumProof);
		case _: null;
	}
}

private function selectWithReceiverProof(expression:TypedExpr, receiverProof:String, nominalProof:String->Null<String>,
		enumProof:String->Null<String>):Null<OcamlGenericInstanceCallTarget> {
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
			final declared = boundMethodShape(field.type, nominalProof, enumProof);
			final instantiated = boundMethodShape(callee.t, nominalProof, enumProof);
			final resultShape = genericValueShape(expression.t, nominalProof);
			final optional = switch (TypeTools.follow(field.type)) {
				case TFun(parameters, _): [for (index in 0...parameters.length) if (parameters[index].opt) index];
				case _: [];
			};
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
					if (parameters.length >= arguments.length && sameShape(resultShape, actualResult)):
					for (index in arguments.length...parameters.length)
						if (optional.indexOf(index) < 0 || !admitsOmittedNull(parameters[index]))
							return null;
					final shapes:Array<OcamlGenericValueShape> = [];
					final conversions:Array<OcamlGenericValueConversion> = [];
					for (index in 0...arguments.length) {
						final shape = boundArgumentShape(arguments[index].t, nominalProof, enumProof);
						if (shape == null || !argumentShapeMatches(shape, actualParameters[index]))
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
						optionalParameterIndices: optional,
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
	nominalProofs(target);
	switch ([target.declaration, target.instantiation]) {
		case [FunctionValue(parameters, result), FunctionValue(actualParameters, actualResult)]:
			if (parameters.length < target.arguments.length
				|| actualParameters.length != parameters.length
				|| target.arguments.length != target.argumentShapes.length
				|| !sameShape(actualResult, target.resultShape)
				|| !sameConversion(genericValueCrossing(result, actualResult), target.result))
				throw "reflaxe.ocaml [ocaml-generic-call:invalid-plan]: inconsistent argument or result crossing";
			var previousOptional = -1;
			for (index in target.optionalParameterIndices) {
				if (index <= previousOptional || index >= parameters.length)
					throw "reflaxe.ocaml [ocaml-generic-call:invalid-plan]: invalid optional parameter order";
				previousOptional = index;
			}
			for (index in target.arguments.length...parameters.length)
				if (target.optionalParameterIndices.indexOf(index) < 0 || !admitsOmittedNull(parameters[index]))
					throw "reflaxe.ocaml [ocaml-generic-call:invalid-plan]: omitted slot lacks optional null admission";
			for (index in 0...target.arguments.length)
				if (!argumentShapeMatches(target.argumentShapes[index], actualParameters[index])
					|| !sameConversion(genericValueCrossing(actualParameters[index], parameters[index]), target.arguments[index]))
					throw "reflaxe.ocaml [ocaml-generic-call:invalid-plan]: inconsistent argument conversion";
		case _:
			throw "reflaxe.ocaml [ocaml-generic-call:invalid-plan]: missing function shape";
	}
}

/**
	Collects exact nominal identities without widening result or callback admission.
	Selection supplies registered proofs; occurrence matching reuses only those retained facts.
	The report inspector separately checks each proof against the current program inventory.
**/
function nominalProofs(target:OcamlGenericInstanceCallTarget):Array<OcamlGenericNominalProof> {
	final proofs:Array<OcamlGenericNominalProof> = [];
	function add(kind:OcamlGenericNominalKind, typeId:String, representationId:String):Void {
		if (typeId.length == 0 || representationId.length == 0)
			throw "reflaxe.ocaml [ocaml-generic-call:invalid-plan]: missing nominal representation";
		for (proof in proofs) {
			if (proof.typeId == typeId) {
				if (proof.kind != kind || proof.representationId != representationId)
					throw "reflaxe.ocaml [ocaml-generic-call:invalid-plan]: conflicting nominal representations";
				return;
			}
		}
		proofs.push({kind: kind, typeId: typeId, representationId: representationId});
	}
	function visit(shape:OcamlGenericValueShape, enumArgument:Bool = false):Void {
		switch (shape) {
			case DynamicValue:
				throw "reflaxe.ocaml [ocaml-generic-call:invalid-plan]: explicit Dynamic belongs to the ordinary callable boundary, not this generic declaration proof";
			case NominalValue(typeId, representationId, _):
				add(OcamlGenericNominalKind.ClassRecord, typeId, representationId);
			case NativeEnumArgument(typeId, representationId):
				if (!enumArgument)
					throw "reflaxe.ocaml [ocaml-generic-call:invalid-plan]: enum proof is restricted to direct method arguments";
				add(OcamlGenericNominalKind.EnumArgument, typeId, representationId);
			case FunctionValue(arguments, result):
				for (argument in arguments)
					visit(argument);
				visit(result);
			case ArrayValue(element):
				visit(element);
			case _:
		}
	}
	function visitMethod(shape:OcamlGenericValueShape):Void {
		switch (shape) {
			case FunctionValue(arguments, result):
				for (argument in arguments)
					visit(argument, true);
				visit(result);
			case _:
				visit(shape);
		}
	}
	visitMethod(target.declaration);
	visitMethod(target.instantiation);
	for (shape in target.argumentShapes)
		visit(shape, true);
	visit(target.resultShape);
	return proofs;
}

function fingerprint(target:OcamlGenericInstanceCallTarget):String {
	return [
		target.moduleId,
		target.typeName,
		target.fieldName,
		target.receiverTypeId,
		target.receiverRepresentationId,
		target.ownedParameterIds.join(","),
		target.optionalParameterIndices.join(","),
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
		optionalParameterIndices: target.optionalParameterIndices.copy(),
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

/** A non-null record can enter the nullable parameter for that exact registered class. */
private function argumentShapeMatches(source:OcamlGenericValueShape, destination:OcamlGenericValueShape):Bool {
	if (sameShape(source, destination))
		return true;
	return switch ([source, destination]) {
		case [
			NominalValue(sourceId, sourceProof, false),
			NominalValue(destinationId, destinationProof, true)
		]: sourceId == destinationId && sourceProof == destinationProof;
		case _: false;
	}
}

/** These method slots use the existing Haxe null sentinel before default normalization. */
private function admitsOmittedNull(shape:OcamlGenericValueShape):Bool {
	return switch (shape) {
		case Integer, Boolean, Text(_), NullableInteger, NullableBoolean, NominalValue(_, _, _): true;
		case _: false;
	}
}

private function sameConversion(left:Null<OcamlGenericValueConversion>, right:OcamlGenericValueConversion):Bool {
	return left != null && Std.string(left) == Std.string(right);
}
