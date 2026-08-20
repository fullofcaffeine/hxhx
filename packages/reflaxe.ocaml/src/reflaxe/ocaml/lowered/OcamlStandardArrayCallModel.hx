package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
#if macro
import haxe.macro.Type;
import haxe.macro.Type.ClassField;
import haxe.macro.Type.ClassType;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypeTools;
#end

/** The bounded standard `Array<T>` operations selected before OCaml syntax. */
enum abstract OcamlStandardArrayOperation(String) from String to String {
	final Concat = "concat";
	final Copy = "copy";
	final Push = "push";
	final Pop = "pop";
	final Shift = "shift";
	final Unshift = "unshift";
	final Reverse = "reverse";
	final Insert = "insert";
	final Remove = "remove";
	final Contains = "contains";
	final Resize = "resize";
	final Splice = "splice";
	final IndexOf = "indexOf";
	final IndexOfDefault = "indexOfDefault";
	final LastIndexOf = "lastIndexOf";
	final LastIndexOfDefault = "lastIndexOfDefault";
	final Slice = "slice";
	final SliceDefault = "sliceDefault";
	final Sort = "sort";
	final Map = "map";
	final Filter = "filter";
}

/** Whether a standard Array operation returns a Haxe value or only an effect. */
enum abstract OcamlStandardArrayResultKind(String) from String to String {
	final Value = "value";
	final EffectOnlyVoid = "effect-only-void";
}

/**
	The complete runtime target for one admitted standard Array call.

	The typed Haxe call fixes the element, receiver, arguments, and result before
	the printer runs. The printer therefore receives one exact `HxArray`
	operation as a checked fact instead of deciding from a field name.
**/
typedef OcamlStandardArrayCallTarget = {
	final operation:OcamlStandardArrayOperation;
	final elementSemanticTypeId:String;
	final receiverSemanticTypeId:String;
	final parameterSemanticTypeIds:Array<String>;
	final argumentSemanticTypeIds:Array<String>;
	final argumentCompatibilityProofIds:Array<String>;
	final resultElementSemanticTypeId:Null<String>;
	final resultSemanticTypeId:String;
	final resultKind:OcamlStandardArrayResultKind;
	final runtimeModule:String;
	final runtimeFunction:String;
	final runtimeTakesUnitArgument:Bool;
	final runtimeCapabilities:Array<String>;
	final proofId:String;
	final proofClaim:String;
}

/** Selects and validates the admitted direct standard-Array calls. */
class OcamlStandardArrayCallContract {
	public static inline final PROOF_ID = "standard-array-typed-target-call-v8";
	public static inline final ARGUMENT_COMPATIBILITY_PROOF_ID = "haxe-typed-array-argument-compatible-v1";
	public static inline final RUNTIME_CAPABILITY = "haxe-array";
	public static inline final PROOF_CLAIM = "The final typed Haxe call resolves to one admitted standard Array operation on one exact Array element type. The sealed target fixes its arguments, optional mapped result element, value-or-Void result, and matching HxArray operation before OCaml syntax. Its schedule evaluates the receiver once before every source argument. Callback identities exclude local parameter names. This proof does not admit other Array methods or user-defined classes with the same field names.";

	#if macro
	/** Returns whether a class is the root Haxe `Array<T>` declaration. */
	public static function isArrayClass(classType:ClassType):Bool {
		return classType.pack != null && classType.pack.length == 0 && classType.module == "Array" && classType.name == "Array";
	}

	/** Returns whether a followed type is one exact standard Array instance. */
	public static function isArrayType(type:Type):Bool {
		return switch (TypeTools.follow(type)) {
			case TInst(classRef, parameters): isArrayClass(classRef.get()) && parameters.length == 1;
			case _:
				false;
		}
	}

