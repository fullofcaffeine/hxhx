package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.ds.ObjectMap;
import haxe.macro.Type;
import haxe.macro.Type.ClassField;
import haxe.macro.Type.ClassType;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapInterfaceCallDecision;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapInterfaceContract;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapInterfaceConversionDecision;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapInterfaceConversionRole;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapInterfaceMethodDecision;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapInterfaceSourceKind;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapCallContract;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapKeyKind;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapOperation;
import reflaxe.ocaml.lowered.OcamlStandardMapCarrierModel.OcamlStandardMapCarrierContract;
import reflaxe.ocaml.lowered.OcamlStandardMapCarrierModel.OcamlStandardMapCarrierKind;

typedef OcamlIMapInterfaceMethodMaterialization = {
	final decision:OcamlIMapInterfaceMethodDecision;
	final owner:ClassType;
	final field:ClassField;
	final operation:OcamlStandardIMapOperation;
	final argumentTypes:Array<Type>;
	final resultType:Type;
}

/**
	Request-local host objects needed only while materializing one sealed conversion.

	The public decision above contains only stable plain values for reports and
	validation. These compiler objects never leave the active request and are not
	part of any cross-request cache payload.
**/
typedef OcamlIMapInterfaceConversionMaterialization = {
	final decision:OcamlIMapInterfaceConversionDecision;
	final keyType:Type;
	final valueType:Type;
	final sourceClass:ClassType;
	final methods:Array<OcamlIMapInterfaceMethodMaterialization>;
}

/**
	Immutable conversion and call inventory for one final typed function body.

	Syntax looks up the exact typed expression object from the active compiler
	request. A missing or conflicting decision is an internal compiler error; the
	printer must not infer an adapter from a field name or key type.
**/
class OcamlIMapInterfacePlan {
	public static inline final MODEL = OcamlIMapInterfaceContract.MODEL;
	public static inline final CONVERSION_PROOF_ID = OcamlIMapInterfaceContract.CONVERSION_PROOF_ID;
	public static inline final CALL_PROOF_ID = OcamlIMapInterfaceContract.CALL_PROOF_ID;
	public static inline final TARGET_CARRIER_ID = OcamlIMapInterfaceContract.TARGET_CARRIER_ID;
	public static inline final CONVERSION_PROOF_CLAIM = OcamlIMapInterfaceContract.CONVERSION_PROOF_CLAIM;
	public static inline final CALL_PROOF_CLAIM = OcamlIMapInterfaceContract.CALL_PROOF_CLAIM;

	final binding:OcamlFunctionPlanBinding;
	final conversionsByExpression:ObjectMap<TypedExpr, OcamlIMapInterfaceConversionMaterialization>;
	final callsByExpression:ObjectMap<TypedExpr, OcamlIMapInterfaceCallDecision>;
	final orderedConversions:Array<OcamlIMapInterfaceConversionDecision>;
	final orderedCalls:Array<OcamlIMapInterfaceCallDecision>;

	public final revision:String;

	public function new(binding:OcamlFunctionPlanBinding, conversionsByExpression:ObjectMap<TypedExpr, OcamlIMapInterfaceConversionMaterialization>,
			callsByExpression:ObjectMap<TypedExpr, OcamlIMapInterfaceCallDecision>) {
		this.binding = copyBinding(binding);
		this.conversionsByExpression = conversionsByExpression;
		this.callsByExpression = callsByExpression;
		orderedConversions = [
			for (materialization in conversionsByExpression)
				copyConversion(materialization.decision)
		];
		orderedConversions.sort((left, right) -> Reflect.compare(left.id, right.id));
		orderedCalls = [for (decision in callsByExpression) copyCall(decision)];
		orderedCalls.sort((left, right) -> Reflect.compare(left.id, right.id));
		for (decision in orderedConversions)
			requireConversionDecision(decision);
		for (decision in orderedCalls)
			requireCallDecision(decision);
		revision = "sha256:" + Sha256.encode(orderedConversions.map(conversionFingerprint).concat(orderedCalls.map(callFingerprint)).join("\n"));
	}

