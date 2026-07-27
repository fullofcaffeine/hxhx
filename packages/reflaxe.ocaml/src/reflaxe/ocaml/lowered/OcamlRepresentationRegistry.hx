package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.ds.StringMap;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationAliasingPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationBoxingPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationIdentityPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationImplicitDefaultPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationNullPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationProof;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationSelection;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationStorageMutationPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationValueMutationPolicy;

/**
	Owns the OCaml carrier selected for each admitted Haxe type and use domain.

	The registry is request-local. A decision answers a semantic question once—
	for example, how an exact non-null Haxe `Int` is stored in a mutable local—so
	function plans, place plans, reports, and syntax construction cannot silently
	choose different carriers. The admitted scope covers exact `Int` and `Bool`
	across internal values, local cells, and direct fields. Direct nominal
	`Array<Int>`, exact core `Null<Int>`, and exact core `Null<Bool>` remain
	local-only decisions. Exact core `String` uses the target's nullable string
	carrier across internal values, local cells, and direct fields.
**/
class OcamlRepresentationRegistry {
	public static inline final MODEL_REVISION = "ocaml-representation-v10";

	var currentProgramRevision:Null<String> = null;
	final decisionsByKey:StringMap<OcamlRepresentationDecision> = new StringMap();
	final decisionsById:StringMap<OcamlRepresentationDecision> = new StringMap();

	public function new() {}

	/** Starts one compilation request and discards every previous decision. */
	public function beginProgram(programRevision:String):Void {
		if (programRevision.length == 0)
			throw "reflaxe.ocaml [ocaml-representation:missing-program-revision]: the target-selected program revision is empty";
		currentProgramRevision = programRevision;
		decisionsByKey.clear();
		decisionsById.clear();
	}

	/** Returns whether a Haxe type is the exact, non-null built-in `Int`. */
	public static function isExactInt(type:Type):Bool {
		var current = type;
		var following = true;
		var depth = 0;
		while (following && depth < 32) {
			depth += 1;
			current = switch (current) {
				case TLazy(resolve): resolve();
				case TMono(reference):
					final resolved = reference.get();
					if (resolved == null) {
						following = false;
						current;
					} else {
						resolved;
					}
				case TType(typeRef, parameters):
					final typedefType = typeRef.get();
					TypeTools.applyTypeParameters(typedefType.type, typedefType.params, parameters);
				case _:
					following = false;
					current;
			}
		}
		if (following)
			return false;
		return switch (current) {
			case TAbstract(abstractRef, _): final abstractType = abstractRef.get(); abstractType.pack.length == 0 && abstractType.name == "Int";
			case _:
				false;
		}
	}

	/** Returns whether a Haxe type resolves to the non-null built-in `Bool`. */
	public static function isExactBool(type:Type):Bool {
		var current = type;
		var following = true;
		var depth = 0;
		while (following && depth < 32) {
			depth += 1;
			current = switch (current) {
				case TLazy(resolve): resolve();
				case TMono(reference):
					final resolved = reference.get();
					if (resolved == null) {
						following = false;
						current;
					} else {
						resolved;
					}
				case TType(typeRef, parameters):
					final typedefType = typeRef.get();
					TypeTools.applyTypeParameters(typedefType.type, typedefType.params, parameters);
				case _:
					following = false;
					current;
			}
		}
		if (following)
			return false;
		return switch (current) {
			case TAbstract(abstractRef, _): final abstractType = abstractRef.get(); abstractType.pack.length == 0 && abstractType.name == "Bool";
			case _:
				false;
		}
	}

	/**
		Returns whether a Haxe type is the direct nominal built-in `Array<Int>`.

		This deliberately does not follow typedefs, abstracts, `Vector`, nullable
		wrappers, or a generic element type. Those families need their own
		representation and conversion proofs.
	**/
	public static function isExactArrayInt(type:Type):Bool {
		return switch (type) {
			case TInst(classRef, [elementType]): final classType = classRef.get(); classType.pack.length == 0 && classType.name == "Array" && isExactInt(elementType);
			case _:
				false;
		}
	}

