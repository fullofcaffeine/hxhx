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

	/**
		Haxe null remains the shared runtime sentinel at nullable boundaries.

		The direct carrier can preserve and pass that sentinel only after a
		separately reviewed boundary conversion; it does not make the sentinel a
		valid value for target-native operations on the carrier.
	**/
	final RuntimeSentinel = "runtime-sentinel";
}

/** Which source-level identity promise the selected carrier preserves. */
enum abstract OcamlRepresentationIdentityPolicy(String) from String to String {
	/** The value has primitive value semantics and no object identity. */
	final PrimitiveValue = "primitive-value";

	/** Copies preserve the identity of one reference-bearing runtime value. */
	final ReferenceIdentity = "reference-identity";

	/**
		The carrier preserves the identity policy of its dynamically stored payload.

		Primitive payloads retain value semantics. Reference-bearing payloads keep
		their existing runtime identity; entering Dynamic never clones them.
	**/
	final DynamicPayloadIdentity = "dynamic-payload-identity";
}

/** How source aliases can observe this represented value. */
enum abstract OcamlRepresentationAliasingPolicy(String) from String to String {
	/** The primitive value itself has no independently observable alias identity. */
	final NoValueAlias = "no-value-alias";

	/** Copies share one reference-bearing value and observe the same mutations. */
	final SharedReferenceAliases = "shared-reference-aliases";

	/**
		Aliasing follows the payload stored in Dynamic.

		Primitive payloads have no source-visible alias identity. Reference-bearing
		payloads continue to share the same underlying value and mutations.
	**/
	final DynamicPayloadAliases = "dynamic-payload-aliases";
}

/** Which surrounding storage location owns replacement of the represented value. */
enum abstract OcamlRepresentationStorageMutationPolicy(String) from String to String {
	/** A newer immutable binding represents a later value. */
	final ImmutableBinding = "immutable-binding";

	/** One local OCaml ref cell owns shared mutation. */
	final SharedLocalCell = "shared-local-cell";

	/** The enclosing record field owns mutation. */
	final InstanceFieldOwner = "instance-field-owner";

	/** The enclosing static OCaml ref cell owns mutation. */
	final StaticFieldOwner = "static-field-owner";

	/** The enclosing Haxe array element owns replacement of its stored value. */
	final ArrayElementOwner = "array-element-owner";
}

/** Whether the represented value can mutate independently of its storage location. */
enum abstract OcamlRepresentationValueMutationPolicy(String) from String to String {
	/** The represented value itself is immutable. */
	final ImmutableValue = "immutable-value";

	/** The carrier is a mutable runtime container shared by reference aliases. */
	final MutableRuntimeContainer = "mutable-runtime-container";

	/**
		Whether mutation is observable depends on the value stored in Dynamic.

		The `Obj.t` carrier itself adds no mutation. It preserves a mutable
		reference payload or an immutable primitive payload unchanged.
	**/
	final DynamicPayloadMutation = "dynamic-payload-mutation";
}

/** Whether the Haxe value needs an additional target box or wrapper. */
enum abstract OcamlRepresentationBoxingPolicy(String) from String to String {
	/** The carrier stores the value directly without a wrapper or Dynamic box. */
	final DirectUnboxed = "direct-unboxed";

	/**
		The carrier is already the target runtime container and needs no additional
		Dynamic box or representation wrapper.
	**/
	final DirectRuntimeContainer = "direct-runtime-container";

	/**
		A Haxe value-semantic type uses one canonical nominal OCaml record.

		The record needs no additional Dynamic box, but its target module, type,
		and exact field-layout revision remain part of the representation proof.
		The carrier does not imply source-visible reference identity or aliasing.
	**/
	final DirectNominalValueCarrier = "direct-nominal-value-carrier";

	/**
		Primitive values are boxed only when they enter this nullable carrier.

		The carrier itself is `Obj.t`: it preserves the shared Haxe null sentinel
		and boxed non-null primitive values. A separate occurrence plan must prove
		every box, carrier-preserving copy, and checked non-null read.
	**/
	final NullablePrimitiveCarrier = "nullable-primitive-carrier";

	/**
		Exact Haxe `String` values use OCaml `string` directly while the canonical
		runtime null sentinel crosses into that carrier through one proof-backed
		cast.

		Only the representation materializer may construct the sentinel value.
		Ordinary string literals, copies, comparisons, and admitted Haxe call
		boundaries preserve the selected carrier directly.
	**/
	final NullableStringCarrier = "nullable-string-carrier";