	/** Selects the bounded standard-Array operation from one final typed call. */
	public static function select(classType:ClassType, parameters:Array<Type>, field:ClassField, receiver:TypedExpr, arguments:Array<TypedExpr>,
			resultType:Type):Null<OcamlStandardArrayCallTarget> {
		if (!isArrayClass(classType) || parameters.length != 1)
			return null;
		final operation = operationFor(field.name, arguments.length);
		if (operation == null)
			return null;
		final elementSemanticTypeId = TypeTools.toString(parameters[0]);
		final expectedArrayType = 'Array<$elementSemanticTypeId>';
		// The resolved field owner is the standard Array declaration. Use that
		// canonical type instead of the receiver's source alias, such as the
		// NativeRest<T> typedef used by haxe.Rest. The field identity and exact
		// Array parameter still prevent a user-defined `copy` method from entering
		// this target family.
		final receiverSemanticTypeId = expectedArrayType;
		final resultSemanticTypeId = TypeTools.toString(resultType);
		final resultElementSemanticTypeId = operation == OcamlStandardArrayOperation.Map ? arrayElementSemanticTypeId(resultType) : null;
		if (operation == OcamlStandardArrayOperation.Map && resultElementSemanticTypeId == null)
			return null;
		if (operation == OcamlStandardArrayOperation.Sort && !sortComparatorMatches(arguments[0].t, elementSemanticTypeId))
			return null;
		if (operation == OcamlStandardArrayOperation.Map
			&& !unaryCallbackMatches(arguments[0].t, elementSemanticTypeId, resultElementSemanticTypeId))
			return null;
		if (operation == OcamlStandardArrayOperation.Filter && !unaryCallbackMatches(arguments[0].t, elementSemanticTypeId, "Bool"))
			return null;
		final argumentSemanticTypeIds = switch (operation) {
			case Sort: [sortComparatorSemanticTypeId(elementSemanticTypeId)];
			case Map: [unaryCallbackSemanticTypeId(elementSemanticTypeId, resultElementSemanticTypeId)];
			case Filter: [unaryCallbackSemanticTypeId(elementSemanticTypeId, "Bool")];
			case _: arguments.map(argument -> TypeTools.toString(argument.t));
		};
		final parameterSemanticTypeIds = expectedParameterSemanticTypeIds(operation, elementSemanticTypeId, resultElementSemanticTypeId);
		if (receiverSemanticTypeId != expectedArrayType
			|| !sourceArgumentsMatch(operation, argumentSemanticTypeIds, parameterSemanticTypeIds)
			|| resultSemanticTypeId != expectedResultSemanticTypeId(operation, elementSemanticTypeId, resultElementSemanticTypeId)) {
			return null;
		}
		final target:OcamlStandardArrayCallTarget = {
			operation: operation,
			elementSemanticTypeId: elementSemanticTypeId,
			receiverSemanticTypeId: receiverSemanticTypeId,
			parameterSemanticTypeIds: parameterSemanticTypeIds,
			argumentSemanticTypeIds: argumentSemanticTypeIds,
			argumentCompatibilityProofIds: arguments.map(_ -> ARGUMENT_COMPATIBILITY_PROOF_ID),
			resultElementSemanticTypeId: resultElementSemanticTypeId,
			resultSemanticTypeId: resultSemanticTypeId,
			resultKind: resultKind(operation),
			runtimeModule: "HxArray",
			runtimeFunction: runtimeFunction(operation),
			runtimeTakesUnitArgument: runtimeTakesUnitArgument(operation),
			runtimeCapabilities: [RUNTIME_CAPABILITY],
			proofId: PROOF_ID,
			proofClaim: PROOF_CLAIM
		};
		require(target);
		return target;
	}

	/** Rechecks a sealed target against the final typed call occurrence. */
	public static function matches(target:OcamlStandardArrayCallTarget, classType:ClassType, parameters:Array<Type>, field:ClassField, receiver:TypedExpr,
			arguments:Array<TypedExpr>, resultType:Type):Bool {
		final selected = select(classType, parameters, field, receiver, arguments, resultType);
		return selected != null && fingerprint(selected) == fingerprint(target);
	}
	#end