	/**
		Returns whether a type is exactly the core `Null<Int>` representation.

		Typedefs, user abstracts, monomorphs, and other nullable primitive families
		are intentionally excluded. Their carrier or conversion proof can differ.
	**/
	public static function isExactNullInt(type:Type):Bool {
		return isExactCoreNullablePrimitive(type, "Int");
	}

	/**
		Returns whether a type is exactly the core `Null<Bool>` representation.

		Like exact `Null<Int>`, this deliberately rejects typedef and user-abstract
		wrappers. Their boundary behavior needs a separate representation proof.
	**/
	public static function isExactNullBool(type:Type):Bool {
		return isExactCoreNullablePrimitive(type, "Bool");
	}

	/**
		Returns whether a type is the direct built-in `String` class.

		The predicate intentionally does not follow typedefs, user abstracts,
		generic parameters, or `Dynamic`. Those families can require different
		interop and null-boundary rules.
	**/
	public static function isExactString(type:Type):Bool {
		return switch (type) {
			case TInst(classRef, _): final classType = classRef.get(); classType.pack.length == 0 && classType.name == "String";
			case _:
				false;
		}
	}

	/**
		Returns whether Haxe wrapped the direct built-in `String` class in its
		core `Null` abstract.

		This predicate does not select a separate `Null<String>` representation.
		It lets call-boundary planning recognize the macro type of `?value:String`
		and deliberately map that optional parameter to the existing exact String
		carrier and its runtime null sentinel.
	**/
	public static function isExactNullString(type:Type):Bool {
		return switch (type) {
			case TAbstract(abstractRef, [TInst(classRef, _)]):
				final abstractType = abstractRef.get();
				final classType = classRef.get();
				abstractType.pack.length == 0
				&& abstractType.name == "Null"
				&& classType.pack.length == 0
				&& classType.name == "String";
			case _:
				false;
		}
	}

	/** Registers or reuses the canonical direct carrier for exact Haxe `Int`. */
	public function selectExactInt(domain:OcamlRepresentationDomain):OcamlRepresentationDecision {
		final storageMutationPolicy = switch (domain) {
			case InternalValue: OcamlRepresentationStorageMutationPolicy.ImmutableBinding;
			case MutableLocalStorage, CapturedLocalStorage: OcamlRepresentationStorageMutationPolicy.SharedLocalCell;
			case InstanceField: OcamlRepresentationStorageMutationPolicy.InstanceFieldOwner;
			case StaticField: OcamlRepresentationStorageMutationPolicy.StaticFieldOwner;
			case ArrayElement: OcamlRepresentationStorageMutationPolicy.ArrayElementOwner;
		}
		return register({
			semanticTypeId: "Int",
			domain: domain,
			carrierTypeId: "int",
			nullPolicy: OcamlRepresentationNullPolicy.NonNull,
			identityPolicy: OcamlRepresentationIdentityPolicy.PrimitiveValue,
			aliasingPolicy: OcamlRepresentationAliasingPolicy.NoValueAlias,
			storageMutationPolicy: storageMutationPolicy,
			valueMutationPolicy: OcamlRepresentationValueMutationPolicy.ImmutableValue,
			boxingPolicy: OcamlRepresentationBoxingPolicy.DirectUnboxed,
			implicitDefaultPolicy: OcamlRepresentationImplicitDefaultPolicy.ExactIntZero,
			reason: exactIntReason(domain),
			proof: {
				id: "direct-exact-int-storage-64-v1",
				claim: "On the currently tested 64-bit OCaml hosts, every signed 32-bit Haxe Int value fits exactly in OCaml int. This proves storage and pass-through only: overflow-sensitive and bit-pattern-sensitive operations still require HxInt, and this proof does not admit a 32-bit OCaml target."
			},
			profileEligibility: ["metal", "portable"]
		});
	}