	/** Returns the sealed materialization for one exact conversion occurrence. */
	public function requireConversion(expression:TypedExpr, targetType:Type):OcamlIMapInterfaceConversionMaterialization {
		final materialization = conversionsByExpression.get(expression);
		if (materialization == null)
			throw 'reflaxe.ocaml [ocaml-imap-interface:missing-conversion]: ${sourceKey(expression.pos)} has no sealed IMap conversion';
		final decision = materialization.decision;
		if (decision.sourceSemanticTypeId != semanticTypeId(OcamlIMapInterfacePlanner.conversionSourceType(expression))
			|| decision.targetSemanticTypeId != semanticTypeId(targetType)
			|| !sameBinding(decision.functionId, decision.programRevision, decision.bodyRevision, decision.pipelineRevision, binding)) {
			throw 'reflaxe.ocaml [ocaml-imap-interface:stale-conversion]: conversion "${decision.id}" disagrees with the final typed occurrence or function revision';
		}
		requireConversionDecision(decision);
		return materialization;
	}

	/** Returns the sealed interface dispatch for one exact call occurrence. */
	public function callFor(expression:TypedExpr):Null<OcamlIMapInterfaceCallDecision> {
		final decision = callsByExpression.get(expression);
		if (decision == null)
			return null;
		if (!sameBinding(decision.functionId, decision.programRevision, decision.bodyRevision, decision.pipelineRevision, binding))
			throw 'reflaxe.ocaml [ocaml-imap-interface:stale-call]: call "${decision.id}" belongs to another function revision';
		requireCallDecision(decision);
		return copyCall(decision);
	}

	/** Returns stable conversion records for reports and inspection. */
	public function conversions():Array<OcamlIMapInterfaceConversionDecision> {
		return orderedConversions.map(copyConversion);
	}

	/** Returns stable call records for reports and inspection. */
	public function calls():Array<OcamlIMapInterfaceCallDecision> {
		return orderedCalls.map(copyCall);
	}

	/** Proves that this plan belongs to the exact function being sealed or emitted. */
	public function requirePlanBinding(expected:OcamlFunctionPlanBinding):Void {
		if (!sameBinding(binding.functionId, binding.programRevision, binding.bodyRevision, binding.pipelineRevision, expected))
			throw 'reflaxe.ocaml [ocaml-imap-interface:stale-plan]: IMap interface plan belongs to another function revision';
	}

	/** Rejects a malformed or internally conflicting conversion record. */
	public static function requireConversionDecision(decision:OcamlIMapInterfaceConversionDecision):Void {
		OcamlIMapInterfaceContract.requireConversion(decision);
	}

	/** Rejects a malformed interface-dispatch record. */
	public static function requireCallDecision(decision:OcamlIMapInterfaceCallDecision):Void {
		OcamlIMapInterfaceContract.requireCall(decision);
	}

	public static final REQUIRED_METHODS = OcamlIMapInterfaceContract.REQUIRED_METHODS;

	/** Stable runtime-requirement identities owned by one conversion occurrence. */
	public static function runtimeRequirementIds(decision:OcamlIMapInterfaceConversionDecision):Array<String> {
		return OcamlIMapInterfaceContract.runtimeRequirementIds(decision);
	}

	static function copyBinding(binding:OcamlFunctionPlanBinding):OcamlFunctionPlanBinding {
		return {
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision
		};
	}

	static function sameBinding(functionId:String, programRevision:String, bodyRevision:String, pipelineRevision:String,
			binding:OcamlFunctionPlanBinding):Bool {
		return functionId == binding.functionId
			&& programRevision == binding.programRevision
			&& bodyRevision == binding.bodyRevision
			&& pipelineRevision == binding.pipelineRevision;
	}

	static function sourceKey(position:haxe.macro.Expr.Position):String {
		final source = OcamlLoweredOrigin.sourceSpan(position);
		return '${source.file}:${source.min}:${source.max}';
	}

	static function semanticTypeId(type:Type):String {
		return TypeTools.toString(type);
	}