	/** Rejects an incomplete or internally conflicting Array target. */
	public static function require(target:OcamlStandardArrayCallTarget):Void {
		if (target == null)
			throw "reflaxe.ocaml [ocaml-array-call:invalid-plan]: standard Array target must not be null";
		final expectedArrayType = 'Array<${target.elementSemanticTypeId}>';
		final expectedMappedElement = target.operation == OcamlStandardArrayOperation.Map ? target.resultElementSemanticTypeId : null;
		final expectedParameters = expectedParameterSemanticTypeIds(target.operation, target.elementSemanticTypeId, expectedMappedElement);
		if (target.elementSemanticTypeId.length == 0
			|| (target.operation == OcamlStandardArrayOperation.Map ? target.resultElementSemanticTypeId == null
				|| target.resultElementSemanticTypeId.length == 0 : target.resultElementSemanticTypeId != null)
			|| target.receiverSemanticTypeId != expectedArrayType
			|| target.parameterSemanticTypeIds.join("\n") != expectedParameters.join("\n")
			|| !sourceArgumentsMatch(target.operation, target.argumentSemanticTypeIds, expectedParameters)
			|| target.argumentCompatibilityProofIds.length != expectedParameters.length
			|| Lambda.exists(target.argumentCompatibilityProofIds, proofId -> proofId != ARGUMENT_COMPATIBILITY_PROOF_ID)
			|| target.resultSemanticTypeId != expectedResultSemanticTypeId(target.operation, target.elementSemanticTypeId, expectedMappedElement)
			|| target.resultKind != resultKind(target.operation)
			|| target.runtimeModule != "HxArray"
			|| target.runtimeFunction != runtimeFunction(target.operation)
			|| target.runtimeTakesUnitArgument != runtimeTakesUnitArgument(target.operation)
			|| target.runtimeCapabilities.length != 1
			|| target.runtimeCapabilities[0] != RUNTIME_CAPABILITY
			|| target.proofId != PROOF_ID
			|| target.proofClaim != PROOF_CLAIM) {
			throw "reflaxe.ocaml [ocaml-array-call:invalid-plan]: standard Array target disagrees with its typed operation, runtime, or proof";
		}
	}

	/** Returns the source method represented by one selected operation. */
	public static function sourceFieldName(operation:OcamlStandardArrayOperation):String {
		return switch (operation) {
			case Concat: "concat";
			case Copy: "copy";
			case Push: "push";
			case Pop: "pop";
			case Shift: "shift";
			case Unshift: "unshift";
			case Reverse: "reverse";
			case Insert: "insert";
			case Remove: "remove";
			case Contains: "contains";
			case Resize: "resize";
			case Splice: "splice";
			case IndexOf | IndexOfDefault: "indexOf";
			case LastIndexOf | LastIndexOfDefault: "lastIndexOf";
			case Slice | SliceDefault: "slice";
			case Sort: "sort";
			case Map: "map";
			case Filter: "filter";
			case _: throw 'reflaxe.ocaml [ocaml-array-call:invalid-operation]: unsupported standard Array operation "$operation"';
		}
	}

	/** Returns the Haxe call-result form fixed by one admitted operation. */
	public static function resultKind(operation:OcamlStandardArrayOperation):OcamlStandardArrayResultKind {
		return switch (operation) {
			case Unshift | Reverse | Insert | Resize | Sort: OcamlStandardArrayResultKind.EffectOnlyVoid;
			case Concat | Copy | Push | Pop | Shift | Remove | Contains | Splice | IndexOf | IndexOfDefault | LastIndexOf | LastIndexOfDefault | Slice |
				SliceDefault | Map | Filter:
				OcamlStandardArrayResultKind.Value;
			case _: throw 'reflaxe.ocaml [ocaml-array-call:invalid-operation]: unsupported standard Array operation "$operation"';
		}
	}

