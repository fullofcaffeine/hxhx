package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
/**
	Defines the exact internal carrier admitted for one non-null Haxe `Float`.

	This contract is intentionally narrower than general Float support. It lets
	sealed binary Bytes operations pass or return an already-typed Float through
	OCaml's binary64 `float` carrier. Float32 rounding belongs to the four-byte
	Bytes operation, not to this carrier. Nullable values, storage, arithmetic,
	formatting, comparison, serialization, Dynamic, and native ABI boundaries
	remain unadmitted.
**/
class OcamlFloatRepresentationContract {
	public static inline final SEMANTIC_TYPE_ID = "Float";
	public static inline final CARRIER_TYPE_ID = "float";
	public static inline final INTERNAL_REPRESENTATION_ID = "representation:Float:internal-value";
	public static inline final PROOF_ID = "direct-exact-float-internal-value-v1";
	public static inline final PROOF_CLAIM = "Exact non-null Haxe Float uses OCaml float only as an immutable internal value passed to or returned from a sealed Bytes binary32 or binary64 operation. OCaml float carries the source binary64 finite value, signed zero, infinities, subnormals, and NaN classification. Binary32 rounding and byte layout remain operation policies. This proof does not admit nullable Float, fields, mutable or captured locals, arrays, arbitrary calls, arithmetic, comparisons, formatting, parsing, Math, JSON, Serializer, Dynamic, or native ABI boundaries.";
}
#end
