package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
/**
	Stable identities shared by Bytes representation and operation planning.

	Direct `haxe.io.Bytes` and explicit core `Null<haxe.io.Bytes>` remain
	distinct typed Haxe forms. Both select the same nullable reference-bearing
	OCaml carrier; only a separately sealed producer occurrence may claim that
	one particular result is non-null.
**/
class OcamlBytesRepresentationContract {
	public static inline final DIRECT_SEMANTIC_TYPE_ID = "haxe.io.Bytes";
	public static inline final EXPLICIT_NULL_SEMANTIC_TYPE_ID = "Null<haxe.io.Bytes>";
	public static inline final CARRIER_TYPE_ID = "HxBytes.t";
	public static inline final DIRECT_INTERNAL_REPRESENTATION_ID = "representation:haxe.io.Bytes:internal-value";
	public static inline final DIRECT_PROOF_ID = "direct-haxe-bytes-reference-carrier-v1";
	public static inline final EXPLICIT_NULL_PROOF_ID = "explicit-null-haxe-bytes-reference-carrier-v1";
}
#end
