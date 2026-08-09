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
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapInterfaceSourceSpan;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapInterfaceSourceKind;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapStorageAliasDecision;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapStorageAliasNullPolicy;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapStorageAliasUseDecision;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapCallContract;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapKeyKind;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapOperation;
import reflaxe.ocaml.lowered.OcamlStandardMapCarrierModel.OcamlStandardMapCarrierContract;
import reflaxe.ocaml.lowered.OcamlStandardMapCarrierModel.OcamlStandardMapCarrierKind;
import reflaxe.ocaml.lowered.OcamlStaticStoragePlan;

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
	final sourceClass:Null<ClassType>;
	final operations:Array<OcamlStandardIMapOperation>;
	final methods:Array<OcamlIMapInterfaceMethodMaterialization>;
}

private typedef PendingStandardMapStorageAlias = {
	final localId:Int;
	final targetType:Type;
	final initializer:TypedExpr;
	final keyType:Type;
	final valueType:Type;
	final kind:OcamlStandardMapCarrierKind;
	final sourceCarrierTypeId:String;
	final nullPolicy:OcamlIMapStorageAliasNullPolicy;
	final uses:Array<OcamlIMapStorageAliasUseDecision>;
	final useExpressions:Array<TypedExpr>;
	var invalid:Bool;
}

private typedef PlannedStandardMapStorageAliases = {
	final initializers:ObjectMap<TypedExpr, OcamlIMapStorageAliasDecision>;
	final uses:ObjectMap<TypedExpr, OcamlIMapStorageAliasDecision>;
}