	/**
		Registers or reuses the direct carrier for exact Haxe `Bool`.

		This bounded decision covers function-internal values, local cells, and
		direct instance/static field storage. Array elements, calls, and ABI
		boundaries remain outside the proof.
	**/
	public function selectExactBool(domain:OcamlRepresentationDomain):OcamlRepresentationDecision {
		final storageMutationPolicy = switch (domain) {
			case InternalValue: OcamlRepresentationStorageMutationPolicy.ImmutableBinding;
			case MutableLocalStorage, CapturedLocalStorage: OcamlRepresentationStorageMutationPolicy.SharedLocalCell;
			case InstanceField: OcamlRepresentationStorageMutationPolicy.InstanceFieldOwner;
			case StaticField: OcamlRepresentationStorageMutationPolicy.StaticFieldOwner;
			case ArrayElement:
				throw 'reflaxe.ocaml [ocaml-representation:unsupported-bool-domain]: exact Bool is admitted only for internal, local, instance-field, or static-field storage, not $domain';
		};
		return register({
			semanticTypeId: "Bool",
			domain: domain,
			carrierTypeId: "bool",
			nullPolicy: OcamlRepresentationNullPolicy.NonNull,
			identityPolicy: OcamlRepresentationIdentityPolicy.PrimitiveValue,
			aliasingPolicy: OcamlRepresentationAliasingPolicy.NoValueAlias,
			storageMutationPolicy: storageMutationPolicy,
			valueMutationPolicy: OcamlRepresentationValueMutationPolicy.ImmutableValue,
			boxingPolicy: OcamlRepresentationBoxingPolicy.DirectUnboxed,
			implicitDefaultPolicy: OcamlRepresentationImplicitDefaultPolicy.ExactBoolFalse,
			reason: exactBoolReason(domain),
			proof: {
				id: "direct-exact-bool-storage-v2",
				claim: "The OCaml bool carrier represents the two exact non-null Haxe Bool values directly. The selected binding, local cell, instance field, or static cell owns replacement; this proof does not admit nullable values, array elements, calls, operators, native boundaries, or public ABI."
			},
			profileEligibility: ["metal", "portable"]
		});
	}

	/**
		Registers or reuses the direct local carrier for nominal `Array<Int>`.

		Immutable, mutable-local, and captured-local storage use the same runtime
		array carrier but different storage owners. Fields, generic arrays, and ABI
		crossings remain on their existing paths.
	**/
	public function selectExactArrayInt(domain:OcamlRepresentationDomain):OcamlRepresentationDecision {
		final storageMutationPolicy = switch (domain) {
			case InternalValue: OcamlRepresentationStorageMutationPolicy.ImmutableBinding;
			case MutableLocalStorage, CapturedLocalStorage: OcamlRepresentationStorageMutationPolicy.SharedLocalCell;
			case InstanceField, StaticField, ArrayElement:
				throw 'reflaxe.ocaml [ocaml-representation:unsupported-array-int-domain]: exact Array<Int> is admitted only for internal, mutable-local, or captured-local storage, not $domain';
		};
		return register({
			semanticTypeId: "Array<Int>",
			domain: domain,
			carrierTypeId: "int HxArray.t",
			nullPolicy: OcamlRepresentationNullPolicy.RuntimeSentinel,
			identityPolicy: OcamlRepresentationIdentityPolicy.ReferenceIdentity,
			aliasingPolicy: OcamlRepresentationAliasingPolicy.SharedReferenceAliases,
			storageMutationPolicy: storageMutationPolicy,
			valueMutationPolicy: OcamlRepresentationValueMutationPolicy.MutableRuntimeContainer,
			boxingPolicy: OcamlRepresentationBoxingPolicy.DirectRuntimeContainer,
			implicitDefaultPolicy: OcamlRepresentationImplicitDefaultPolicy.NotAdmitted,
			reason: exactArrayIntReason(domain),
			proof: {
				id: "direct-array-int-reference-carrier-v2",
				claim: "HxArray.t is the target runtime's mutable reference-bearing array container. The surrounding binding or ref cell owns replacement of the whole carrier, while the carrier owns shared element mutation. Reusing that exact carrier preserves reference identity and aliases; Haxe null remains a separately converted runtime sentinel. This proof does not admit generic, nullable, typedef, abstract, Vector, field, or ABI representations."
			},
			profileEligibility: ["metal", "portable"]
		});
	}

