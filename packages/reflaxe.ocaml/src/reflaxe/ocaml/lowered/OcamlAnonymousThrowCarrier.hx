package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
#if macro
import haxe.crypto.Sha256;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import reflaxe.ocaml.lowered.OcamlDynamicEqualityPlan.OcamlDynamicCarrierModel;
#end

/**
	Identifies an existing anonymous container for opaque exception transport.

	The shared carrier classifier excludes structural values represented as
	OCaml records or tuples. Transport preserves the remaining Obj.t value;
	it neither visits fields nor grants permission to generate field operations.
	The type digest detects a changed source type within the revision-bound
	function plan. It is not a recursive field-layout or cache-reuse proof.

	Only compiler macros inspect live Haxe types. Runtime report readers use
	the serialized identity checks without loading compiler-only type APIs.
**/
class OcamlAnonymousThrowCarrier {
	public static inline final PROOF_ID = "opaque-anonymous-container-throw-v1";
	public static inline final PREFIX = "anonymous-container:";

	#if macro
	/** Selects only a real structural type whose existing carrier is Obj.t. */
	public static function semanticTypeId(type:Type):Null<String> {
		return switch (TypeTools.follow(type)) {
			case TAnonymous(_) if (OcamlDynamicCarrierModel.usesDynamicCarrier(type)):
				PREFIX + Sha256.encode(TypeTools.toString(type));
			case _: null;
		};
	}
	#end

	/** Checks the serialized identity without treating it as a field-layout proof. */
	public static function isSemanticTypeId(value:String):Bool {
		return value != null && ~/^anonymous-container:[0-9a-f]{64}$/.match(value);
	}

	/** The exception-only identity never registers a general field representation. */
	public static function representationId(semanticTypeId:String):String {
		return "control-representation:" + semanticTypeId + ":hxanon-v1";
	}
}
#end