	/** Returns the private runtime function selected by one operation. */
	public static function runtimeFunction(operation:OcamlStandardArrayOperation):String {
		return switch (operation) {
			case IndexOfDefault: "indexOf_default";
			case LastIndexOfDefault: "lastIndexOf_default";
			case SliceDefault: "slice_default";
			case _: sourceFieldName(operation);
		}
	}

	/** Returns whether the private OCaml function needs a trailing `unit`. */
	public static function runtimeTakesUnitArgument(operation:OcamlStandardArrayOperation):Bool {
		return switch (operation) {
			case Pop | Shift | Reverse: true;
			case Concat | Copy | Push | Unshift | Insert | Remove | Contains | Resize | Splice | IndexOf | IndexOfDefault | LastIndexOf | LastIndexOfDefault |
				Slice | SliceDefault | Sort | Map | Filter:
				false;
			case _: throw 'reflaxe.ocaml [ocaml-array-call:invalid-operation]: unsupported standard Array operation "$operation"';
		}
	}

	/** Returns the exact runtime requirement identity for this call. */
	public static function runtimeRequirementId(callId:String, target:OcamlStandardArrayCallTarget):String {
		require(target);
		if (callId.length == 0)
			throw "reflaxe.ocaml [ocaml-array-call:invalid-plan]: standard Array call identity must not be empty";
		return '$callId:runtime:$RUNTIME_CAPABILITY:${target.runtimeFunction}';
	}

	/** Returns a stable representation used by plan copying and validation. */
	public static function fingerprint(target:OcamlStandardArrayCallTarget):String {
		require(target);
		return [
			(target.operation : String),
			target.elementSemanticTypeId,
			target.receiverSemanticTypeId,
			target.parameterSemanticTypeIds.join(","),
			target.argumentSemanticTypeIds.join(","),
			target.argumentCompatibilityProofIds.join(","),
			target.resultElementSemanticTypeId ?? "no-result-element",
			target.resultSemanticTypeId,
			(target.resultKind : String),
			target.runtimeModule,
			target.runtimeFunction,
			target.runtimeTakesUnitArgument ? "runtime-unit" : "runtime-no-unit",
			target.runtimeCapabilities.join(","),
			target.proofId,
			target.proofClaim
		].join("|");
	}

	/** Copies the immutable target out of request-owned planning state. */
	public static function copy(target:OcamlStandardArrayCallTarget):OcamlStandardArrayCallTarget {
		return {
			operation: target.operation,
			elementSemanticTypeId: target.elementSemanticTypeId,
			receiverSemanticTypeId: target.receiverSemanticTypeId,
			parameterSemanticTypeIds: target.parameterSemanticTypeIds.copy(),
			argumentSemanticTypeIds: target.argumentSemanticTypeIds.copy(),
			argumentCompatibilityProofIds: target.argumentCompatibilityProofIds.copy(),
			resultElementSemanticTypeId: target.resultElementSemanticTypeId,
			resultSemanticTypeId: target.resultSemanticTypeId,
			resultKind: target.resultKind,
			runtimeModule: target.runtimeModule,
			runtimeFunction: target.runtimeFunction,
			runtimeTakesUnitArgument: target.runtimeTakesUnitArgument,
			runtimeCapabilities: target.runtimeCapabilities.copy(),
			proofId: target.proofId,
			proofClaim: target.proofClaim
		};
	}

