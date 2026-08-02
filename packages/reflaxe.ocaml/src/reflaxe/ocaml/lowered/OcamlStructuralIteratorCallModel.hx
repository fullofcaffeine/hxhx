package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
#if macro
import haxe.macro.Type;
import haxe.macro.Type.ClassField;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypeTools;
#end

/** The structural `Iterator<T>` operation selected before OCaml syntax. */
enum abstract OcamlStructuralIteratorOperation(String) from String to String {
	final HasNext = "has-next";
	final Next = "next";
}

/**
	The exact runtime operation for one direct structural Iterator call.

	The target records the Haxe receiver and result types for inspection while
	keeping the runtime carrier explicit. `OcamlBuilder` only materializes the
	receiver once and invokes the recorded `HxIterator` function; it does not
	re-discover whether the source field means `hasNext` or `next`.
**/
typedef OcamlStructuralIteratorCallTarget = {
	final operation:OcamlStructuralIteratorOperation;
	final receiverSemanticTypeId:String;
	final receiverCarrierTypeId:String;
	final resultSemanticTypeId:String;
	final runtimeModule:String;
	final runtimeFunction:String;
	final runtimeCapabilities:Array<String>;
	final proofId:String;
	final proofClaim:String;
}

/**
	Selects direct `hasNext()` and `next()` calls on structural Iterator values.

	This is deliberately a consumer-only boundary. Iterator construction,
	array-to-iterator conversion, class adaptation, and standalone method values
	remain separate work even though they may eventually use the same runtime
	carrier.
**/
class OcamlStructuralIteratorCallContract {
	public static inline final MODEL = "typed-structural-iterator-consumer-v1";
	public static inline final PROOF_ID = "structural-iterator-runtime-call-v1";
	public static inline final RUNTIME_CAPABILITY = "haxe-iterator";
	public static inline final RECEIVER_CARRIER = "HxIterator.t";

	#if macro
	/** Selects one supported direct structural Iterator call. */
	public static function select(receiver:TypedExpr, field:ClassField, arguments:Array<TypedExpr>, resultType:Type):Null<OcamlStructuralIteratorCallTarget> {
		if (arguments.length != 0 || !isIteratorType(receiver.t))
			return null;
		final operation = operationFor(field.name);
		if (operation == null || !fieldMatchesOperation(field, operation, resultType))
			return null;
		final target:OcamlStructuralIteratorCallTarget = {
			operation: operation,
			receiverSemanticTypeId: TypeTools.toString(receiver.t),
			receiverCarrierTypeId: RECEIVER_CARRIER,
			resultSemanticTypeId: TypeTools.toString(resultType),
			runtimeModule: "HxIterator",
			runtimeFunction: runtimeFunction(operation),
			runtimeCapabilities: [RUNTIME_CAPABILITY],
			proofId: PROOF_ID,
			proofClaim: "The final typed Haxe call invokes hasNext or next on a structural Iterator value with no source arguments. The target materializes that receiver once, calls the matching HxIterator operation, and preserves the typed result selected by the existing call boundary. This proof does not cover iterator construction, adaptation, or a method value used without immediate invocation."
		};
		require(target);
		return target;
	}

	/** Rechecks a sealed target against its final typed call occurrence. */
	public static function matches(target:OcamlStructuralIteratorCallTarget, receiver:TypedExpr, field:ClassField, arguments:Array<TypedExpr>,
			resultType:Type):Bool {
		final selected = select(receiver, field, arguments, resultType);
		return selected != null && fingerprint(selected) == fingerprint(target);
	}

	static function isIteratorType(type:Type):Bool {
		return switch (TypeTools.follow(type)) {
			case TAnonymous(anonymousRef): final fields = anonymousRef.get()
					.fields; final hasNext = Lambda.find(fields,
					field -> field.name == "hasNext"); final next = Lambda.find(fields,
					field -> field.name == "next"); hasNext != null && next != null && fieldReturnsExactBool(hasNext) && isZeroArgumentFunction(next.type);
			case _:
				false;
		}
	}

