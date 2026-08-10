package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
#if macro
import haxe.macro.Type;
import haxe.macro.Type.ClassField;
import haxe.macro.Type.ClassType;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypeTools;
#end

/** The first standard `Array<T>` operations selected before OCaml syntax. */
enum abstract OcamlStandardArrayOperation(String) from String to String {
	final Concat = "concat";
	final Copy = "copy";
}

/**
	The complete runtime target for one admitted standard Array call.

	The typed Haxe call fixes the element, receiver, arguments, and result before
	the printer runs. The printer therefore receives `HxArray.concat` or
	`HxArray.copy` as checked facts instead of deciding from a field name.
**/
typedef OcamlStandardArrayCallTarget = {
	final operation:OcamlStandardArrayOperation;
	final elementSemanticTypeId:String;
	final receiverSemanticTypeId:String;
	final argumentSemanticTypeIds:Array<String>;
	final resultSemanticTypeId:String;
	final runtimeModule:String;
	final runtimeFunction:String;
	final runtimeCapabilities:Array<String>;
	final proofId:String;
	final proofClaim:String;
}

/** Selects and validates direct `Array.concat` and `Array.copy` calls. */
class OcamlStandardArrayCallContract {
	public static inline final PROOF_ID = "standard-array-typed-target-call-v1";
	public static inline final RUNTIME_CAPABILITY = "haxe-array";
	public static inline final PROOF_CLAIM = "The final typed Haxe call resolves to Array.concat or Array.copy on one exact Array element type. The sealed target selects the matching HxArray operation before OCaml syntax, and its schedule evaluates the receiver once before every source argument. This proof does not admit other Array methods or user-defined classes with the same field names.";

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
		if (receiverSemanticTypeId != expectedArrayType
			|| resultSemanticTypeId != expectedArrayType
			|| (operation == OcamlStandardArrayOperation.Concat
				&& (argumentSemanticTypeIds.length != 1 || argumentSemanticTypeIds[0] != expectedArrayType))
			|| (operation == OcamlStandardArrayOperation.Copy && argumentSemanticTypeIds.length != 0)) {
			return null;
		}
		final target:OcamlStandardArrayCallTarget = {
			operation: operation,
			elementSemanticTypeId: elementSemanticTypeId,
			receiverSemanticTypeId: receiverSemanticTypeId,
			argumentSemanticTypeIds: argumentSemanticTypeIds,
			resultSemanticTypeId: resultSemanticTypeId,
			runtimeModule: "HxArray",
			runtimeFunction: runtimeFunction(operation),
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
		final expectedArguments = target.operation == OcamlStandardArrayOperation.Concat ? [expectedArrayType] : [];
		if (target.elementSemanticTypeId.length == 0
			|| target.receiverSemanticTypeId != expectedArrayType
			|| target.argumentSemanticTypeIds.join("\n") != expectedArguments.join("\n")
			|| target.resultSemanticTypeId != expectedArrayType
			|| target.runtimeModule != "HxArray"
			|| target.runtimeFunction != runtimeFunction(target.operation)
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
			case _: throw 'reflaxe.ocaml [ocaml-array-call:invalid-operation]: unsupported standard Array operation "$operation"';
		}
	}

	/** Returns the private runtime function selected by one operation. */
	public static function runtimeFunction(operation:OcamlStandardArrayOperation):String {
		return sourceFieldName(operation);
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
			target.argumentSemanticTypeIds.join(","),
			target.resultSemanticTypeId,
			target.runtimeModule,
			target.runtimeFunction,
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
			argumentSemanticTypeIds: target.argumentSemanticTypeIds.copy(),
			resultSemanticTypeId: target.resultSemanticTypeId,
			runtimeModule: target.runtimeModule,
			runtimeFunction: target.runtimeFunction,
			runtimeCapabilities: target.runtimeCapabilities.copy(),
			proofId: target.proofId,
			proofClaim: target.proofClaim
		};
	}

	static function operationFor(fieldName:String, argumentCount:Int):Null<OcamlStandardArrayOperation> {
		return switch [fieldName, argumentCount] {
			case ["concat", 1]: OcamlStandardArrayOperation.Concat;
			case ["copy", 0]: OcamlStandardArrayOperation.Copy;
			case _: null;
		}
	}
}
#end