	/**
		Registers the nullable primitive carrier used by exact `Null<Int>` storage.

		The representation decision owns the carrier only. The function-local
		conversion plan separately proves whether each occurrence preserves the
		carrier, boxes an exact Int, or performs a checked non-null read. Field
		assignment conversions remain outside this storage/default decision.
	**/
	public function selectExactNullInt(domain:OcamlRepresentationDomain):OcamlRepresentationDecision {
		requireNullablePrimitiveDomain(domain, "Null<Int>");
		return selectExactNullablePrimitive(domain, "Null<Int>", exactNullIntReason(domain), {
			id: "nullable-int-obj-carrier-v2",
			claim: "One Obj.t carrier can distinguish HxRuntime.hx_null from every boxed OCaml int that represents a Haxe Int. It owns internal/local/field storage and implicit null defaults only. Occurrence-bound proofs remain required for sentinel preservation, exact-Int boxing, checked non-null reads, and field writes; this does not admit other Null<T> families, calls, or ABI crossings."
		});
	}

	/**
		Registers the nullable primitive carrier used by exact `Null<Bool>` storage.

		The stored carrier preserves null, false, and true as distinct values.
		Function-local occurrence plans separately prove carrier-preserving writes,
		exact-Bool boxing, and Haxe condition truthiness.
	**/
	public function selectExactNullBool(domain:OcamlRepresentationDomain):OcamlRepresentationDecision {
		requireNullablePrimitiveDomain(domain, "Null<Bool>");
		return selectExactNullablePrimitive(domain, "Null<Bool>", exactNullBoolReason(domain), {
			id: "nullable-bool-obj-carrier-v2",
			claim: "One Obj.t carrier preserves HxRuntime.hx_null, Obj.repr false, and Obj.repr true as three distinct Haxe Null<Bool> values. It owns internal/local/field storage and implicit null defaults only. Occurrence-bound proofs must own every carrier-preserving copy, exact-Bool box, condition-truthiness read, and field write; this does not admit calls, concrete-Bool boundaries, ABI crossings, or other Null<T> families."
		});
	}

	/**
		Registers the nullable direct carrier used by exact core `String`.

		Haxe 4.3.7 initializes omitted String storage to null, while OCaml
		`string` has no null constructor. The selected proof therefore admits one
		narrow unsafe operation: the materializer may cast the canonical runtime
		sentinel into the string carrier for an implicit default. Non-null strings
		and admitted Haxe-to-Haxe call boundaries stay direct.
	**/
	public function selectExactString(domain:OcamlRepresentationDomain):OcamlRepresentationDecision {
		final storageMutationPolicy = switch (domain) {
			case InternalValue: OcamlRepresentationStorageMutationPolicy.ImmutableBinding;
			case MutableLocalStorage, CapturedLocalStorage: OcamlRepresentationStorageMutationPolicy.SharedLocalCell;
			case InstanceField: OcamlRepresentationStorageMutationPolicy.InstanceFieldOwner;
			case StaticField: OcamlRepresentationStorageMutationPolicy.StaticFieldOwner;
			case ArrayElement:
				throw 'reflaxe.ocaml [ocaml-representation:unsupported-string-domain]: exact String is admitted only for internal, local, instance-field, or static-field storage, not $domain';
		};
		return register({
			semanticTypeId: "String",
			domain: domain,
			carrierTypeId: "string",
			nullPolicy: OcamlRepresentationNullPolicy.RuntimeSentinel,
			identityPolicy: OcamlRepresentationIdentityPolicy.PrimitiveValue,
			aliasingPolicy: OcamlRepresentationAliasingPolicy.NoValueAlias,
			storageMutationPolicy: storageMutationPolicy,
			valueMutationPolicy: OcamlRepresentationValueMutationPolicy.ImmutableValue,
			boxingPolicy: OcamlRepresentationBoxingPolicy.NullableStringCarrier,
			implicitDefaultPolicy: OcamlRepresentationImplicitDefaultPolicy.RuntimeNullSentinel,
			reason: exactStringReason(domain),
			proof: {
				id: "nullable-string-runtime-sentinel-carrier-v1",
				claim: "Exact Haxe String uses OCaml string for non-null values and preserves the canonical Haxe null sentinel through the single runtime-owned HxString.hx_null_string value. Generated storage and expressions reference that value instead of creating occurrence-local Obj.magic casts. HxString.equals checks the sentinel before native string equality. This proof does not admit typedefs, abstracts, Dynamic, native ABI crossings, array elements, or arbitrary class carriers."
			},
			profileEligibility: ["metal", "portable"]
		});
	}

