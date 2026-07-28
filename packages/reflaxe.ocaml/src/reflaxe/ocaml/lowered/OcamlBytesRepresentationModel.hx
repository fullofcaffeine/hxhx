package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
/**
	Stable identities shared by Bytes representation and operation planning.

	Direct `haxe.io.Bytes` and explicit core `Null<haxe.io.Bytes>` remain
	distinct typed Haxe forms. Both select the same nullable reference-bearing
	OCaml carrier. That carrier stores the declared Haxe length separately from
	one mutable native data value, while a separately sealed producer occurrence
	decides how those two facts are created.
**/
class OcamlBytesRepresentationContract {
	public static inline final DIRECT_SEMANTIC_TYPE_ID = "haxe.io.Bytes";
	public static inline final EXPLICIT_NULL_SEMANTIC_TYPE_ID = "Null<haxe.io.Bytes>";
	public static inline final DATA_SEMANTIC_TYPE_ID = "haxe.io.BytesData";
	public static inline final CARRIER_TYPE_ID = "HxBytes.t";
	public static inline final DATA_CARRIER_TYPE_ID = "bytes";
	public static inline final CARRIER_SHAPE_ID = "explicit-length+mutable-native-data-v1";
	public static inline final DATA_ALIASING_POLICY = "shared-native-data-alias";
	public static inline final RANGE_BOUNDS_POLICY = "declared-length";
	public static inline final DIRECT_INTERNAL_REPRESENTATION_ID = "representation:haxe.io.Bytes:internal-value";
	public static inline final DATA_INTERNAL_REPRESENTATION_ID = "representation:haxe.io.BytesData:internal-value";
	public static inline final DIRECT_PROOF_ID = "direct-haxe-bytes-reference-carrier-v2";
	public static inline final EXPLICIT_NULL_PROOF_ID = "explicit-null-haxe-bytes-reference-carrier-v2";
	public static inline final DATA_PROOF_ID = "direct-haxe-bytes-data-alias-v1";
}
#end