private typedef NativeStandardMapStorageUse = {
	final localId:Int;
	final storageExpression:TypedExpr;
	final boundaryExpression:TypedExpr;
	final operation:String;
	final source:OcamlIMapInterfaceSourceSpan;
	final kind:OcamlStandardMapCarrierKind;
	final keyType:Type;
	final valueType:Type;
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
	public static inline final STORAGE_ALIAS_PROOF_ID = OcamlIMapInterfaceContract.STORAGE_ALIAS_PROOF_ID;
	public static inline final TARGET_CARRIER_ID = OcamlIMapInterfaceContract.TARGET_CARRIER_ID;
	public static inline final CONVERSION_PROOF_CLAIM = OcamlIMapInterfaceContract.CONVERSION_PROOF_CLAIM;
	public static inline final CALL_PROOF_CLAIM = OcamlIMapInterfaceContract.CALL_PROOF_CLAIM;
	public static inline final STORAGE_ALIAS_PROOF_CLAIM = OcamlIMapInterfaceContract.STORAGE_ALIAS_PROOF_CLAIM;

	final binding:OcamlFunctionPlanBinding;
	final conversionsByExpression:ObjectMap<TypedExpr, OcamlIMapInterfaceConversionMaterialization>;
	final callsByExpression:ObjectMap<TypedExpr, OcamlIMapInterfaceCallDecision>;
	final storageAliasesByExpression:ObjectMap<TypedExpr, OcamlIMapStorageAliasDecision>;
	final storageAliasUsesByExpression:ObjectMap<TypedExpr, OcamlIMapStorageAliasDecision>;
	final storageAliasUsesByLocalOccurrence:Map<String, OcamlIMapStorageAliasDecision>;
	final orderedConversions:Array<OcamlIMapInterfaceConversionDecision>;
	final orderedCalls:Array<OcamlIMapInterfaceCallDecision>;
	final orderedStorageAliases:Array<OcamlIMapStorageAliasDecision>;

	public final revision:String;

	public function new(binding:OcamlFunctionPlanBinding, conversionsByExpression:ObjectMap<TypedExpr, OcamlIMapInterfaceConversionMaterialization>,
			callsByExpression:ObjectMap<TypedExpr, OcamlIMapInterfaceCallDecision>,
			?storageAliasesByExpression:ObjectMap<TypedExpr, OcamlIMapStorageAliasDecision>,
			?storageAliasUsesByExpression:ObjectMap<TypedExpr, OcamlIMapStorageAliasDecision>) {
		this.binding = copyBinding(binding);
		this.conversionsByExpression = conversionsByExpression;
		this.callsByExpression = callsByExpression;
		this.storageAliasesByExpression = storageAliasesByExpression ?? new ObjectMap();
		this.storageAliasUsesByExpression = storageAliasUsesByExpression ?? new ObjectMap();
		this.storageAliasUsesByLocalOccurrence = [];
		for (expression in this.storageAliasUsesByExpression.keys()) {
			final decision = this.storageAliasUsesByExpression.get(expression);
			if (decision == null)
				continue;
			switch (expression.expr) {
				case TLocal(local):
					final key = localUseKey(local.id, expression.pos);
					final existing = this.storageAliasUsesByLocalOccurrence.get(key);
					if (existing != null && existing.id != decision.id)
						throw 'reflaxe.ocaml [ocaml-imap-interface:conflicting-storage-alias]: local occurrence "$key" belongs to two aliases';
					this.storageAliasUsesByLocalOccurrence.set(key, decision);
				case _:
			}
		}
		orderedConversions = [
			for (materialization in conversionsByExpression)
				copyConversion(materialization.decision)
		];
		orderedConversions.sort((left, right) -> Reflect.compare(left.id, right.id));
		orderedCalls = [for (decision in callsByExpression) copyCall(decision)];
		orderedCalls.sort((left, right) -> Reflect.compare(left.id, right.id));
		orderedStorageAliases = [for (decision in this.storageAliasesByExpression) copyStorageAlias(decision)];
		orderedStorageAliases.sort((left, right) -> Reflect.compare(left.id, right.id));
		for (decision in orderedConversions)
			requireConversionDecision(decision);
		for (decision in orderedCalls)
			requireCallDecision(decision);
		for (decision in orderedStorageAliases)
			requireStorageAliasDecision(decision);
		revision = "sha256:"
			+ Sha256.encode(orderedConversions.map(conversionFingerprint)
				.concat(orderedCalls.map(callFingerprint))
				.concat(orderedStorageAliases.map(storageAliasFingerprint))
				.join("\n"));
	}

	/** Returns the sealed materialization for one exact conversion occurrence. */
	public function requireConversion(expression:TypedExpr, targetType:Type):OcamlIMapInterfaceConversionMaterialization {
		final materialization = conversionsByExpression.get(expression);
		if (materialization == null)
			throw 'reflaxe.ocaml [ocaml-imap-interface:missing-conversion]: ${sourceKey(expression.pos)} has no sealed conversion from ${semanticTypeId(OcamlIMapInterfacePlanner.conversionSourceType(expression))} (typed occurrence ${semanticTypeId(expression.t)}) to ${semanticTypeId(targetType)}';
		final decision = materialization.decision;
		if (decision.sourceSemanticTypeId != semanticTypeId(OcamlIMapInterfacePlanner.conversionSourceType(expression))
			|| decision.targetSemanticTypeId != semanticTypeId(targetType)
			|| !sameBinding(decision.functionId, decision.programRevision, decision.bodyRevision, decision.pipelineRevision, binding)) {
			throw 'reflaxe.ocaml [ocaml-imap-interface:stale-conversion]: conversion "${decision.id}" disagrees with the final typed occurrence or function revision';
		}
		requireConversionDecision(decision);
		final retainedMethodNames = decision.methods.map(method -> method.name).join(",");
		final materializedOperationNames = materialization.operations.map(operation -> OcamlStandardIMapCallContract.sourceFieldName(operation)).join(",");
		final materializedMethodNames = materialization.methods.map(method -> method.decision.name).join(",");
		if (materializedOperationNames != retainedMethodNames
			|| (decision.sourceKind == OcamlIMapInterfaceSourceKind.UserImplementation && materializedMethodNames != retainedMethodNames)
			|| (decision.sourceKind != OcamlIMapInterfaceSourceKind.UserImplementation && materialization.methods.length != 0)) {
			throw 'reflaxe.ocaml [ocaml-imap-interface:stale-conversion]: conversion "${decision.id}" has a request-local adapter surface that disagrees with its sealed report decision';
		}
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

	/** Returns the sealed raw-storage alias for one exact local initializer. */
	public function storageAliasFor(expression:TypedExpr, targetType:Type):Null<OcamlIMapStorageAliasDecision> {
		final decision = storageAliasesByExpression.get(expression);
		if (decision == null)
			return null;
		if (decision.sourceSemanticTypeId != semanticTypeId(expression.t)
			|| decision.targetSemanticTypeId != semanticTypeId(targetType)
			|| !sameBinding(decision.functionId, decision.programRevision, decision.bodyRevision, decision.pipelineRevision, binding)) {
			throw 'reflaxe.ocaml [ocaml-imap-interface:stale-storage-alias]: storage alias "${decision.id}" disagrees with the final typed initializer or function revision';
		}
		requireStorageAliasDecision(decision);
		return copyStorageAlias(decision);
	}

	/** Returns the sealed raw-storage owner for one exact standard Map cast. */
	public function storageAliasUseFor(expression:TypedExpr):Null<OcamlIMapStorageAliasDecision> {
		final decision = storageAliasUsesByExpression.get(expression);
		if (decision == null)
			return null;
		if (!sameBinding(decision.functionId, decision.programRevision, decision.bodyRevision, decision.pipelineRevision, binding))
			throw 'reflaxe.ocaml [ocaml-imap-interface:stale-storage-alias]: storage alias "${decision.id}" belongs to another function revision';
		requireStorageAliasDecision(decision);
		return copyStorageAlias(decision);
	}

	/** Returns the raw-storage owner when syntax reads one sealed local occurrence. */
	public function storageAliasUseForLocal(localId:Int, position:haxe.macro.Expr.Position):Null<OcamlIMapStorageAliasDecision> {
		final decision = storageAliasUsesByLocalOccurrence.get(localUseKey(localId, position));
		if (decision == null)
			return null;
		if (!sameBinding(decision.functionId, decision.programRevision, decision.bodyRevision, decision.pipelineRevision, binding))
			throw 'reflaxe.ocaml [ocaml-imap-interface:stale-storage-alias]: storage alias "${decision.id}" belongs to another function revision';
		requireStorageAliasDecision(decision);
		return copyStorageAlias(decision);
	}

	/** Returns stable conversion records for reports and inspection. */
	public function conversions():Array<OcamlIMapInterfaceConversionDecision> {
		return orderedConversions.map(copyConversion);
	}

	/** Returns stable call records for reports and inspection. */
	public function calls():Array<OcamlIMapInterfaceCallDecision> {
		return orderedCalls.map(copyCall);
	}

	/** Returns stable standard Map storage-alias records for reports and inspection. */
	public function storageAliases():Array<OcamlIMapStorageAliasDecision> {
		return orderedStorageAliases.map(copyStorageAlias);
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

	/** Rejects a malformed standard Map storage-alias record. */
	public static function requireStorageAliasDecision(decision:OcamlIMapStorageAliasDecision):Void {
		OcamlIMapInterfaceContract.requireStorageAlias(decision);
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

	static function localUseKey(localId:Int, position:haxe.macro.Expr.Position):String {
		return '$localId:${sourceKey(position)}';
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

	static function storageAliasFingerprint(decision:OcamlIMapStorageAliasDecision):String {
		return [
			decision.id,
			decision.source.file,
			Std.string(decision.source.min),
			Std.string(decision.source.max),
			decision.sourceSemanticTypeId,
			decision.sourceCarrierTypeId,
			decision.preservedCarrierTypeId,
			decision.targetSemanticTypeId,
			decision.keySemanticTypeId,
			decision.valueSemanticTypeId,
			(decision.standardKeyKind : String),
			(decision.nullPolicy : String),
			decision.uses.map(use -> '${use.source.file}:${use.source.min}:${use.source.max}:${use.nativeOperation}:${use.carrierTypeId}').join(","),
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

	static function copyStorageAliasUse(use:OcamlIMapStorageAliasUseDecision):OcamlIMapStorageAliasUseDecision {
		return {
			source: {file: use.source.file, min: use.source.min, max: use.source.max},
			nativeOperation: use.nativeOperation,
			carrierTypeId: use.carrierTypeId
		};
	}

	static function copyStorageAlias(decision:OcamlIMapStorageAliasDecision):OcamlIMapStorageAliasDecision {
		return {
			id: decision.id,
			source: {file: decision.source.file, min: decision.source.min, max: decision.source.max},
			sourceSemanticTypeId: decision.sourceSemanticTypeId,
			sourceCarrierTypeId: decision.sourceCarrierTypeId,
			preservedCarrierTypeId: decision.preservedCarrierTypeId,
			targetSemanticTypeId: decision.targetSemanticTypeId,
			keySemanticTypeId: decision.keySemanticTypeId,
			valueSemanticTypeId: decision.valueSemanticTypeId,
			standardKeyKind: decision.standardKeyKind,
			nullPolicy: decision.nullPolicy,
			uses: decision.uses.map(copyStorageAliasUse),
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
	final staticStorage:OcamlStaticStoragePlan;

	public function new(context:CompilationContext, binding:OcamlFunctionPlanBinding, staticStorage:OcamlStaticStoragePlan) {
		this.context = context;
		this.binding = binding;
		this.staticStorage = staticStorage;
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
		final storageAliases = planStandardMapStorageAliases(expression);

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
					if (storageAliases.initializers.get(initializer) == null)
						registerConversion(variable.t, initializer, OcamlIMapInterfaceConversionRole.LocalInitializer, variable.id);
				case TBinop(OpAssign, left, right):
					registerConversion(left.t, right, OcamlIMapInterfaceConversionRole.Assignment, -1);
				case _:
			}
			TypedExprTools.iter(current, visit);
		}

		visit(expression);
		return new OcamlIMapInterfacePlan(binding, conversions, calls, storageAliases.initializers, storageAliases.uses);
	}

	/**
		Finds Haxe's closed standard-Map expansion locals before interface boxing.

		The result is deliberately occurrence-bound. A local is admitted only when
		every read in the final typed function is the storage argument of a matching
		target-authored `NativeHxMap` operation. Any other read, assignment, or
		capture leaves the initializer on the ordinary interface-conversion path.
	**/
	function planStandardMapStorageAliases(expression:TypedExpr):PlannedStandardMapStorageAliases {
		final candidates:Map<Int, PendingStandardMapStorageAlias> = [];

		function collect(current:TypedExpr):Void {
			switch (current.expr) {
				case TFunction(_):
					return;
				case TVar(local, initializer) if (initializer != null):
					final target = exactIMap(local.t);
					final source = standardMapStorageSource(initializer);
					if (target != null && source != null && sameType(target.key, source.key) && sameType(target.value, source.value)) {
						candidates.set(local.id, {
							localId: local.id,
							targetType: local.t,
							initializer: initializer,
							keyType: source.key,
							valueType: source.value,
							kind: source.kind,
							sourceCarrierTypeId: source.sourceCarrierTypeId,
							nullPolicy: source.nullPolicy,
							uses: [],
							useExpressions: [],
							invalid: false
						});
					}
				case _:
			}
			TypedExprTools.iter(current, collect);
		}

		collect(expression);
		if (!candidates.keys().hasNext())
			return {initializers: new ObjectMap(), uses: new ObjectMap()};

		function validateUses(current:TypedExpr):Void {
			final approved = nativeStandardMapStorageUse(current);
			if (approved != null) {
				final candidate = candidates.get(approved.localId);
				if (candidate != null
					&& candidate.kind == approved.kind
					&& sameType(candidate.keyType, approved.keyType)
					&& sameType(candidate.valueType, approved.valueType)) {
					candidate.uses.push({
						source: approved.source,
						nativeOperation: approved.operation,
						carrierTypeId: standardCarrierId(candidate.kind)
					});
					candidate.useExpressions.push(approved.storageExpression);
					candidate.useExpressions.push(approved.boundaryExpression);
					switch (current.expr) {
						case TCall(callee, arguments):
							validateUses(callee);
							for (index in 1...arguments.length)
								validateUses(arguments[index]);
						case _:
					}
					return;
				}
			}
			switch (current.expr) {
				case TLocal(local):
					final candidate = candidates.get(local.id);
					if (candidate != null)
						candidate.invalid = true;
				case _:
			}
			TypedExprTools.iter(current, validateUses);
		}

		validateUses(expression);
		final initializers:ObjectMap<TypedExpr, OcamlIMapStorageAliasDecision> = new ObjectMap();
		final uses:ObjectMap<TypedExpr, OcamlIMapStorageAliasDecision> = new ObjectMap();
		for (candidate in candidates) {
			if (candidate.invalid || candidate.uses.length == 0)
				continue;
			candidate.uses.sort((left, right) -> Reflect.compare(storageAliasUseIdentity(left), storageAliasUseIdentity(right)));
			var duplicateUse = false;
			for (index in 1...candidate.uses.length) {
				if (storageAliasUseIdentity(candidate.uses[index - 1]) == storageAliasUseIdentity(candidate.uses[index])) {
					duplicateUse = true;
					break;
				}
			}
			if (duplicateUse)
				continue;
			final source = OcamlLoweredOrigin.sourceSpan(candidate.initializer.pos);
			final keySemanticTypeId = semanticTypeId(candidate.keyType);
			final valueSemanticTypeId = semanticTypeId(candidate.valueType);
			final keyKind = standardKeyKind(candidate.kind);
			final fingerprint = [
				binding.functionId,
				binding.programRevision,
				binding.bodyRevision,
				binding.pipelineRevision,
				'${source.file}:${source.min}:${source.max}',
				keySemanticTypeId,
				valueSemanticTypeId,
				(keyKind : String),
				(candidate.nullPolicy : String)
			].concat(candidate.uses.map(storageAliasUseIdentity)).join("|");
			final decision:OcamlIMapStorageAliasDecision = {
				id: "imap-storage-alias:" + Sha256.encode(fingerprint).substr(0, 24),
				source: source,
				sourceSemanticTypeId: semanticTypeId(candidate.initializer.t),
				sourceCarrierTypeId: candidate.sourceCarrierTypeId,
				preservedCarrierTypeId: standardCarrierId(candidate.kind),
				targetSemanticTypeId: semanticTypeId(candidate.targetType),
				keySemanticTypeId: keySemanticTypeId,
				valueSemanticTypeId: valueSemanticTypeId,
				standardKeyKind: keyKind,
				nullPolicy: candidate.nullPolicy,
				uses: candidate.uses.map(copyAliasUse),
				proofId: OcamlIMapInterfacePlan.STORAGE_ALIAS_PROOF_ID,
				proofClaim: OcamlIMapInterfacePlan.STORAGE_ALIAS_PROOF_CLAIM,
				functionId: binding.functionId,
				programRevision: binding.programRevision,
				bodyRevision: binding.bodyRevision,
				pipelineRevision: binding.pipelineRevision
			};
			OcamlIMapInterfacePlan.requireStorageAliasDecision(decision);
			initializers.set(candidate.initializer, decision);
			for (useExpression in candidate.useExpressions)
				uses.set(useExpression, decision);
		}
		return {initializers: initializers, uses: uses};
	}

	/** Recognizes one exact target-authored native Map call and its storage local. */
	function nativeStandardMapStorageUse(expression:TypedExpr):Null<NativeStandardMapStorageUse> {
		return switch (expression.expr) {
			case TCall({expr: TField(_, FStatic(classRef, fieldRef))}, arguments) if (arguments.length > 0):
				final classType = classRef.get();
				if (canonicalClassName(classType) != "haxe.ds.NativeHxMap") {
					null;
				} else {
					final operation = fieldRef.get().name;
					final operationKind = nativeOperationKind(operation);
					final storage = operationKind == null ? null : nativeStorageLocal(arguments[0], operationKind);
					if (operationKind == null || storage == null) {
						null;
					} else {
						{
							localId: storage.localId,
							storageExpression: storage.localExpression,
							boundaryExpression: arguments[0],
							operation: operation,
							source: OcamlLoweredOrigin.sourceSpan(storage.localExpression.pos),
							kind: storage.kind,
							keyType: storage.keyType,
							valueType: storage.valueType
						};
					}
				}
			case _:
				null;
		};
	}

	/** Returns the exact local and carrier behind one typed standard-map cast. */
	function nativeStorageLocal(expression:TypedExpr, expectedKind:OcamlStandardMapCarrierKind):Null<{
		localId:Int,
		localExpression:TypedExpr,
		kind:OcamlStandardMapCarrierKind,
		keyType:Type,
		valueType:Type
	}> {
		final outer = unwrapParenthesesAndMetadata(expression);
		return switch (outer.expr) {
			case TCast(child, _):
				final standard = switch (TypeTools.follow(outer.t)) {
					case TInst(classRef, parameters):
						final classType = classRef.get();
						// The cast's standard Map class is shown as `HxMap` after it
						// receives its OCaml native name. The
						// canonical source identity still distinguishes StringMap,
						// IntMap, and ObjectMap before syntax is built.
						if (OcamlStandardMapCarrierContract.kindForClass(classType) != expectedKind) {
							null;
						} else switch (expectedKind) {
							case StringKeys if (parameters.length == 1): {kind: expectedKind, key: ContextType.stringType(), value: parameters[0]};
							case IntKeys if (parameters.length == 1): {kind: expectedKind, key: ContextType.intType(), value: parameters[0]};
							case ObjectIdentityKeys if (parameters.length == 2): {kind: expectedKind, key: parameters[0], value: parameters[1]};
							case _: null;
						}
					case _: null;
				};
				final inner = unwrapParenthesesAndMetadata(child);
				switch (inner.expr) {
					case TLocal(local) if (standard != null): {
							localId: local.id,
							localExpression: inner,
							kind: standard.kind,
							keyType: standard.key,
							valueType: standard.value
						};
					case _: null;
				}
			case _:
				null;
		};
	}

	/** Returns the exact standard `haxe.ds.Map<K,V>` abstract facts. */
	static function standardMapAbstractTypes(type:Type):Null<{
		kind:OcamlStandardMapCarrierKind,
		key:Type,
		value:Type
	}> {
		return switch (followTypeAliases(type)) {
			case TAbstract(abstractRef, parameters):
				final abstractType = abstractRef.get();
				if (abstractType.pack.length == 2 && abstractType.pack[0] == "haxe" && abstractType.pack[1] == "ds" && abstractType.name == "Map"
					&& parameters.length == 2) {
					final kind = standardMapKindForKey(parameters[0]);
					kind == null ? null : {kind: kind, key: parameters[0], value: parameters[1]};
				} else {
					null;
				}
			case _:
				null;
		};
	}

	/**
		Selects the raw standard Map carrier that an `IMap` expansion may preserve.

		A nullable value is admitted only for an exact static field read whose field
		declaration still has `Map<K,V>` storage. This matters because an arbitrary
		`Null<Map<K,V>>` local can use a different target representation and cannot
		be treated as an `HxMap` merely because its source type looks similar.
	**/
	function standardMapStorageSource(initializer:TypedExpr):Null<{
		kind:OcamlStandardMapCarrierKind,
		key:Type,
		value:Type,
		sourceCarrierTypeId:String,
		nullPolicy:OcamlIMapStorageAliasNullPolicy
	}> {
		final direct = standardMapAbstractTypes(initializer.t);
		if (direct != null) {
			return {
				kind: direct.kind,
				key: direct.key,
				value: direct.value,
				sourceCarrierTypeId: standardCarrierId(direct.kind),
				nullPolicy: OcamlIMapStorageAliasNullPolicy.NonNullableSource
			};
		}

		final nullable = nullableStandardMapAbstractTypes(initializer.t);
		if (nullable == null)
			return null;
		final storageEntry = switch (unwrapParenthesesAndMetadata(initializer).expr) {
			case TField(_, FStatic(classRef, fieldRef)):
				final classType = classRef.get();
				staticStorage.require(classType.module, classType.name, fieldRef.get().name);
			case _: null;
		};
		if (storageEntry == null
			|| storageEntry.semanticTypeId != semanticTypeId(initializer.t)
			|| storageEntry.carrierTypeId != "Obj.t") {
			return null;
		}
		return {
			kind: nullable.kind,
			key: nullable.key,
			value: nullable.value,
			sourceCarrierTypeId: storageEntry.carrierTypeId,
			nullPolicy: OcamlIMapStorageAliasNullPolicy.CheckNullAndUnbox
		};
	}

	/** Returns the standard Map facts inside one exact `Null<Map<K,V>>`. */
	static function nullableStandardMapAbstractTypes(type:Type):Null<{
		kind:OcamlStandardMapCarrierKind,
		key:Type,
		value:Type
	}> {
		return switch (followTypeAliases(type)) {
			case TAbstract(abstractRef, [inner]):
				final abstractType = abstractRef.get();
				if (abstractType.pack.length == 0 && abstractType.name == "Null") standardMapAbstractTypes(inner); else null;
			case _:
				null;
		};
	}

	/** Follows host indirections without erasing the `Map` abstract itself. */
	static function followTypeAliases(type:Type):Type {
		var current = type;
		var depth = 0;
		while (depth++ < 32) {
			final next = switch (current) {
				case TLazy(resolve): resolve();
				case TMono(reference):
					final resolved = reference.get();
					resolved == null ? current : resolved;
				case TType(typeRef, parameters):
					final alias = typeRef.get();
					TypeTools.applyTypeParameters(alias.type, alias.params, parameters);
				case _:
					return current;
			};
			if (next == current)
				return current;
			current = next;
		}
		return current;
	}

	static function standardMapKindForKey(keyType:Type):Null<OcamlStandardMapCarrierKind> {
		return switch (TypeTools.follow(keyType)) {
			case TInst(classRef, _):
				final classType = classRef.get();
				(classType.pack.length == 0 && classType.name == "String") ? OcamlStandardMapCarrierKind.StringKeys : OcamlStandardMapCarrierKind.ObjectIdentityKeys;
			case TAbstract(abstractRef, _):
				final abstractType = abstractRef.get();
				(abstractType.pack.length == 0 && abstractType.name == "Int") ? OcamlStandardMapCarrierKind.IntKeys : null;
			case TAnonymous(_):
				OcamlStandardMapCarrierKind.ObjectIdentityKeys;
			case _:
				null;
		};
	}

	static function canonicalClassName(classType:ClassType):String {
		final rewrittenName = (classType.pack ?? []).concat([classType.name]).join(".");
		return OcamlTypedDeclarationIdentity.canonicalSourceName(classType.meta, rewrittenName, "a class");
	}

	static function nativeOperationKind(operation:String):Null<OcamlStandardMapCarrierKind> {
		final prefixes = ["set", "get", "exists", "remove", "clear", "copy", "keys", "values", "pairs"];
		for (prefix in prefixes) {
			if (operation == prefix + "_string")
				return OcamlStandardMapCarrierKind.StringKeys;
			if (operation == prefix + "_int")
				return OcamlStandardMapCarrierKind.IntKeys;
			if (operation == prefix + "_object")
				return OcamlStandardMapCarrierKind.ObjectIdentityKeys;
		}
		return null;
	}

	static function standardKeyKind(kind:OcamlStandardMapCarrierKind):OcamlStandardIMapKeyKind {
		return switch (kind) {
			case StringKeys: OcamlStandardIMapKeyKind.StringKey;
			case IntKeys: OcamlStandardIMapKeyKind.IntKey;
			case ObjectIdentityKeys: OcamlStandardIMapKeyKind.ObjectIdentityKey;
		};
	}

	static function standardCarrierId(kind:OcamlStandardMapCarrierKind):String {
		return OcamlStandardIMapCallContract.carrierId(standardKeyKind(kind));
	}

	static function storageAliasUseIdentity(use:OcamlIMapStorageAliasUseDecision):String {
		return '${use.source.file}:${use.source.min}:${use.source.max}:${use.nativeOperation}:${use.carrierTypeId}';
	}

	static function copyAliasUse(use:OcamlIMapStorageAliasUseDecision):OcamlIMapStorageAliasUseDecision {
		return {
			source: {file: use.source.file, min: use.source.min, max: use.source.max},
			nativeOperation: use.nativeOperation,
			carrierTypeId: use.carrierTypeId
		};
	}

	static function unwrapParenthesesAndMetadata(expression:TypedExpr):TypedExpr {
		return switch (expression.expr) {
			case TParenthesis(inner), TMeta(_, inner): unwrapParenthesesAndMetadata(inner);
			case _: expression;
		};
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
		final abstractSource = standardMapAbstractTypes(sourceType);
		if (abstractSource != null) {
			if (!sameType(abstractSource.key, target.key) || !sameType(abstractSource.value, target.value))
				return null;
			final sourceKind:OcamlIMapInterfaceSourceKind = switch (abstractSource.kind) {
				case StringKeys: OcamlIMapInterfaceSourceKind.StandardStringMapAbstract;
				case IntKeys: OcamlIMapInterfaceSourceKind.StandardIntMapAbstract;
				case ObjectIdentityKeys: OcamlIMapInterfaceSourceKind.StandardObjectMapAbstract;
			};
			return standardConversion(value, sourceType, role, roleIndex, null, target.owner, target.key, target.value, abstractSource.kind, sourceKind);
		}
		return switch (TypeTools.follow(sourceType)) {
			case TInst(classRef, parameters):
				final sourceClass = classRef.get();
				final standard = standardMapTypes(sourceClass, parameters);
				if (standard != null) {
					if (!sameType(standard.key, target.key) || !sameType(standard.value, target.value))
						return null;
					final sourceKind:OcamlIMapInterfaceSourceKind = switch (standard.kind) {
						case StringKeys: OcamlIMapInterfaceSourceKind.StandardStringMap;
						case IntKeys: OcamlIMapInterfaceSourceKind.StandardIntMap;
						case ObjectIdentityKeys: OcamlIMapInterfaceSourceKind.StandardObjectMap;
					};
					standardConversion(value, sourceType, role, roleIndex, sourceClass, target.owner, target.key, target.value, standard.kind, sourceKind);
				} else {
					final implemented = implementedIMap(sourceClass);
					if (implemented == null || !sameType(implemented.key, target.key) || !sameType(implemented.value, target.value))
						return null;
					userConversion(value, sourceType, role, roleIndex, sourceClass, target.owner, target.key, target.value);
				}
			case _:
				null;
		};
	}

	function standardConversion(value:TypedExpr, sourceType:Type, role:OcamlIMapInterfaceConversionRole, roleIndex:Int, sourceClass:Null<ClassType>,
			interfaceClass:ClassType, keyType:Type, valueType:Type, kind:OcamlStandardMapCarrierKind,
			sourceKind:OcamlIMapInterfaceSourceKind):OcamlIMapInterfaceConversionMaterialization {
		final keyKind:OcamlStandardIMapKeyKind = switch (kind) {
			case StringKeys: OcamlStandardIMapKeyKind.StringKey;
			case IntKeys: OcamlStandardIMapKeyKind.IntKey;
			case ObjectIdentityKeys: OcamlStandardIMapKeyKind.ObjectIdentityKey;
		};
		final keySemanticTypeId = semanticTypeId(keyType);
		final valueSemanticTypeId = semanticTypeId(valueType);
		final operations = retainedInterfaceOperations(interfaceClass);
		final targetSemanticTypeId = 'haxe.IMap<$keySemanticTypeId, $valueSemanticTypeId>';
		final methods:Array<OcamlIMapInterfaceMethodDecision> = operations.map(operation -> {
			name: OcamlStandardIMapCallContract.sourceFieldName(operation),
			sourceOwnerModuleId: interfaceClass.module,
			sourceOwnerTypeName: interfaceClass.name,
			argumentSemanticTypeIds: OcamlStandardIMapCallContract.argumentSemanticTypeIds(operation, keySemanticTypeId, valueSemanticTypeId),
			resultSemanticTypeId: OcamlStandardIMapCallContract.expectedResultSemanticTypeId(operation, targetSemanticTypeId, keySemanticTypeId,
				valueSemanticTypeId)
		});
		final decision = conversionDecision(value, sourceType, role, roleIndex, sourceKind, sourceClass, OcamlStandardIMapCallContract.carrierId(keyKind),
			keyType, valueType, keyKind, methods, OcamlStandardIMapCallContract.adapterRuntimeCapabilities(keySemanticTypeId, valueSemanticTypeId));
		return {
			decision: decision,
			keyType: keyType,
			valueType: valueType,
			sourceClass: sourceClass,
			operations: operations,
			methods: []
		};
	}

	function userConversion(value:TypedExpr, sourceType:Type, role:OcamlIMapInterfaceConversionRole, roleIndex:Int, sourceClass:ClassType,
			interfaceClass:ClassType, keyType:Type, valueType:Type):OcamlIMapInterfaceConversionMaterialization {
		if (sourceClass.params.length > 0)
			throw 'reflaxe.ocaml [ocaml-imap-interface:unsupported-user-implementation]: generic user IMap implementation ${fullClassName(sourceClass)} needs an explicit specialization contract';
		final methods:Array<OcamlIMapInterfaceMethodMaterialization> = [];
		for (operation in retainedInterfaceOperations(interfaceClass)) {
			final name = OcamlStandardIMapCallContract.sourceFieldName(operation);
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
			operations: methods.map(method -> method.operation),
			methods: methods
		};
	}

	function conversionDecision(value:TypedExpr, sourceType:Type, role:OcamlIMapInterfaceConversionRole, roleIndex:Int,
			sourceKind:OcamlIMapInterfaceSourceKind, sourceClass:Null<ClassType>, sourceCarrierTypeId:String, keyType:Type, valueType:Type,
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

	static function exactIMap(type:Type):Null<{owner:ClassType, key:Type, value:Type}> {
		return switch (TypeTools.follow(type)) {
			case TInst(classRef, parameters) if (OcamlStandardIMapCallContract.isIMapClass(classRef.get()) && parameters.length == 2):
				{owner: classRef.get(), key: parameters[0], value: parameters[1]};
			case _:
				null;
		};
	}

	/**
		Returns the interface methods that survived Haxe dead-code elimination.

		For example, a program that only calls `map.get()` and `map.keys()` receives
		an OCaml `imap_t` record with only those two fields. Adapters must mirror
		that retained surface exactly: adding an unused field is a native OCaml type
		error, while omitting a retained field would make the actual call impossible.
	**/
	static function retainedInterfaceOperations(interfaceClass:ClassType):Array<OcamlStandardIMapOperation> {
		final retained:Map<String, Bool> = [];
		for (field in interfaceClass.fields.get()) {
			if (OcamlIMapInterfacePlan.REQUIRED_METHODS.indexOf(field.name) < 0)
				throw 'reflaxe.ocaml [ocaml-imap-interface:unsupported-retained-method]: ${fullClassName(interfaceClass)}.${field.name} is outside the pinned IMap adapter contract';
			retained.set(field.name, true);
		}
		final out:Array<OcamlStandardIMapOperation> = [];
		for (operation in OcamlIMapInterfaceContract.requiredOperations()) {
			if (retained.exists(OcamlStandardIMapCallContract.sourceFieldName(operation)))
				out.push(operation);
		}
		return out;
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
} /** Resolves core primitive `Type` values without keeping compiler globals in decisions. */

private class ContextType {
	public static function stringType():Type {
		return haxe.macro.Context.getType("String");
	}

	public static function intType():Type {
		return haxe.macro.Context.getType("Int");
	}
}
#end