	static function conversionFingerprint(decision:OcamlIMapInterfaceConversionDecision):String {
		return [
			decision.id,
			decision.source.file,
			Std.string(decision.source.min),
			Std.string(decision.source.max),
			(decision.role : String),
			Std.string(decision.roleIndex),
			(decision.sourceKind : String),
			decision.sourceSemanticTypeId,
			decision.sourceCarrierTypeId,
			decision.targetSemanticTypeId,
			decision.targetCarrierTypeId,
			decision.keySemanticTypeId,
			decision.valueSemanticTypeId,
			decision.standardKeyKind == null ? "" : (decision.standardKeyKind : String),
			decision.keyStringifier == null ? "" : (decision.keyStringifier : String),
			decision.valueStringifier == null ? "" : (decision.valueStringifier : String),
			decision.methods.map(method -> [
				method.name,
				method.sourceOwnerModuleId,
				method.sourceOwnerTypeName,
				method.argumentSemanticTypeIds.join(","),
				method.resultSemanticTypeId
			].join(":")).join(","),
			decision.runtimeCapabilities.join(","),
			decision.proofId,
			decision.functionId,
			decision.programRevision,
			decision.bodyRevision,
			decision.pipelineRevision
		].join("|");
	}

	static function callFingerprint(decision:OcamlIMapInterfaceCallDecision):String {
		return [
			decision.id,
			decision.source.file,
			Std.string(decision.source.min),
			Std.string(decision.source.max),
			(decision.operation : String),
			decision.receiverSemanticTypeId,
			decision.receiverCarrierTypeId,
			decision.keySemanticTypeId,
			decision.valueSemanticTypeId,
			decision.argumentSemanticTypeIds.join(","),
			decision.resultSemanticTypeId,
			decision.proofId,
			decision.functionId,
			decision.programRevision,
			decision.bodyRevision,
			decision.pipelineRevision
		].join("|");
	}

	static function copyMethod(method:OcamlIMapInterfaceMethodDecision):OcamlIMapInterfaceMethodDecision {
		return {
			name: method.name,
			sourceOwnerModuleId: method.sourceOwnerModuleId,
			sourceOwnerTypeName: method.sourceOwnerTypeName,
			argumentSemanticTypeIds: method.argumentSemanticTypeIds.copy(),
			resultSemanticTypeId: method.resultSemanticTypeId
		};
	}