	static function fieldMatchesOperation(field:ClassField, operation:OcamlStructuralIteratorOperation, resultType:Type):Bool {
		if (!isZeroArgumentFunction(field.type))
			return false;
		final declaredResult = switch (TypeTools.follow(field.type)) {
			case TFun(_, result): TypeTools.toString(result);
			case _: return false;
		}
		return declaredResult == TypeTools.toString(resultType)
			&& (operation != OcamlStructuralIteratorOperation.HasNext || declaredResult == "Bool");
	}

	static function fieldReturnsExactBool(field:ClassField):Bool {
		return switch (TypeTools.follow(field.type)) {
			case TFun(arguments, result): arguments.length == 0 && TypeTools.toString(result) == "Bool";
			case _: false;
		}
	}

	static function isZeroArgumentFunction(type:Type):Bool {
		return switch (TypeTools.follow(type)) {
			case TFun(arguments, _): arguments.length == 0;
			case _: false;
		}
	}
	#end

	/** Rejects a corrupted or incomplete structural Iterator target. */
	public static function require(target:OcamlStructuralIteratorCallTarget):Void {
		if (target == null)
			throw "reflaxe.ocaml [ocaml-iterator:invalid-plan]: structural Iterator target must not be null";
		if (target.receiverSemanticTypeId.length == 0
			|| target.resultSemanticTypeId.length == 0
			|| target.receiverCarrierTypeId != RECEIVER_CARRIER
			|| target.runtimeModule != "HxIterator"
			|| target.runtimeFunction != runtimeFunction(target.operation)
			|| target.runtimeCapabilities.length != 1
			|| target.runtimeCapabilities[0] != RUNTIME_CAPABILITY
			|| target.proofId != PROOF_ID
			|| target.proofClaim.length == 0
			|| (target.operation == OcamlStructuralIteratorOperation.HasNext && target.resultSemanticTypeId != "Bool")) {
			throw "reflaxe.ocaml [ocaml-iterator:invalid-plan]: structural Iterator target disagrees with its receiver, operation, result, runtime, or proof";
		}
	}

	/** Copies the immutable target out of request-owned planning state. */
	public static function copy(target:OcamlStructuralIteratorCallTarget):OcamlStructuralIteratorCallTarget {
		return {
			operation: target.operation,
			receiverSemanticTypeId: target.receiverSemanticTypeId,
			receiverCarrierTypeId: target.receiverCarrierTypeId,
			resultSemanticTypeId: target.resultSemanticTypeId,
			runtimeModule: target.runtimeModule,
			runtimeFunction: target.runtimeFunction,
			runtimeCapabilities: target.runtimeCapabilities.copy(),
			proofId: target.proofId,
			proofClaim: target.proofClaim
		};
	}

	/** Canonical target form used by call identities and deterministic reports. */
	public static function fingerprint(target:OcamlStructuralIteratorCallTarget):String {
		require(target);
		return [
			(target.operation : String),
			target.receiverSemanticTypeId,
			target.receiverCarrierTypeId,
			target.resultSemanticTypeId,
			target.runtimeModule + "." + target.runtimeFunction,
			target.runtimeCapabilities.join(","),
			target.proofId,
			target.proofClaim
		].join("|");
	}

	/** Returns the source field represented by one structural operation. */
	public static function sourceFieldName(operation:OcamlStructuralIteratorOperation):String {
		return switch (operation) {
			case HasNext: "hasNext";
			case Next: "next";
			case _: throw 'reflaxe.ocaml [ocaml-iterator:invalid-operation]: unsupported structural Iterator operation "$operation"';
		}
	}

	/** Returns the runtime function selected by one structural operation. */
	public static function runtimeFunction(operation:OcamlStructuralIteratorOperation):String {
		return sourceFieldName(operation);
	}

	/** Stable requirement identities owned by one exact call occurrence. */
	public static function runtimeRequirementIds(callId:String, target:OcamlStructuralIteratorCallTarget):Array<String> {
		require(target);
		return [callId + ":runtime:" + RUNTIME_CAPABILITY];
	}

	static function operationFor(fieldName:String):Null<OcamlStructuralIteratorOperation> {
		return switch (fieldName) {
			case "hasNext": OcamlStructuralIteratorOperation.HasNext;
			case "next": OcamlStructuralIteratorOperation.Next;
			case _: null;
		}
	}
}
#end
