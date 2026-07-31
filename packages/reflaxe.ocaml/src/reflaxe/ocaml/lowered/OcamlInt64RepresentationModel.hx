package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
import haxe.crypto.Sha256;

/**
	Defines the exact target record used for one non-null `haxe.Int64` value.

	Haxe exposes Int64 with value semantics. The OCaml target currently carries
	those 64 bits in the generated `Haxe_Int64.___int64_t` record. The record's
	fields happen to be mutable implementation details; admitted compiler
	operations must still treat the represented Int64 value as immutable and
	create a new record for a different value.
**/
class OcamlInt64RepresentationContract {
	public static inline final SEMANTIC_TYPE_ID = "haxe.Int64";
	public static inline final TARGET_MODULE_NAME = "Haxe_Int64";
	public static inline final TARGET_TYPE_NAME = "___int64_t";
	public static inline final QUALIFIED_CARRIER_TYPE_ID = "Haxe_Int64.___int64_t";
	public static inline final INTERNAL_REPRESENTATION_ID = "representation:haxe.Int64:internal-value";
	public static inline final PROOF_ID = "direct-exact-int64-nominal-value-v1";
	public static inline final PROOF_CLAIM = "Exact non-null haxe.Int64 values use the generated Haxe_Int64.___int64_t nominal record. The high and low signed Int fields preserve all 64 source bits. Although the generated carrier fields are mutable target details, this admitted representation has Haxe value semantics: callers receive no alias identity, compiler operations do not mutate an existing value, and a changed Int64 is a new record. This proof covers internal values only; nullable storage, ordinary fields, arrays, calls outside an occurrence plan, Dynamic, and native ABI boundaries remain unadmitted.";

	/**
		Revision of the exact generated record shape consumed by sealed plans.

		The canonical string names field order, carrier types, and physical OCaml
		mutability so a target-record change invalidates every dependent plan.
	**/
	public static final LAYOUT_REVISION = "sha256:" + Sha256.encode([
		"reflaxe.ocaml-int64-layout-v1",
		TARGET_MODULE_NAME,
		TARGET_TYPE_NAME,
		"0|__hx_type|Obj.t|immutable",
		"1|high|int|mutable",
		"2|low|int|mutable"
	].join("\n"));
}
#end