	/**
		A Haxe class value uses one nominal OCaml record for non-null payloads.

		The source class remains nullable. This first slice admits only producer
		and receiver occurrences proven to contain that record payload; a general
		null-to-record crossing is not implied by the carrier decision.
	**/
	final NullableNominalRecordCarrier = "nullable-nominal-record-carrier";

	/**
		Haxe Dynamic stores one already-produced target value in `Obj.t`.

		Every concrete-to-Dynamic occurrence owns one explicit conversion.
		`Obj.repr` preserves ordinary concrete values; exact Bool uses the runtime's
		distinguishable Bool box because OCaml Bool and Int are both immediate
		values. Existing Dynamic values and the canonical null sentinel preserve
		the carrier directly.
	**/
	final DynamicCarrier = "dynamic-carrier";
}

/**
	Which value Haxe supplies when storage has no explicit initializer.

	The policy is semantic metadata. A focused materializer may turn an admitted
	field policy into target syntax only after the representation decision has
	been resolved for the current program.
**/
enum abstract OcamlRepresentationImplicitDefaultPolicy(String) from String to String {
	/** This representation has not admitted implicit storage initialization. */
	final NotAdmitted = "not-admitted";

	/** Exact Haxe `Int` storage starts at integer zero. */
	final ExactIntZero = "exact-int-zero";

	/** Exact Haxe `Bool` storage starts at false. */
	final ExactBoolFalse = "exact-bool-false";

	/** Nullable primitive storage starts at the canonical Haxe null sentinel. */
	final RuntimeNullSentinel = "runtime-null-sentinel";
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
	final storageMutationPolicy:OcamlRepresentationStorageMutationPolicy;
	final valueMutationPolicy:OcamlRepresentationValueMutationPolicy;
	final boxingPolicy:OcamlRepresentationBoxingPolicy;
	final implicitDefaultPolicy:OcamlRepresentationImplicitDefaultPolicy;
	final reason:String;
	final proof:OcamlRepresentationProof;
	final profileEligibility:Array<String>;

	/** Canonical OCaml module that owns an admitted nominal record carrier. */
	final ?nominalTargetModuleName:String;

	/** Unqualified record type inside the canonical target module. */
	final ?nominalTargetTypeName:String;

	/** Revision of the exact field layout represented by the nominal carrier. */
	final ?nominalLayoutRevision:String;

	/** Program-owned array shape used by this representation, when it is an array. */
	final ?arrayDescriptorId:String;

	/** Exact content revision of `arrayDescriptorId`. */
	final ?arrayDescriptorRevision:String;
}

/** One immutable program-owned representation decision. */
typedef OcamlRepresentationDecision = {
	> OcamlRepresentationSelection,
	final id:String;
	final key:String;
	final programRevision:String;
	final revision:String;
}

/**
	Host-neutral identity for one direct, closed, flat Haxe array type.

	The normalizing adapter creates this plain value from the current typed Haxe
	program. It deliberately retains no macro `Type` object, so the representation
	registry can validate and report the same array shape without depending on
	request-local compiler identity.
**/
typedef OcamlNormalizedRepresentedArray = {
	final arraySemanticTypeId:String;
	final elementSemanticTypeId:String;
	final sourceForm:String;
	final closureKind:String;
	final outerWrapperKind:String;
	final nestingKind:String;
}

/**
	One immutable program-owned description of a represented Haxe array.

	A descriptor binds an array shape to an element representation that is
	explicitly valid for array storage. Domain-specific representation decisions
	still own outer nullability, identity, aliasing, replacement, and boxing. This
	record only prevents local, call, and control consumers from independently
	reconstructing the element carrier or `HxArray.t` composition.
**/
typedef OcamlRepresentedArrayDescriptor = {
	final id:String;
	final key:String;
	final programRevision:String;
	final modelRevision:String;
	final revision:String;
	final arraySemanticTypeId:String;
	final sourceForm:String;
	final closureKind:String;
	final outerWrapperKind:String;
	final elementSemanticTypeId:String;
	final elementRepresentationId:String;
	final elementRepresentationRevision:String;
	final elementCarrierTypeId:String;
	final elementDomain:OcamlRepresentationDomain;
	final carrierFamilyId:String;
	final arrayCarrierTypeId:String;
	final runtimeCarrierCapabilityId:String;
	final runtimeKindTagId:String;
	final nestingKind:String;
	final reason:String;
	final proofId:String;
	final proofClaim:String;
	final profileEligibility:Array<String>;
}
#end
