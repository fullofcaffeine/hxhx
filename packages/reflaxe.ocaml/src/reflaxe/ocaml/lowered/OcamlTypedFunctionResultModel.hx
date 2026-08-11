package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
import haxe.crypto.Sha256;

/**
	Defines the stable report identities for a private typed return crossing.

	The compiler and the standalone report reader both use this model. Keeping the
	identity calculation here prevents the report reader from loading Haxe compiler
	types only to validate an already generated report.
**/
class OcamlTypedFunctionResultModel {
	public static inline final MODEL = "typed-function-local-inferred-result-v1";
	public static inline final PROOF_ID = "typed-function-result-early-return-control-v1";
	public static inline final INFERRED_CARRIER_TYPE_ID = "ocaml-inferred-function-result";
	public static inline final REPRESENTATION_PREFIX = "control-representation:typed-function-result-v1:";

	/** Returns the function-owned identity for one inferred input or output. */
	public static function representationId(functionId:String, role:String, semanticTypeId:String):String {
		return REPRESENTATION_PREFIX + Sha256.encode(functionId + "|" + role + "|" + semanticTypeId).substr(0, 24);
	}
}
#end