	function selectExactNullablePrimitive(domain:OcamlRepresentationDomain, semanticTypeId:String, reason:String,
			proof:OcamlRepresentationProof):OcamlRepresentationDecision {
		final storageMutationPolicy = switch (domain) {
			case InternalValue: OcamlRepresentationStorageMutationPolicy.ImmutableBinding;
			case MutableLocalStorage, CapturedLocalStorage: OcamlRepresentationStorageMutationPolicy.SharedLocalCell;
			case InstanceField: OcamlRepresentationStorageMutationPolicy.InstanceFieldOwner;
			case StaticField: OcamlRepresentationStorageMutationPolicy.StaticFieldOwner;
			case ArrayElement:
				throw 'reflaxe.ocaml [ocaml-representation:unsupported-nullable-primitive-domain]: exact $semanticTypeId is admitted only for internal, local, instance-field, or static-field storage, not $domain';
		};
		return register({
			semanticTypeId: semanticTypeId,
			domain: domain,
			carrierTypeId: "Obj.t",
			nullPolicy: OcamlRepresentationNullPolicy.RuntimeSentinel,
			identityPolicy: OcamlRepresentationIdentityPolicy.PrimitiveValue,
			aliasingPolicy: OcamlRepresentationAliasingPolicy.NoValueAlias,
			storageMutationPolicy: storageMutationPolicy,
			valueMutationPolicy: OcamlRepresentationValueMutationPolicy.ImmutableValue,
			boxingPolicy: OcamlRepresentationBoxingPolicy.NullablePrimitiveCarrier,
			implicitDefaultPolicy: OcamlRepresentationImplicitDefaultPolicy.RuntimeNullSentinel,
			reason: reason,
			proof: proof,
			profileEligibility: ["metal", "portable"]
		});
	}

	/**
		Registers one complete choice or rejects a conflicting choice for its key.

		Keeping this operation general lets later semantic types join the same
		registry without adding another side table. Compiler paths call it through
		the closed semantic-family selectors above.
	**/
	public function register(selection:OcamlRepresentationSelection):OcamlRepresentationDecision {
		final programRevision = requireProgramRevision();
		validateSelection(selection);
		final canonical = canonicalSelection(selection);
		final key = decisionKey(canonical.semanticTypeId, canonical.domain);
		final id = "representation:" + canonical.semanticTypeId + ":" + (canonical.domain : String);
		final revision = "sha256:" + Sha256.encode(selectionFingerprint(canonical));
		final candidate:OcamlRepresentationDecision = {
			id: id,
			key: key,
			programRevision: programRevision,
			revision: revision,
			semanticTypeId: canonical.semanticTypeId,
			domain: canonical.domain,
			carrierTypeId: canonical.carrierTypeId,
			nullPolicy: canonical.nullPolicy,
			identityPolicy: canonical.identityPolicy,
			aliasingPolicy: canonical.aliasingPolicy,
			storageMutationPolicy: canonical.storageMutationPolicy,
			valueMutationPolicy: canonical.valueMutationPolicy,
			boxingPolicy: canonical.boxingPolicy,
			implicitDefaultPolicy: canonical.implicitDefaultPolicy,
			reason: canonical.reason,
			proof: canonical.proof,
			profileEligibility: canonical.profileEligibility
		};
		final existing = decisionsByKey.get(key);
		if (existing != null) {
			if (existing.revision != candidate.revision) {
				throw 'reflaxe.ocaml [ocaml-representation:conflicting-decision]: "$key" was already assigned ${existing.carrierTypeId} (${existing.revision}), so it cannot also use ${candidate.carrierTypeId} (${candidate.revision})';
			}
			return copyDecision(existing);
		}
		if (decisionsById.exists(id))
			throw 'reflaxe.ocaml [ocaml-representation:duplicate-identity]: representation identity "$id" belongs to more than one key';
		decisionsByKey.set(key, candidate);
		decisionsById.set(id, candidate);
		return copyDecision(candidate);
	}