	static function operationFor(fieldName:String, argumentCount:Int):Null<OcamlStandardArrayOperation> {
		return switch [fieldName, argumentCount] {
			case ["concat", 1]: OcamlStandardArrayOperation.Concat;
			case ["copy", 0]: OcamlStandardArrayOperation.Copy;
			case ["push", 1]: OcamlStandardArrayOperation.Push;
			case ["pop", 0]: OcamlStandardArrayOperation.Pop;
			case ["shift", 0]: OcamlStandardArrayOperation.Shift;
			case ["unshift", 1]: OcamlStandardArrayOperation.Unshift;
			case ["reverse", 0]: OcamlStandardArrayOperation.Reverse;
			case ["insert", 2]: OcamlStandardArrayOperation.Insert;
			case ["remove", 1]: OcamlStandardArrayOperation.Remove;
			case ["contains", 1]: OcamlStandardArrayOperation.Contains;
			case ["resize", 1]: OcamlStandardArrayOperation.Resize;
			case ["splice", 2]: OcamlStandardArrayOperation.Splice;
			case ["indexOf", 1]: OcamlStandardArrayOperation.IndexOfDefault;
			case ["indexOf", 2]: OcamlStandardArrayOperation.IndexOf;
			case ["lastIndexOf", 1]: OcamlStandardArrayOperation.LastIndexOfDefault;
			case ["lastIndexOf", 2]: OcamlStandardArrayOperation.LastIndexOf;
			case ["slice", 1]: OcamlStandardArrayOperation.SliceDefault;
			case ["slice", 2]: OcamlStandardArrayOperation.Slice;
			case ["sort", 1]: OcamlStandardArrayOperation.Sort;
			case ["map", 1]: OcamlStandardArrayOperation.Map;
			case ["filter", 1]: OcamlStandardArrayOperation.Filter;
			case _: null;
		}
	}

	static function expectedParameterSemanticTypeIds(operation:OcamlStandardArrayOperation, elementSemanticTypeId:String,
			resultElementSemanticTypeId:Null<String>):Array<String> {
		return switch (operation) {
			case Concat: ['Array<$elementSemanticTypeId>'];
			case Push | Unshift | Remove | Contains: [elementSemanticTypeId];
			case Insert: ["Int", elementSemanticTypeId];
			case Resize: ["Int"];
			case Splice: ["Int", "Int"];
			case IndexOf | LastIndexOf: [elementSemanticTypeId, "Null<Int>"];
			case IndexOfDefault | LastIndexOfDefault: [elementSemanticTypeId];
			case Slice: ["Int", "Null<Int>"];
			case SliceDefault: ["Int"];
			case Sort: [sortComparatorSemanticTypeId(elementSemanticTypeId)];
			case Map:
				if (resultElementSemanticTypeId == null)
					throw "reflaxe.ocaml [ocaml-array-call:invalid-plan]: Array.map needs one exact result element type";
				[unaryCallbackSemanticTypeId(elementSemanticTypeId, resultElementSemanticTypeId)];
			case Filter: [unaryCallbackSemanticTypeId(elementSemanticTypeId, "Bool")];
			case Copy | Pop | Shift | Reverse: [];
			case _: throw 'reflaxe.ocaml [ocaml-array-call:invalid-operation]: unsupported standard Array operation "$operation"';
		}
	}

	/**
		Checks only facts that remain meaningful after macro typing is gone.

		For example, `Array<Dynamic>.push("x")` has a `String` source argument and
		a `Dynamic` parameter. The Haxe typer already proved that crossing. This
		sealed target records both types plus an exact compatibility proof instead
		of trying to recreate Haxe's type system from their display strings.
	**/
	static function sourceArgumentsMatch(operation:OcamlStandardArrayOperation, sourceArguments:Array<String>, parameters:Array<String>):Bool {
		if (sourceArguments.length != parameters.length || Lambda.exists(sourceArguments, argument -> argument.length == 0))
			return false;
		return switch (operation) {
			case Concat: concatArgumentsShareCarrier(sourceArguments[0], parameters[0]);
			case Insert: sourceArguments[0] == "Int";
			case Resize: sourceArguments[0] == "Int";
			case Splice: sourceArguments[0] == "Int" && sourceArguments[1] == "Int";
			case IndexOf | LastIndexOf: sourceArguments[1] == "Int" || sourceArguments[1] == "Null<Int>";
			case Slice: sourceArguments[0] == "Int" && (sourceArguments[1] == "Int" || sourceArguments[1] == "Null<Int>");
			case SliceDefault: sourceArguments[0] == "Int";
			case Sort | Map | Filter: sourceArguments[0] == parameters[0];
			case Push | Unshift | Remove | Contains | IndexOfDefault | LastIndexOfDefault: true;
			case Copy | Pop | Shift | Reverse: true;
			case _: false;
		}
	}