	static function copyConversion(decision:OcamlIMapInterfaceConversionDecision):OcamlIMapInterfaceConversionDecision {
		return {
			id: decision.id,
			source: {file: decision.source.file, min: decision.source.min, max: decision.source.max},
			role: decision.role,
			roleIndex: decision.roleIndex,
			sourceKind: decision.sourceKind,
			sourceSemanticTypeId: decision.sourceSemanticTypeId,
			sourceCarrierTypeId: decision.sourceCarrierTypeId,
			targetSemanticTypeId: decision.targetSemanticTypeId,
			targetCarrierTypeId: decision.targetCarrierTypeId,
			keySemanticTypeId: decision.keySemanticTypeId,
			valueSemanticTypeId: decision.valueSemanticTypeId,
			standardKeyKind: decision.standardKeyKind,
			keyStringifier: decision.keyStringifier,
			valueStringifier: decision.valueStringifier,
			methods: decision.methods.map(copyMethod),
			runtimeCapabilities: decision.runtimeCapabilities.copy(),
			proofId: decision.proofId,
			proofClaim: decision.proofClaim,
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
	}

	static function copyCall(decision:OcamlIMapInterfaceCallDecision):OcamlIMapInterfaceCallDecision {
		return {
			id: decision.id,
			source: {file: decision.source.file, min: decision.source.min, max: decision.source.max},
			operation: decision.operation,
			receiverSemanticTypeId: decision.receiverSemanticTypeId,
			receiverCarrierTypeId: decision.receiverCarrierTypeId,
			keySemanticTypeId: decision.keySemanticTypeId,
			valueSemanticTypeId: decision.valueSemanticTypeId,
			argumentSemanticTypeIds: decision.argumentSemanticTypeIds.copy(),
			resultSemanticTypeId: decision.resultSemanticTypeId,
			proofId: decision.proofId,
			proofClaim: decision.proofClaim,
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
	}
}

/** Selects every admitted `IMap` conversion and dispatch from one final body. */
class OcamlIMapInterfacePlanner {
	final context:CompilationContext;
	final binding:OcamlFunctionPlanBinding;

	public function new(context:CompilationContext, binding:OcamlFunctionPlanBinding) {
		this.context = context;
		this.binding = binding;
	}

	/**
		Returns the runtime source type of one value crossing an `IMap` boundary.

		Haxe can type `new StringMap()` as the expected `IMap<String, V>` at a
		field or argument boundary. The typed constructor node still records that
		the runtime object is a `StringMap`; preserving that fact is what lets the
		planner select the standard adapter instead of accepting an unconverted
		interface value. Parentheses, metadata, and explicit casts do not change
		the constructed runtime class.
	**/
	public static function conversionSourceType(expression:TypedExpr):Type {
		return switch (expression.expr) {
			case TNew(classRef, parameters, _):
				TInst(classRef, parameters);
			case TParenthesis(inner), TMeta(_, inner), TCast(inner, _):
				conversionSourceType(inner);
			case _:
				expression.t;
		};
	}

	/** Plans one function while leaving nested functions to their own seals. */
	public function plan(expression:TypedExpr, functionResultType:Null<Type>):OcamlIMapInterfacePlan {
		final conversions:ObjectMap<TypedExpr, OcamlIMapInterfaceConversionMaterialization> = new ObjectMap();
		final calls:ObjectMap<TypedExpr, OcamlIMapInterfaceCallDecision> = new ObjectMap();

		function registerConversion(targetType:Type, value:TypedExpr, role:OcamlIMapInterfaceConversionRole, roleIndex:Int):Void {
			final selected = selectConversion(targetType, value, role, roleIndex);
			if (selected == null)
				return;
			final existing = conversions.get(value);
			if (existing != null) {
				if (haxe.Json.stringify(existing.decision) != haxe.Json.stringify(selected.decision))
					throw 'reflaxe.ocaml [ocaml-imap-interface:conflicting-conversion]: ${sourceKey(value)} selects two different IMap conversions';
				return;
			}
			conversions.set(value, selected);
		}

		function visit(current:TypedExpr):Void {
			switch (current.expr) {
				case TFunction(_):
					return;
				case TCall(callee, arguments):
					final call = selectCall(current);
					if (call != null)
						calls.set(current, call);
					switch (TypeTools.follow(callee.t)) {
						case TFun(parameters, _):
							for (index in 0...arguments.length) {
								if (index < parameters.length)
									registerConversion(parameters[index].t, arguments[index], OcamlIMapInterfaceConversionRole.CallArgument, index);
							}
						case _:
					}
				case TNew(classRef, _, arguments):
					final constructor = classRef.get().constructor;
					if (constructor != null) {
						switch (TypeTools.follow(constructor.get().type)) {
							case TFun(parameters, _):
								for (index in 0...arguments.length) {
									if (index < parameters.length)
										registerConversion(parameters[index].t, arguments[index], OcamlIMapInterfaceConversionRole.CallArgument, index);
								}
							case _:
						}
					}
				case TReturn(value) if (value != null && functionResultType != null):
					registerConversion(functionResultType, value, OcamlIMapInterfaceConversionRole.ReturnValue, -1);
				case TVar(variable, initializer) if (initializer != null):
					registerConversion(variable.t, initializer, OcamlIMapInterfaceConversionRole.LocalInitializer, variable.id);
				case TBinop(OpAssign, left, right):
					registerConversion(left.t, right, OcamlIMapInterfaceConversionRole.Assignment, -1);
				case _:
			}
			TypedExprTools.iter(current, visit);
		}

		visit(expression);
		return new OcamlIMapInterfacePlan(binding, conversions, calls);
	}

	function selectCall(expression:TypedExpr):Null<OcamlIMapInterfaceCallDecision> {
		return switch (expression.expr) {
			case TCall({expr: TField(receiver, FInstance(classRef, parameters, fieldRef))}, arguments)
				if (OcamlStandardIMapCallContract.isIMapClass(classRef.get()) && parameters.length == 2):
				final operation = OcamlStandardIMapCallContract.operationFor(fieldRef.get().name, arguments.length);
				if (operation == null) {
					null;
				} else {
					final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
					final receiverSemanticTypeId = semanticTypeId(receiver.t);
					final fingerprint = [
						binding.functionId,
						binding.programRevision,
						binding.bodyRevision,
						binding.pipelineRevision,
						'${source.file}:${source.min}:${source.max}',
						(operation : String),
						receiverSemanticTypeId
					].join("|");
					{
						id: "imap-interface-call:" + Sha256.encode(fingerprint).substr(0, 24),
						source: source,
						operation: operation,
						receiverSemanticTypeId: receiverSemanticTypeId,
						receiverCarrierTypeId: OcamlIMapInterfacePlan.TARGET_CARRIER_ID,
						keySemanticTypeId: semanticTypeId(parameters[0]),
						valueSemanticTypeId: semanticTypeId(parameters[1]),
						argumentSemanticTypeIds: arguments.map(argument -> semanticTypeId(argument.t)),
						resultSemanticTypeId: semanticTypeId(expression.t),
						proofId: OcamlIMapInterfacePlan.CALL_PROOF_ID,
						proofClaim: OcamlIMapInterfacePlan.CALL_PROOF_CLAIM,
						functionId: binding.functionId,
						programRevision: binding.programRevision,
						bodyRevision: binding.bodyRevision,
						pipelineRevision: binding.pipelineRevision
					};
				}
			case _:
				null;
		};
	}

	function selectConversion(targetType:Type, value:TypedExpr, role:OcamlIMapInterfaceConversionRole,
			roleIndex:Int):Null<OcamlIMapInterfaceConversionMaterialization> {
		final target = exactIMap(targetType);
		final sourceType = conversionSourceType(value);
		if (target == null || exactIMap(sourceType) != null)
			return null;
		return switch (TypeTools.follow(sourceType)) {
			case TInst(classRef, parameters):
				final sourceClass = classRef.get();
				final standard = standardMapTypes(sourceClass, parameters);
				if (standard != null) {
					if (!sameType(standard.key, target.key) || !sameType(standard.value, target.value))
						return null;
					standardConversion(value, sourceType, role, roleIndex, sourceClass, target.key, target.value, standard.kind);
				} else {
					final implemented = implementedIMap(sourceClass);
					if (implemented == null || !sameType(implemented.key, target.key) || !sameType(implemented.value, target.value))
						return null;
					userConversion(value, sourceType, role, roleIndex, sourceClass, target.key, target.value);
				}
			case _:
				null;
		};
	}

	function standardConversion(value:TypedExpr, sourceType:Type, role:OcamlIMapInterfaceConversionRole, roleIndex:Int, sourceClass:ClassType, keyType:Type,
			valueType:Type, kind:OcamlStandardMapCarrierKind):OcamlIMapInterfaceConversionMaterialization {
		final sourceKind:OcamlIMapInterfaceSourceKind = switch (kind) {
			case StringKeys: OcamlIMapInterfaceSourceKind.StandardStringMap;
			case IntKeys: OcamlIMapInterfaceSourceKind.StandardIntMap;
			case ObjectIdentityKeys: OcamlIMapInterfaceSourceKind.StandardObjectMap;
		};
		final keyKind:OcamlStandardIMapKeyKind = switch (kind) {
			case StringKeys: OcamlStandardIMapKeyKind.StringKey;
			case IntKeys: OcamlStandardIMapKeyKind.IntKey;
			case ObjectIdentityKeys: OcamlStandardIMapKeyKind.ObjectIdentityKey;
		};
		final keySemanticTypeId = semanticTypeId(keyType);
		final valueSemanticTypeId = semanticTypeId(valueType);
		final decision = conversionDecision(value, sourceType, role, roleIndex, sourceKind, sourceClass, OcamlStandardIMapCallContract.carrierId(keyKind),
			keyType, valueType, keyKind, [], OcamlStandardIMapCallContract.adapterRuntimeCapabilities(keySemanticTypeId, valueSemanticTypeId));
		return {
			decision: decision,
			keyType: keyType,
			valueType: valueType,
			sourceClass: sourceClass,
			methods: []
		};
	}

	function userConversion(value:TypedExpr, sourceType:Type, role:OcamlIMapInterfaceConversionRole, roleIndex:Int, sourceClass:ClassType, keyType:Type,
			valueType:Type):OcamlIMapInterfaceConversionMaterialization {
		if (sourceClass.params.length > 0)
			throw 'reflaxe.ocaml [ocaml-imap-interface:unsupported-user-implementation]: generic user IMap implementation ${fullClassName(sourceClass)} needs an explicit specialization contract';
		final methods:Array<OcamlIMapInterfaceMethodMaterialization> = [];
		for (name in OcamlIMapInterfacePlan.REQUIRED_METHODS) {
			final found = findMethod(sourceClass, name);
			if (found == null)
				throw 'reflaxe.ocaml [ocaml-imap-interface:missing-user-method]: ${fullClassName(sourceClass)} has no concrete "$name" implementation';
			final signature = switch (TypeTools.follow(found.field.type)) {
				case TFun(arguments, result): {
						argumentTypes: arguments.map(argument -> argument.t),
						argumentSemanticTypeIds: arguments.map(argument -> semanticTypeId(argument.t)),
						resultType: result,
						resultSemanticTypeId: semanticTypeId(result)
					};
				case _:
					throw 'reflaxe.ocaml [ocaml-imap-interface:invalid-user-method]: ${fullClassName(found.owner)}.$name is not a method';
			};
			final operation = OcamlStandardIMapCallContract.operationFor(name, signature.argumentTypes.length);
			if (operation == null)
				throw 'reflaxe.ocaml [ocaml-imap-interface:invalid-user-method]: ${fullClassName(found.owner)}.$name has a signature outside the IMap contract';
			methods.push({
				decision: {
					name: name,
					sourceOwnerModuleId: found.owner.module,
					sourceOwnerTypeName: found.owner.name,
					argumentSemanticTypeIds: signature.argumentSemanticTypeIds,
					resultSemanticTypeId: signature.resultSemanticTypeId
				},
				owner: found.owner,
				field: found.field,
				operation: operation,
				argumentTypes: signature.argumentTypes,
				resultType: signature.resultType
			});
		}
		final sourceCarrier = context.ocamlModuleNameForModuleId(sourceClass.module)
			+ "."
			+ context.scopedInstanceTypeName(sourceClass.module, sourceClass.name);
		final decision = conversionDecision(value, sourceType, role, roleIndex, OcamlIMapInterfaceSourceKind.UserImplementation, sourceClass, sourceCarrier,
			keyType, valueType, null, methods.map(method -> method.decision), []);
		return {
			decision: decision,
			keyType: keyType,
			valueType: valueType,
			sourceClass: sourceClass,
			methods: methods
		};
	}

	function conversionDecision(value:TypedExpr, sourceType:Type, role:OcamlIMapInterfaceConversionRole, roleIndex:Int,
			sourceKind:OcamlIMapInterfaceSourceKind, sourceClass:ClassType, sourceCarrierTypeId:String, keyType:Type, valueType:Type,
			standardKeyKind:Null<OcamlStandardIMapKeyKind>, methods:Array<OcamlIMapInterfaceMethodDecision>,
			runtimeCapabilities:Array<String>):OcamlIMapInterfaceConversionDecision {
		final source = OcamlLoweredOrigin.sourceSpan(value.pos);
		final keySemanticTypeId = semanticTypeId(keyType);
		final valueSemanticTypeId = semanticTypeId(valueType);
		final fingerprint = [
			binding.functionId,
			binding.programRevision,
			binding.bodyRevision,
			binding.pipelineRevision,
			'${source.file}:${source.min}:${source.max}',
			(role : String),
			Std.string(roleIndex),
			(sourceKind : String),
			semanticTypeId(sourceType),
			keySemanticTypeId,
			valueSemanticTypeId
		].join("|");
		return {
			id: "imap-interface-conversion:" + Sha256.encode(fingerprint).substr(0, 24),
			source: source,
			role: role,
			roleIndex: roleIndex,
			sourceKind: sourceKind,
			sourceSemanticTypeId: semanticTypeId(sourceType),
			sourceCarrierTypeId: sourceCarrierTypeId,
			targetSemanticTypeId: 'haxe.IMap<$keySemanticTypeId, $valueSemanticTypeId>',
			targetCarrierTypeId: OcamlIMapInterfacePlan.TARGET_CARRIER_ID,
			keySemanticTypeId: keySemanticTypeId,
			valueSemanticTypeId: valueSemanticTypeId,
			standardKeyKind: standardKeyKind,
			keyStringifier: standardKeyKind == null ? null : OcamlStandardIMapCallContract.stringifierForSemanticTypeId(keySemanticTypeId),
			valueStringifier: standardKeyKind == null ? null : OcamlStandardIMapCallContract.stringifierForSemanticTypeId(valueSemanticTypeId),
			methods: methods,
			runtimeCapabilities: runtimeCapabilities,
			proofId: OcamlIMapInterfacePlan.CONVERSION_PROOF_ID,
			proofClaim: OcamlIMapInterfacePlan.CONVERSION_PROOF_CLAIM,
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision
		};
	}

	static function exactIMap(type:Type):Null<{key:Type, value:Type}> {
		return switch (TypeTools.follow(type)) {
			case TInst(classRef, parameters) if (OcamlStandardIMapCallContract.isIMapClass(classRef.get()) && parameters.length == 2):
				{key: parameters[0], value: parameters[1]};
			case _:
				null;
		};
	}

	static function standardMapTypes(classType:ClassType, parameters:Array<Type>):Null<{kind:OcamlStandardMapCarrierKind, key:Type, value:Type}> {
		return switch (OcamlStandardMapCarrierContract.kindForClass(classType)) {
			case StringKeys if (parameters.length == 1):
				{kind: OcamlStandardMapCarrierKind.StringKeys, key: ContextType.stringType(), value: parameters[0]};
			case IntKeys if (parameters.length == 1):
				{kind: OcamlStandardMapCarrierKind.IntKeys, key: ContextType.intType(), value: parameters[0]};
			case ObjectIdentityKeys if (parameters.length == 2):
				{kind: OcamlStandardMapCarrierKind.ObjectIdentityKeys, key: parameters[0], value: parameters[1]};
			case _:
				null;
		};
	}

	static function implementedIMap(classType:ClassType):Null<{key:Type, value:Type}> {
		for (edge in classType.interfaces) {
			final interfaceType = edge.t.get();
			if (OcamlStandardIMapCallContract.isIMapClass(interfaceType) && edge.params.length == 2)
				return {key: edge.params[0], value: edge.params[1]};
			final inherited = implementedIMap(interfaceType);
			if (inherited != null)
				return inherited;
		}
		return classType.superClass == null ? null : implementedIMap(classType.superClass.t.get());
	}

	static function findMethod(classType:ClassType, name:String):Null<{owner:ClassType, field:ClassField}> {
		for (field in classType.fields.get()) {
			if (field.name == name) {
				return switch (field.kind) {
					case FMethod(_): {owner: classType, field: field};
					case _: null;
				};
			}
		}
		return classType.superClass == null ? null : findMethod(classType.superClass.t.get(), name);
	}

	static function sameType(left:Type, right:Type):Bool {
		return semanticTypeId(left) == semanticTypeId(right);
	}

	static function semanticTypeId(type:Type):String {
		return TypeTools.toString(type);
	}

	static function fullClassName(classType:ClassType):String {
		return (classType.pack ?? []).concat([classType.name]).join(".");
	}

	static function sourceKey(expression:TypedExpr):String {
		final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
		return '${source.file}:${source.min}:${source.max}';
	}
}

/** Resolves core primitive `Type` values without keeping compiler globals in decisions. */
private class ContextType {
	public static function stringType():Type {
		return haxe.macro.Context.getType("String");
	}

	public static function intType():Type {
		return haxe.macro.Context.getType("Int");
	}
}
#end