	/** Resolves one decision only inside the program revision that selected it. */
	public function require(representationId:String, expectedProgramRevision:String):OcamlRepresentationDecision {
		final actualProgramRevision = requireProgramRevision();
		if (expectedProgramRevision != actualProgramRevision) {
			throw 'reflaxe.ocaml [ocaml-representation:stale-program-revision]: representation "$representationId" was requested for $expectedProgramRevision, but the registry belongs to $actualProgramRevision';
		}
		final decision = decisionsById.get(representationId);
		if (decision == null)
			throw 'reflaxe.ocaml [ocaml-representation:missing-decision]: no representation decision exists for "$representationId"';
		return copyDecision(decision);
	}

	/** Returns every decision in deterministic identity order. */
	public function decisions():Array<OcamlRepresentationDecision> {
		final ids = [for (id in decisionsById.keys()) id];
		ids.sort(Reflect.compare);
		return [for (id in ids) copyDecision(cast decisionsById.get(id))];
	}

	/** Returns a deterministic digest of the program's current decisions. */
	public function revision():String {
		return "sha256:" + Sha256.encode(decisions().map(decision -> decision.id + "|" + decision.revision).join("\n"));
	}

	static function decisionKey(semanticTypeId:String, domain:OcamlRepresentationDomain):String {
		return semanticTypeId + "|" + (domain : String);
	}

	static function exactIntReason(domain:OcamlRepresentationDomain):String {
		return switch (domain) {
			case InternalValue: "An exact, non-null Haxe Int uses OCaml int directly; a later value is represented by a newer immutable binding.";
			case MutableLocalStorage: "An exact, non-null Haxe Int uses OCaml int directly inside the mutable local cell selected by the function plan.";
			case CapturedLocalStorage: "An exact, non-null Haxe Int uses OCaml int directly inside the one local cell shared with nested functions.";
			case InstanceField: "An exact, non-null Haxe Int uses OCaml int directly; the enclosing instance field owns mutation.";
			case StaticField: "An exact, non-null Haxe Int uses OCaml int directly inside the static field's OCaml ref cell.";
			case ArrayElement: "An exact, non-null Haxe Int uses OCaml int directly; the enclosing Haxe array owns element mutation.";
		}
	}

	static function exactBoolReason(domain:OcamlRepresentationDomain):String {
		return switch (domain) {
			case InternalValue: "An exact, non-null Haxe Bool local uses OCaml bool directly; a later value is represented by a newer immutable binding.";
			case MutableLocalStorage: "An exact, non-null Haxe Bool uses OCaml bool directly inside the mutable local cell selected by the function plan.";
			case CapturedLocalStorage: "An exact, non-null Haxe Bool uses OCaml bool directly inside the one local cell shared with nested functions.";
			case InstanceField: "An exact, non-null Haxe Bool uses OCaml bool directly; the enclosing instance field owns mutation.";
			case StaticField: "An exact, non-null Haxe Bool uses OCaml bool directly inside the static field's OCaml ref cell.";
			case ArrayElement:
				throw 'reflaxe.ocaml [ocaml-representation:unsupported-bool-domain]: no exact Bool storage reason exists for $domain';
		}
	}

	static function exactArrayIntReason(domain:OcamlRepresentationDomain):String {
		return switch (domain) {
			case InternalValue:
				"An exact Array<Int> immutable binding stores the direct HxArray container; aliases share its element mutations while a later source assignment creates a newer binding.";
			case MutableLocalStorage:
				"An exact Array<Int> mutable local stores the direct HxArray container in one ref cell; the cell owns whole-array replacement and each HxArray owns shared element mutation.";
			case CapturedLocalStorage:
				"An exact Array<Int> captured local stores the direct HxArray container in the ref cell shared with nested functions; the cell owns replacement and each HxArray owns shared element mutation.";
			case InstanceField, StaticField, ArrayElement:
				throw 'reflaxe.ocaml [ocaml-representation:unsupported-array-int-domain]: no exact Array<Int> local reason exists for $domain';
		}
	}