	/**
		Accepts only concat argument types that need no element conversion.

		Haxe can preserve `Null<String>` in a typed Array method signature even
		though `String` already uses the same nullable OCaml string carrier. This
		one pair can therefore share `HxArray.concat` directly. Other compatible
		Haxe types can need boxing or another carrier, so they remain unsupported
		until lowering records their element conversion explicitly.
	**/
	static function concatArgumentsShareCarrier(sourceArgument:String, parameter:String):Bool {
		if (sourceArgument == parameter)
			return true;
		return (sourceArgument == "Array<String>" && parameter == "Array<Null<String>>")
			|| (sourceArgument == "Array<Null<String>>" && parameter == "Array<String>");
	}

	static function expectedResultSemanticTypeId(operation:OcamlStandardArrayOperation, elementSemanticTypeId:String,
			resultElementSemanticTypeId:Null<String>):String {
		return switch (operation) {
			case Concat | Copy: 'Array<$elementSemanticTypeId>';
			case Push: "Int";
			case Pop | Shift: 'Null<$elementSemanticTypeId>';
			case Unshift | Reverse | Insert: "Void";
			case Remove | Contains: "Bool";
			case Resize: "Void";
			case Splice: 'Array<$elementSemanticTypeId>';
			case IndexOf | IndexOfDefault | LastIndexOf | LastIndexOfDefault: "Int";
			case Slice | SliceDefault: 'Array<$elementSemanticTypeId>';
			case Sort: "Void";
			case Map:
				if (resultElementSemanticTypeId == null)
					throw "reflaxe.ocaml [ocaml-array-call:invalid-plan]: Array.map needs one exact result element type";
				'Array<$resultElementSemanticTypeId>';
			case Filter: 'Array<$elementSemanticTypeId>';
			case _: throw 'reflaxe.ocaml [ocaml-array-call:invalid-operation]: unsupported standard Array operation "$operation"';
		}
	}

	static function sortComparatorSemanticTypeId(elementSemanticTypeId:String):String {
		return '($elementSemanticTypeId,$elementSemanticTypeId)->Int';
	}

	static function unaryCallbackSemanticTypeId(inputSemanticTypeId:String, resultSemanticTypeId:String):String {
		return '($inputSemanticTypeId)->$resultSemanticTypeId';
	}

	#if macro
	static function sortComparatorMatches(type:Type, elementSemanticTypeId:String):Bool {
		return switch (TypeTools.follow(type)) {
			case TFun(arguments, result):
				arguments.length == 2
				&& TypeTools.toString(arguments[0].t) == elementSemanticTypeId
				&& TypeTools.toString(arguments[1].t) == elementSemanticTypeId
				&& TypeTools.toString(result) == "Int";
			case _:
				false;
		}
	}

	static function unaryCallbackMatches(type:Type, inputSemanticTypeId:String, resultSemanticTypeId:String):Bool {
		return switch (TypeTools.follow(type)) {
			case TFun(arguments, result): arguments.length == 1 && TypeTools.toString(arguments[0].t) == inputSemanticTypeId && TypeTools.toString(result) == resultSemanticTypeId;
			case _:
				false;
		}
	}

	static function arrayElementSemanticTypeId(type:Type):Null<String> {
		return switch (TypeTools.follow(type)) {
			case TInst(classRef, parameters) if (isArrayClass(classRef.get()) && parameters.length == 1):
				TypeTools.toString(parameters[0]);
			case _:
				null;
		}
	}
	#end
}
#end
