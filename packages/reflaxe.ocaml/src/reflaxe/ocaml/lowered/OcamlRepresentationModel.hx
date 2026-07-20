package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
/** Where one Haxe value is stored or passed inside the OCaml target. */
enum abstract OcamlRepresentationDomain(String) from String to String {
	/** An ordinary value used inside a function. */
	final InternalValue = "internal-value";

	/** A value stored in a mutable local cell. */
	final MutableLocalStorage = "mutable-local-storage";

	/** A mutable local cell shared with a nested function. */
	final CapturedLocalStorage = "captured-local-storage";

	/** A value stored in an ordinary instance field. */
	final InstanceField = "instance-field";

	/** A value stored in a mutable static field. */
	final StaticField = "static-field";

	/** A value stored in a Haxe array element. */
	final ArrayElement = "array-element";
}

/** How the selected carrier represents Haxe null. */
enum abstract OcamlRepresentationNullPolicy(String) from String to String {
	/** Null is not a valid value in this admitted representation. */
	final NonNull = "non-null";
}

/** Which source-level identity promise the selected carrier preserves. */
enum abstract OcamlRepresentationIdentityPolicy(String) from String to String {
	/** The value has primitive value semantics and no object identity. */
	final PrimitiveValue = "primitive-value";
}

/** How source aliases can observe this represented value. */
enum abstract OcamlRepresentationAliasingPolicy(String) from String to String {
	/** The primitive value itself has no independently observable alias identity. */
	final NoValueAlias = "no-value-alias";
}

/** Which surrounding owner, if any, makes updates observable. */
enum abstract OcamlRepresentationMutationPolicy(String) from String to String {
	/** The value itself is immutable. A newer binding represents a later value. */
	final ImmutableValue = "immutable-value";

	/** One local OCaml ref cell owns shared mutation. */
	final SharedLocalCell = "shared-local-cell";

	/** The enclosing record field owns mutation. */
	final InstanceFieldOwner = "instance-field-owner";

	/** The enclosing static OCaml ref cell owns mutation. */
	final StaticFieldOwner = "static-field-owner";

	/** The enclosing Haxe-array representation owns mutation. */
	final ArrayOwner = "array-owner";
}

/** Whether the Haxe value needs an additional target box or wrapper. */
enum abstract OcamlRepresentationBoxingPolicy(String) from String to String {
	/** The carrier stores the value directly without a wrapper or Dynamic box. */
	final DirectUnboxed = "direct-unboxed";
}

/** A named, reviewable claim supporting one representation choice. */
typedef OcamlRepresentationProof = {
	final id:String;
	final claim:String;
}

/** Candidate facts registered for one semantic type and representation domain. */
typedef OcamlRepresentationSelection = {
	final semanticTypeId:String;
	final domain:OcamlRepresentationDomain;
	final carrierTypeId:String;
	final nullPolicy:OcamlRepresentationNullPolicy;
	final identityPolicy:OcamlRepresentationIdentityPolicy;
	final aliasingPolicy:OcamlRepresentationAliasingPolicy;
	final mutationPolicy:OcamlRepresentationMutationPolicy;
	final boxingPolicy:OcamlRepresentationBoxingPolicy;
	final reason:String;
	final proof:OcamlRepresentationProof;
	final profileEligibility:Array<String>;
}

/** One immutable program-owned representation decision. */
typedef OcamlRepresentationDecision = {
	> OcamlRepresentationSelection,
	final id:String;
	final key:String;
	final programRevision:String;
	final revision:String;
}
#end