	static function exactNullIntReason(domain:OcamlRepresentationDomain):String {
		return switch (domain) {
			case InternalValue:
				"An exact Null<Int> immutable binding uses Obj.t so one carrier can preserve Haxe null and boxed Int values across source rebindings.";
			case MutableLocalStorage:
				"An exact Null<Int> mutable local stores its Obj.t carrier in one ref cell; the cell owns replacement while occurrence plans own boxing and checked reads.";
			case CapturedLocalStorage:
				"An exact Null<Int> captured local stores its Obj.t carrier in the ref cell shared with nested functions; occurrence plans own every carrier crossing.";
			case InstanceField:
				"An exact Null<Int> instance field stores Haxe null or a boxed Int in Obj.t; the field owns replacement and its omitted default is HxRuntime.hx_null.";
			case StaticField:
				"An exact Null<Int> static field stores Haxe null or a boxed Int in one Obj.t ref cell; the cell owns replacement and its omitted default is HxRuntime.hx_null.";
			case ArrayElement:
				throw 'reflaxe.ocaml [ocaml-representation:unsupported-null-int-domain]: no exact Null<Int> storage reason exists for $domain';
		}
	}

	static function exactNullBoolReason(domain:OcamlRepresentationDomain):String {
		return switch (domain) {
			case InternalValue:
				"An exact Null<Bool> immutable binding uses Obj.t so stored null remains distinct from boxed false and boxed true.";
			case MutableLocalStorage:
				"An exact Null<Bool> mutable local stores its Obj.t carrier in one ref cell; the cell owns replacement while occurrence plans own boxing and condition truthiness.";
			case CapturedLocalStorage:
				"An exact Null<Bool> captured local stores its Obj.t carrier in the ref cell shared with nested functions; occurrence plans preserve all three stored states and own truthiness reads.";
			case InstanceField:
				"An exact Null<Bool> instance field stores Haxe null, boxed false, or boxed true in Obj.t; the field owns replacement and its omitted default is HxRuntime.hx_null.";
			case StaticField:
				"An exact Null<Bool> static field stores Haxe null, boxed false, or boxed true in one Obj.t ref cell; the cell owns replacement and its omitted default is HxRuntime.hx_null.";
			case ArrayElement:
				throw 'reflaxe.ocaml [ocaml-representation:unsupported-null-bool-domain]: no exact Null<Bool> storage reason exists for $domain';
		}
	}

	static function exactStringReason(domain:OcamlRepresentationDomain):String {
		return switch (domain) {
			case InternalValue:
				"An exact Haxe String internal value uses the nullable OCaml string carrier; non-null values are direct and the canonical null sentinel is materialized only through the sealed proof.";
			case MutableLocalStorage:
				"An exact Haxe String mutable local stores the nullable string carrier in one ref cell; the cell owns replacement and the sealed representation owns its implicit null default.";
			case CapturedLocalStorage:
				"An exact Haxe String captured local stores the nullable string carrier in the ref cell shared with nested functions; the sealed representation owns its implicit null default.";
			case InstanceField:
				"An exact Haxe String instance field uses the nullable string carrier and starts at the canonical Haxe null sentinel when no initializer is present.";
			case StaticField:
				"An exact Haxe String static field uses the nullable string carrier in one ref cell and starts at the canonical Haxe null sentinel when no initializer is present.";
			case ArrayElement:
				throw 'reflaxe.ocaml [ocaml-representation:unsupported-string-domain]: no exact String storage reason exists for $domain';
		}
	}

	static function isExactCoreNullablePrimitive(type:Type, primitiveName:String):Bool {
		return switch (type) {
			case TAbstract(abstractRef, [TAbstract(innerRef, _)]):
				final abstractType = abstractRef.get();
				final innerType = innerRef.get();
				abstractType.pack.length == 0
				&& abstractType.name == "Null"
				&& innerType.pack.length == 0
				&& innerType.name == primitiveName;
			case _:
				false;
		}
	}

