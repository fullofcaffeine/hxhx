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
	public static inline final PROOF_ID = "standard-array-typed-target-call-v2";
	public static inline final ARGUMENT_COMPATIBILITY_PROOF_ID = "haxe-typed-array-argument-compatible-v1";
	public static inline final RUNTIME_CAPABILITY = "haxe-array";
	public static inline final PROOF_CLAIM = "The final typed Haxe call resolves to one admitted standard Array operation on one exact Array element type. The sealed target fixes its arguments, value-or-Void result, and matching HxArray operation before OCaml syntax. Its schedule evaluates the receiver once before every source argument. This proof does not admit other Array methods or user-defined classes with the same field names.";

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
		final receiverSemanticTypeId = TypeTools.toString(receiver.t);
		final resultSemanticTypeId = TypeTools.toString(resultType);
		final argumentSemanticTypeIds = arguments.map(argument -> TypeTools.toString(argument.t));
		final parameterSemanticTypeIds = expectedParameterSemanticTypeIds(operation, elementSemanticTypeId);
		if (receiverSemanticTypeId != expectedArrayType
			|| !sourceArgumentsMatch(operation, argumentSemanticTypeIds, parameterSemanticTypeIds)
			|| resultSemanticTypeId != expectedResultSemanticTypeId(operation, elementSemanticTypeId)) {
			return null;
		}
		final target:OcamlStandardArrayCallTarget = {
			operation: operation,
			elementSemanticTypeId: elementSemanticTypeId,
			receiverSemanticTypeId: receiverSemanticTypeId,
			parameterSemanticTypeIds: parameterSemanticTypeIds,
			argumentSemanticTypeIds: argumentSemanticTypeIds,
			argumentCompatibilityProofIds: arguments.map(_ -> ARGUMENT_COMPATIBILITY_PROOF_ID),
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
		final expectedParameters = expectedParameterSemanticTypeIds(target.operation, target.elementSemanticTypeId);
		if (target.elementSemanticTypeId.length == 0
			|| target.receiverSemanticTypeId != expectedArrayType
			|| target.parameterSemanticTypeIds.join("\n") != expectedParameters.join("\n")
			|| !sourceArgumentsMatch(target.operation, target.argumentSemanticTypeIds, expectedParameters)
			|| target.argumentCompatibilityProofIds.length != expectedParameters.length
			|| Lambda.exists(target.argumentCompatibilityProofIds, proofId -> proofId != ARGUMENT_COMPATIBILITY_PROOF_ID)
			|| target.resultSemanticTypeId != expectedResultSemanticTypeId(target.operation, target.elementSemanticTypeId)
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
			case _: throw 'reflaxe.ocaml [ocaml-array-call:invalid-operation]: unsupported standard Array operation "$operation"';
		}
	}

	/** Returns the Haxe call-result form fixed by one admitted operation. */
	public static function resultKind(operation:OcamlStandardArrayOperation):OcamlStandardArrayResultKind {
		return switch (operation) {
			case Unshift | Reverse: OcamlStandardArrayResultKind.EffectOnlyVoid;
			case Concat | Copy | Push | Pop | Shift: OcamlStandardArrayResultKind.Value;
			case _: throw 'reflaxe.ocaml [ocaml-array-call:invalid-operation]: unsupported standard Array operation "$operation"';
		}
	}

	/** Returns the private runtime function selected by one operation. */
	public static function runtimeFunction(operation:OcamlStandardArrayOperation):String {
		return sourceFieldName(operation);
	}

	/** Returns whether the private OCaml function needs a trailing `unit`. */
	public static function runtimeTakesUnitArgument(operation:OcamlStandardArrayOperation):Bool {
		return switch (operation) {
			case Pop | Shift | Reverse: true;
			case Concat | Copy | Push | Unshift: false;
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
			case _: null;
		}
	}

	static function expectedParameterSemanticTypeIds(operation:OcamlStandardArrayOperation, elementSemanticTypeId:String):Array<String> {
		return switch (operation) {
			case Concat: ['Array<$elementSemanticTypeId>'];
			case Push | Unshift: [elementSemanticTypeId];
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
			case Concat: sourceArguments[0] == parameters[0];
			case Push | Unshift: true;
			case Copy | Pop | Shift | Reverse: true;
			case _: false;
		}
	}

	static function expectedResultSemanticTypeId(operation:OcamlStandardArrayOperation, elementSemanticTypeId:String):String {
		return switch (operation) {
			case Concat | Copy: 'Array<$elementSemanticTypeId>';
			case Push: "Int";
			case Pop | Shift: 'Null<$elementSemanticTypeId>';
			case Unshift | Reverse: "Void";
			case _: throw 'reflaxe.ocaml [ocaml-array-call:invalid-operation]: unsupported standard Array operation "$operation"';
		}
	}
}
#end