	static function requireNullablePrimitiveDomain(domain:OcamlRepresentationDomain, semanticTypeId:String):Void {
		switch (domain) {
			case InternalValue, MutableLocalStorage, CapturedLocalStorage, InstanceField, StaticField:
			case ArrayElement:
				throw 'reflaxe.ocaml [ocaml-representation:unsupported-nullable-primitive-domain]: exact $semanticTypeId is admitted only for internal, local, instance-field, or static-field storage, not $domain';
		}
	}

	function requireProgramRevision():String {
		if (currentProgramRevision == null)
			throw "reflaxe.ocaml [ocaml-representation:program-not-started]: beginProgram must run before selecting or resolving representations";
		return currentProgramRevision;
	}

	static function validateSelection(selection:OcamlRepresentationSelection):Void {
		if (selection.semanticTypeId.length == 0 || selection.carrierTypeId.length == 0 || selection.reason.length == 0)
			throw "reflaxe.ocaml [ocaml-representation:invalid-decision]: semantic type, carrier, and reason must be non-empty";
		if (selection.proof.id.length == 0 || selection.proof.claim.length == 0)
			throw "reflaxe.ocaml [ocaml-representation:invalid-decision]: every decision needs a named proof and claim";
		if (selection.profileEligibility.length == 0)
			throw "reflaxe.ocaml [ocaml-representation:invalid-decision]: every decision needs at least one eligible profile";
	}

	static function canonicalSelection(selection:OcamlRepresentationSelection):OcamlRepresentationSelection {
		final profiles = selection.profileEligibility.copy();
		profiles.sort(Reflect.compare);
		final uniqueProfiles:Array<String> = [];
		for (profile in profiles) {
			if (uniqueProfiles.length == 0 || uniqueProfiles[uniqueProfiles.length - 1] != profile)
				uniqueProfiles.push(profile);
		}
		return {
			semanticTypeId: selection.semanticTypeId,
			domain: selection.domain,
			carrierTypeId: selection.carrierTypeId,
			nullPolicy: selection.nullPolicy,
			identityPolicy: selection.identityPolicy,
			aliasingPolicy: selection.aliasingPolicy,
			storageMutationPolicy: selection.storageMutationPolicy,
			valueMutationPolicy: selection.valueMutationPolicy,
			boxingPolicy: selection.boxingPolicy,
			implicitDefaultPolicy: selection.implicitDefaultPolicy,
			reason: selection.reason,
			proof: {
				id: selection.proof.id,
				claim: selection.proof.claim
			},
			profileEligibility: uniqueProfiles
		};
	}

	static function selectionFingerprint(selection:OcamlRepresentationSelection):String {
		return [
			MODEL_REVISION,
			selection.semanticTypeId,
			(selection.domain : String),
			selection.carrierTypeId,
			(selection.nullPolicy : String),
			(selection.identityPolicy : String),
			(selection.aliasingPolicy : String),
			(selection.storageMutationPolicy : String),
			(selection.valueMutationPolicy : String),
			(selection.boxingPolicy : String),
			(selection.implicitDefaultPolicy : String),
			selection.reason,
			selection.proof.id,
			selection.proof.claim,
			selection.profileEligibility.join(",")
		].join("\n");
	}

	static function copyDecision(decision:OcamlRepresentationDecision):OcamlRepresentationDecision {
		return {
			id: decision.id,
			key: decision.key,
			programRevision: decision.programRevision,
			revision: decision.revision,
			semanticTypeId: decision.semanticTypeId,
			domain: decision.domain,
			carrierTypeId: decision.carrierTypeId,
			nullPolicy: decision.nullPolicy,
			identityPolicy: decision.identityPolicy,
			aliasingPolicy: decision.aliasingPolicy,
			storageMutationPolicy: decision.storageMutationPolicy,
			valueMutationPolicy: decision.valueMutationPolicy,
			boxingPolicy: decision.boxingPolicy,
			implicitDefaultPolicy: decision.implicitDefaultPolicy,
			reason: decision.reason,
			proof: {
				id: decision.proof.id,
				claim: decision.proof.claim
			},
			profileEligibility: decision.profileEligibility.copy()
		};
	}
}
#end
