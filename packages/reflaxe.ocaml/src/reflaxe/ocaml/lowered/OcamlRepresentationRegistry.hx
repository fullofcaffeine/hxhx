package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.ds.StringMap;
import haxe.macro.Type;
import haxe.macro.TypeTools;
import reflaxe.ocaml.lowered.OcamlBytesRepresentationModel.OcamlBytesRepresentationContract;
import reflaxe.ocaml.lowered.OcamlFloatRepresentationModel.OcamlFloatRepresentationContract;
import reflaxe.ocaml.lowered.OcamlInt64RepresentationModel.OcamlInt64RepresentationContract;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationAliasingPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationBoxingPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationIdentityPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationImplicitDefaultPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationNullPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlNormalizedRepresentedArray;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationProof;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentedArrayDescriptor;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationSelection;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationStorageMutationPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationValueMutationPolicy;
import reflaxe.ocaml.lowered.OcamlMonomorphicClassRepresentation.OcamlMonomorphicClassDecision;
import reflaxe.ocaml.lowered.OcamlMonomorphicClassRepresentation.OcamlMonomorphicClassField;

/**
	Owns the OCaml carrier selected for each admitted Haxe type and use domain.

	The registry is request-local. A decision answers a semantic question once—
	for example, how an exact non-null Haxe `Int` is stored in a mutable local—so
	function plans, place plans, reports, and syntax construction cannot silently
	choose different carriers. The admitted scope covers exact `Int` and `Bool`
	across internal values, local cells, and direct fields. Direct nominal
	`Array<Int>`, exact core `Null<Int>`, and exact core `Null<Bool>` remain
	local-only decisions. Exact non-null `Float` and `haxe.Int64` have narrowly
	bounded internal-value decisions for sealed Bytes binary operations. Direct
	`haxe.io.Bytes` and exact core
	`Null<haxe.io.Bytes>` have internal-value decisions that preserve their
	distinct typed forms while sharing one nullable reference carrier. Exact core
	`String` uses the target's nullable string carrier across internal values,
	local cells, direct fields, and the independently proved `ArrayElement`
	domain. An explicit host-neutral identity can compose that element decision
	into a dormant `Array<String>` descriptor, but the production Haxe-type
	normalizer and all array producers and consumers remain `Array<Int>`-only.
	Exact `Dynamic` uses one internal `Obj.t`
	carrier with occurrence-bound conversions that either preserve an existing
	Dynamic value or box one typed concrete value. A proven monomorphic class may
	additionally occupy one captured local cell when every whole-value replacement
	already produces that exact nominal carrier.
**/
class OcamlRepresentationRegistry {
	public static inline final MODEL_REVISION = "ocaml-representation-v21";
	public static inline final ARRAY_DESCRIPTOR_MODEL_REVISION = "ocaml-represented-array-v1";

	var currentProgramRevision:Null<String> = null;
	final decisionsByKey:StringMap<OcamlRepresentationDecision> = new StringMap();
	final decisionsById:StringMap<OcamlRepresentationDecision> = new StringMap();
	final representedArraysByKey:StringMap<OcamlRepresentedArrayDescriptor> = new StringMap();
	final representedArraysById:StringMap<OcamlRepresentedArrayDescriptor> = new StringMap();
	final monomorphicClassesBySemanticType:StringMap<OcamlMonomorphicClassDecision> = new StringMap();
	final monomorphicClassesById:StringMap<OcamlMonomorphicClassDecision> = new StringMap();

	public function new() {}

	/** Starts one compilation request and discards every previous decision. */
	public function beginProgram(programRevision:String):Void {
		if (programRevision.length == 0)
			throw "reflaxe.ocaml [ocaml-representation:missing-program-revision]: the target-selected program revision is empty";
		currentProgramRevision = programRevision;
		decisionsByKey.clear();
		decisionsById.clear();
		representedArraysByKey.clear();
		representedArraysById.clear();
		monomorphicClassesBySemanticType.clear();
		monomorphicClassesById.clear();
	}

	/**
		Selects an already admitted direct field representation.

		Returning null is deliberate: a monomorphic class is admitted only when
		every instance field already has an independently sealed carrier.
	**/
	public function selectAdmittedInstanceField(type:Type):Null<OcamlRepresentationDecision> {
		if (isExactInt(type))
			return selectExactInt(OcamlRepresentationDomain.InstanceField);
		if (isExactBool(type))
			return selectExactBool(OcamlRepresentationDomain.InstanceField);
		if (isExactNullInt(type))
			return selectExactNullInt(OcamlRepresentationDomain.InstanceField);
		if (isExactNullBool(type))
			return selectExactNullBool(OcamlRepresentationDomain.InstanceField);
		if (isExactString(type))
			return selectExactString(OcamlRepresentationDomain.InstanceField);
		return null;
	}

	/** Registers one exact monomorphic class layout before function planning. */
	public function registerMonomorphicClass(selection:{
		final semanticTypeId:String;
		final sourceModuleId:String;
		final sourceTypeName:String;
		final targetModuleName:String;
		final targetTypeName:String;
		final fields:Array<OcamlMonomorphicClassField>;
	}):OcamlMonomorphicClassDecision {
		final programRevision = requireProgramRevision();
		if (selection.semanticTypeId.length == 0
			|| selection.sourceModuleId.length == 0
			|| selection.sourceTypeName.length == 0
			|| selection.targetModuleName.length == 0
			|| selection.targetTypeName.length == 0) {
			throw "reflaxe.ocaml [ocaml-representation:invalid-class-layout]: class and nominal carrier identities must be non-empty";
		}
		final fields = selection.fields.map(copyMonomorphicField);
		fields.sort((left, right) -> left.declarationOrder - right.declarationOrder);
		for (index in 0...fields.length) {
			final field = fields[index];
			if (field.declarationOrder != index || field.sourceFieldName.length == 0 || field.targetFieldName.length == 0
				|| field.semanticTypeId.length == 0 || field.carrierTypeId.length == 0 || field.representationId.length == 0) {
				throw 'reflaxe.ocaml [ocaml-representation:invalid-class-layout]: ${selection.semanticTypeId} has an invalid field at declaration order $index';
			}
			final representation = require(field.representationId, programRevision);
			if (representation.semanticTypeId != field.semanticTypeId
				|| representation.carrierTypeId != field.carrierTypeId
				|| representation.domain != OcamlRepresentationDomain.InstanceField) {
				throw 'reflaxe.ocaml [ocaml-representation:class-field-mismatch]: ${selection.semanticTypeId}.${field.sourceFieldName} expects ${field.semanticTypeId} -> ${field.carrierTypeId}, but ${representation.id} selects ${representation.semanticTypeId} -> ${representation.carrierTypeId} in ${representation.domain}';
			}
		}
		final canonicalCarrierTypeId = selection.targetModuleName + "." + selection.targetTypeName;
		final layoutFingerprint = [
			MODEL_REVISION,
			selection.semanticTypeId,
			selection.sourceModuleId,
			selection.sourceTypeName,
			selection.targetModuleName,
			selection.targetTypeName,
			canonicalCarrierTypeId,
			"__hx_type|Obj.t"
		].concat(fields.map(field -> [
			Std.string(field.declarationOrder),
			field.sourceFieldName,
			field.targetFieldName,
			field.semanticTypeId,
			field.carrierTypeId,
			field.representationId
		].join("|"))).join("\n");
		final revision = "sha256:" + Sha256.encode(layoutFingerprint);
		final id = "class-layout:" + selection.semanticTypeId;
		final decision:OcamlMonomorphicClassDecision = {
			id: id,
			key: selection.semanticTypeId,
			programRevision: programRevision,
			revision: revision,
			semanticTypeId: selection.semanticTypeId,
			sourceModuleId: selection.sourceModuleId,
			sourceTypeName: selection.sourceTypeName,
			targetModuleName: selection.targetModuleName,
			targetTypeName: selection.targetTypeName,
			canonicalCarrierTypeId: canonicalCarrierTypeId,
			fields: fields,
			proofId: "whole-program-monomorphic-nominal-record-v1",
			proofClaim: "The complete typed program contains one concrete non-extern, non-generic class with no base class, subclass, interface, or dynamic method. Its exact declared fields already have sealed carriers, so constructor results and proven same-class locals can share one nominal OCaml record payload without a hierarchy or interface cast."
		};
		final existing = monomorphicClassesBySemanticType.get(selection.semanticTypeId);
		if (existing != null) {
			if (existing.revision != decision.revision)
				throw 'reflaxe.ocaml [ocaml-representation:conflicting-class-layout]: ${selection.semanticTypeId} was already assigned ${existing.revision}, so it cannot also use ${decision.revision}';
			selectMonomorphicClassDecision(existing, OcamlRepresentationDomain.InternalValue);
			return copyMonomorphicClass(existing);
		}
		if (monomorphicClassesById.exists(id))
			throw 'reflaxe.ocaml [ocaml-representation:duplicate-class-layout]: class layout identity "$id" belongs to more than one semantic type';
		monomorphicClassesBySemanticType.set(selection.semanticTypeId, decision);
		monomorphicClassesById.set(id, decision);
		selectMonomorphicClassDecision(decision, OcamlRepresentationDomain.InternalValue);
		return copyMonomorphicClass(decision);
	}

	/** Returns the admitted exact class layout for a direct Haxe instance type. */
	public function monomorphicClassForType(type:Type):Null<OcamlMonomorphicClassDecision> {
		final semanticTypeId = monomorphicClassSemanticTypeId(type);
		if (semanticTypeId == null)
			return null;
		final decision = monomorphicClassesBySemanticType.get(semanticTypeId);
		return decision == null ? null : copyMonomorphicClass(decision);
	}

	/** Returns the admitted exact class layout by canonical Haxe semantic type. */
	public function monomorphicClass(semanticTypeId:String):Null<OcamlMonomorphicClassDecision> {
		final decision = monomorphicClassesBySemanticType.get(semanticTypeId);
		return decision == null ? null : copyMonomorphicClass(decision);
	}

	/**
		Selects the nominal record carrier for one proven monomorphic class value.

		The admitted slice includes immutable internal bindings and one captured
		local cell whose replacements are all exact constructors or already-proven
		values of the same class. Ordinary mutable cells, fields containing class
		values, arrays, calls, and external boundaries need separate occurrence or
		conversion proofs.
	**/
	public function selectMonomorphicClassValue(type:Type, domain:OcamlRepresentationDomain):Null<OcamlRepresentationDecision> {
		final layout = monomorphicClassForType(type);
		if (layout == null)
			return null;
		return selectMonomorphicClassDecision(layout, domain);
	}

	/** Resolves the preplanned internal representation for one admitted class. */
	public function monomorphicClassValue(semanticTypeId:String):Null<OcamlRepresentationDecision> {
		if (!monomorphicClassesBySemanticType.exists(semanticTypeId))
			return null;
		final decision = decisionsByKey.get(decisionKey(semanticTypeId, OcamlRepresentationDomain.InternalValue));
		return decision == null ? null : copyDecision(decision);
	}

	function selectMonomorphicClassDecision(layout:OcamlMonomorphicClassDecision, domain:OcamlRepresentationDomain):OcamlRepresentationDecision {
		final storageMutationPolicy = switch (domain) {
			case InternalValue:
				OcamlRepresentationStorageMutationPolicy.ImmutableBinding;
			case CapturedLocalStorage:
				OcamlRepresentationStorageMutationPolicy.SharedLocalCell;
			case _:
				throw 'reflaxe.ocaml [ocaml-representation:unsupported-class-domain]: ${layout.semanticTypeId} is admitted only for immutable internal bindings or captured local cells, not $domain';
		};
		final reason = switch (domain) {
			case InternalValue:
				'The exact whole-program-monomorphic class ${layout.semanticTypeId} uses nominal record ${layout.canonicalCarrierTypeId}; the carrier identity stores ${layout.targetTypeName} plus its owning target module separately so syntax can qualify it correctly. This decision admits only constructor-produced and already-proven same-class internal values.';
			case CapturedLocalStorage:
				'The exact whole-program-monomorphic class ${layout.semanticTypeId} uses nominal record ${layout.canonicalCarrierTypeId} inside one captured local cell. The cell owns whole-value replacement while every initializer and assignment is separately proven to produce that same nominal record.';
			case _:
				throw "unreachable monomorphic class representation domain";
		};
		return register({
			semanticTypeId: layout.semanticTypeId,
			domain: domain,
			carrierTypeId: layout.targetTypeName,
			nullPolicy: OcamlRepresentationNullPolicy.RuntimeSentinel,
			identityPolicy: OcamlRepresentationIdentityPolicy.ReferenceIdentity,
			aliasingPolicy: OcamlRepresentationAliasingPolicy.SharedReferenceAliases,
			storageMutationPolicy: storageMutationPolicy,
			valueMutationPolicy: OcamlRepresentationValueMutationPolicy.MutableRuntimeContainer,
			boxingPolicy: OcamlRepresentationBoxingPolicy.NullableNominalRecordCarrier,
			implicitDefaultPolicy: OcamlRepresentationImplicitDefaultPolicy.NotAdmitted,
			reason: reason,
			proof: {
				id: layout.proofId + ":" + layout.revision,
				claim: layout.proofClaim
			},
			profileEligibility: ["metal", "portable"],
			nominalTargetModuleName: layout.targetModuleName,
			nominalTargetTypeName: layout.targetTypeName,
			nominalLayoutRevision: layout.revision
		});
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

	/**
		Returns whether a type is the exact, non-null built-in `Float`.

		Typedefs, nullable wrappers, user abstracts, monomorphs, and Dynamic are
		excluded because this predicate supports only the reviewed internal
		Bytes-call carrier.
	**/
	public static function isExactFloat(type:Type):Bool {
		return switch (type) {
			case TAbstract(abstractRef, parameters): final abstractType = abstractRef.get(); parameters.length == 0 && abstractType.pack.length == 0 && abstractType.name == OcamlFloatRepresentationContract.SEMANTIC_TYPE_ID;
			case _:
				false;
		}
	}

	/**
		Returns whether a type is the exact standard-library `haxe.Int64` abstract.

		The predicate keeps the nominal abstract visible instead of following it
		into its target-specific backing class. Typedefs, nullable wrappers, user
		abstracts, monomorphs, and Dynamic require separate representation proofs.
	**/
	public static function isExactInt64(type:Type):Bool {
		return switch (type) {
			case TAbstract(abstractRef, parameters):
				final abstractType = abstractRef.get();
				parameters.length == 0
				&& abstractType.pack.length == 1
				&& abstractType.pack[0] == "haxe"
				&& abstractType.name == "Int64";
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
		Normalizes one currently admitted direct array shape into plain values.

		This first hard cut recognizes only the existing direct `Array<Int>`
		family. Returning null for every other element or wrapper is deliberate:
		the caller cannot create a represented-array descriptor until the element
		has an independently proved `ArrayElement` representation.
	**/
	public static function normalizedDirectFlatArray(type:Type):Null<OcamlNormalizedRepresentedArray> {
		return switch (type) {
			case TInst(classRef, [elementType]):
				final classType = classRef.get();
				final directIntElement = switch (elementType) {
					case TAbstract(abstractRef, parameters): final abstractType = abstractRef.get(); parameters.length == 0 && abstractType.pack.length == 0 && abstractType.name == "Int";
					case _:
						false;
				};
				if (classType.pack.length == 0 && classType.name == "Array" && directIntElement) {
					{
						arraySemanticTypeId: "Array<Int>",
						elementSemanticTypeId: "Int",
						sourceForm: "direct-builtin-array",
						closureKind: "closed-monomorphic",
						outerWrapperKind: "none",
						nestingKind: "flat"
					};
				} else {
					null;
				}
			case _:
				null;
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
		Returns whether the typed value is Haxe `Dynamic` itself.

		Typedefs, monomorphs, and concrete values cast to Dynamic remain visible
		to the occurrence planner so it can prove the crossing rather than
		quietly classifying them as an existing Dynamic carrier.
	**/
	public static function isExactDynamic(type:Type):Bool {
		return switch (type) {
			case TDynamic(_): true;
			case _: false;
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

	/**
		Returns whether a type is the direct standard-library `haxe.io.Bytes`.

		This deliberately preserves the raw typed form. It does not follow the
		core `Null` abstract, typedefs, user abstracts, or monomorphs.
	**/
	public static function isExactBytes(type:Type):Bool {
		return switch (type) {
			case TInst(classRef, parameters):
				final classType = classRef.get();
				parameters.length == 0
				&& classType.pack != null
				&& classType.pack.length == 2
				&& classType.pack[0] == "haxe"
				&& classType.pack[1] == "io"
				&& classType.name == "Bytes";
			case _:
				false;
		}
	}

	/**
		Returns whether a type is the exact `haxe.io.BytesData` declaration.

		Upstream Haxe targets may expose that declaration as a typedef while the
		OCaml target override keeps it as an opaque abstract. Recognizing either
		raw declaration lets host-side planning and OCaml type mapping agree on
		the semantic argument without following into either target's native
		implementation.
	**/
	public static function isExactBytesData(type:Type):Bool {
		return switch (type) {
			case TAbstract(abstractRef, parameters):
				final abstractType = abstractRef.get();
				parameters.length == 0
				&& abstractType.pack != null
				&& abstractType.pack.length == 2
				&& abstractType.pack[0] == "haxe"
				&& abstractType.pack[1] == "io"
				&& abstractType.name == "BytesData";
			case TType(typeRef, parameters):
				final typedefType = typeRef.get();
				parameters.length == 0
				&& typedefType.pack != null
				&& typedefType.pack.length == 2
				&& typedefType.pack[0] == "haxe"
				&& typedefType.pack[1] == "io"
				&& typedefType.name == "BytesData";
			case _:
				false;
		}
	}

	/**
		Returns whether a type is exact core `Null<haxe.io.Bytes>`.

		Haxe reference values are nullable even without this wrapper. Keeping the
		explicit wrapper visible gives diagnostics and later conversion planning
		the source semantic identity without claiming a different runtime value
		set.
	**/
	public static function isExactNullBytes(type:Type):Bool {
		return switch (type) {
			case TAbstract(abstractRef, [inner]): final abstractType = abstractRef.get(); abstractType.pack.length == 0 && abstractType.name == "Null" && isExactBytes(inner);
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
		Registers the exact nominal value carrier for an internal `haxe.Int64`.

		This is deliberately narrower than a general Int64 storage decision.
		Bytes access needs to pass or return one already-typed value; nullable
		storage, fields, arrays, calls, and ABI boundaries remain separate work.
	**/
	public function selectExactInt64(domain:OcamlRepresentationDomain):OcamlRepresentationDecision {
		if (domain != OcamlRepresentationDomain.InternalValue) {
			throw 'reflaxe.ocaml [ocaml-representation:unsupported-int64-domain]: exact haxe.Int64 is admitted only as an internal value, not $domain';
		}
		return register({
			semanticTypeId: OcamlInt64RepresentationContract.SEMANTIC_TYPE_ID,
			domain: domain,
			carrierTypeId: OcamlInt64RepresentationContract.TARGET_TYPE_NAME,
			nullPolicy: OcamlRepresentationNullPolicy.NonNull,
			identityPolicy: OcamlRepresentationIdentityPolicy.PrimitiveValue,
			aliasingPolicy: OcamlRepresentationAliasingPolicy.NoValueAlias,
			storageMutationPolicy: OcamlRepresentationStorageMutationPolicy.ImmutableBinding,
			valueMutationPolicy: OcamlRepresentationValueMutationPolicy.ImmutableValue,
			boxingPolicy: OcamlRepresentationBoxingPolicy.DirectNominalValueCarrier,
			implicitDefaultPolicy: OcamlRepresentationImplicitDefaultPolicy.NotAdmitted,
			reason: OcamlInt64RepresentationContract.PROOF_CLAIM,
			proof: {
				id: OcamlInt64RepresentationContract.PROOF_ID,
				claim: OcamlInt64RepresentationContract.PROOF_CLAIM
			},
			profileEligibility: ["metal", "portable"],
			nominalTargetModuleName: OcamlInt64RepresentationContract.TARGET_MODULE_NAME,
			nominalTargetTypeName: OcamlInt64RepresentationContract.TARGET_TYPE_NAME,
			nominalLayoutRevision: OcamlInt64RepresentationContract.LAYOUT_REVISION
		});
	}

	/**
		Registers the direct carrier for one exact internal Haxe `Float`.

		The decision exists only for sealed Bytes binary I/O. General Float
		storage and behavior require separate review and occurrence proofs.
	**/
	public function selectExactFloat(domain:OcamlRepresentationDomain):OcamlRepresentationDecision {
		if (domain != OcamlRepresentationDomain.InternalValue) {
			throw 'reflaxe.ocaml [ocaml-representation:unsupported-float-domain]: exact Float is admitted only as an internal value, not $domain';
		}
		return register({
			semanticTypeId: OcamlFloatRepresentationContract.SEMANTIC_TYPE_ID,
			domain: domain,
			carrierTypeId: OcamlFloatRepresentationContract.CARRIER_TYPE_ID,
			nullPolicy: OcamlRepresentationNullPolicy.NonNull,
			identityPolicy: OcamlRepresentationIdentityPolicy.PrimitiveValue,
			aliasingPolicy: OcamlRepresentationAliasingPolicy.NoValueAlias,
			storageMutationPolicy: OcamlRepresentationStorageMutationPolicy.ImmutableBinding,
			valueMutationPolicy: OcamlRepresentationValueMutationPolicy.ImmutableValue,
			boxingPolicy: OcamlRepresentationBoxingPolicy.DirectUnboxed,
			implicitDefaultPolicy: OcamlRepresentationImplicitDefaultPolicy.NotAdmitted,
			reason: OcamlFloatRepresentationContract.PROOF_CLAIM,
			proof: {
				id: OcamlFloatRepresentationContract.PROOF_ID,
				claim: OcamlFloatRepresentationContract.PROOF_CLAIM
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
	public function selectRepresentedArray(type:Type, domain:OcamlRepresentationDomain):OcamlRepresentationDecision {
		final normalized = normalizedDirectFlatArray(type);
		if (normalized == null) {
			throw 'reflaxe.ocaml [ocaml-representation:unsupported-array-shape]: only a direct closed flat array with a proved ArrayElement representation is admitted';
		}
		return selectNormalizedRepresentedArray(normalized, domain);
	}

	/**
		Selects a representation from a host-neutral direct array identity.

		The descriptor is registered before the domain-specific representation so
		all later consumers can follow one revision-checked graph back to the exact
		element-storage decision.
	**/
	public function selectNormalizedRepresentedArray(normalized:OcamlNormalizedRepresentedArray, domain:OcamlRepresentationDomain):OcamlRepresentationDecision {
		final storageMutationPolicy = switch (domain) {
			case InternalValue: OcamlRepresentationStorageMutationPolicy.ImmutableBinding;
			case MutableLocalStorage, CapturedLocalStorage: OcamlRepresentationStorageMutationPolicy.SharedLocalCell;
			case InstanceField, StaticField, ArrayElement:
				throw 'reflaxe.ocaml [ocaml-representation:unsupported-array-domain]: a represented array is admitted only for internal, mutable-local, or captured-local storage, not $domain';
		};
		final elementRepresentation = switch (normalized.elementSemanticTypeId) {
			case "Int": selectExactInt(OcamlRepresentationDomain.ArrayElement);
			case "String": selectExactString(OcamlRepresentationDomain.ArrayElement);
			case _:
				throw 'reflaxe.ocaml [ocaml-representation:unsupported-array-element]: ${normalized.elementSemanticTypeId} has no admitted ArrayElement representation';
		};
		final descriptor = registerRepresentedArray(normalized, elementRepresentation);
		return register({
			semanticTypeId: descriptor.arraySemanticTypeId,
			domain: domain,
			carrierTypeId: descriptor.arrayCarrierTypeId,
			nullPolicy: OcamlRepresentationNullPolicy.RuntimeSentinel,
			identityPolicy: OcamlRepresentationIdentityPolicy.ReferenceIdentity,
			aliasingPolicy: OcamlRepresentationAliasingPolicy.SharedReferenceAliases,
			storageMutationPolicy: storageMutationPolicy,
			valueMutationPolicy: OcamlRepresentationValueMutationPolicy.MutableRuntimeContainer,
			boxingPolicy: OcamlRepresentationBoxingPolicy.DirectRuntimeContainer,
			implicitDefaultPolicy: OcamlRepresentationImplicitDefaultPolicy.NotAdmitted,
			reason: representedArrayReason(descriptor, domain),
			proof: {
				id: "direct-represented-array-reference-carrier-v1",
				claim: "The program-owned array descriptor binds one direct closed flat Haxe array to an exact ArrayElement representation and HxArray.t carrier. The surrounding binding or ref cell owns whole-array replacement while the carrier owns shared element mutation. This proof does not admit another element family, wrapper, nesting shape, field, call, return, typed catch, native boundary, or public ABI."
			},
			profileEligibility: descriptor.profileEligibility,
			arrayDescriptorId: descriptor.id,
			arrayDescriptorRevision: descriptor.revision
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
		sentinel into the string carrier for an implicit default. An array element
		uses that same nullable carrier, while `HxArray` owns sparse slots,
		out-of-bounds null reads, and storage-mode changes. This decision does not
		admit a represented `Array<String>`; a later descriptor must consume it
		explicitly.
	**/
	public function selectExactString(domain:OcamlRepresentationDomain):OcamlRepresentationDecision {
		final storageMutationPolicy = switch (domain) {
			case InternalValue: OcamlRepresentationStorageMutationPolicy.ImmutableBinding;
			case MutableLocalStorage, CapturedLocalStorage: OcamlRepresentationStorageMutationPolicy.SharedLocalCell;
			case InstanceField: OcamlRepresentationStorageMutationPolicy.InstanceFieldOwner;
			case StaticField: OcamlRepresentationStorageMutationPolicy.StaticFieldOwner;
			case ArrayElement: OcamlRepresentationStorageMutationPolicy.ArrayElementOwner;
		};
		final proof:OcamlRepresentationProof = switch (domain) {
			case ArrayElement:
				{
					id: "nullable-string-array-element-carrier-v1",
					claim: "Exact Haxe String array elements use the nullable string carrier. Non-null text remains direct, while the canonical Haxe null sentinel preserves explicit null values, sparse and out-of-bounds slots, and grow-resize holes through HxArray's observable operations. HxArray may change its private storage mode without changing values, order, length, or shared container identity. This proof does not admit an Array<String> descriptor, literal producer, local, call, return, throw, catch, native boundary, public ABI, typedef, abstract, generic, nested, or mixed array."
				};
			case _:
				{
					id: "nullable-string-runtime-sentinel-carrier-v1",
					claim: "Exact Haxe String uses OCaml string for non-null values and preserves the canonical Haxe null sentinel through the single runtime-owned HxString.hx_null_string value. Generated storage and expressions reference that value instead of creating occurrence-local Obj.magic casts. HxString.equals checks the sentinel before native string equality. This proof does not admit typedefs, abstracts, Dynamic, native ABI crossings, array elements, or arbitrary class carriers."
				};
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
			proof: proof,
			profileEligibility: ["metal", "portable"]
		});
	}

	/**
		Registers the heterogeneous carrier for one internal Haxe Dynamic value.

		This first slice admits immutable values and callable boundaries only.
		Mutable cells, fields, arrays, extern ABI storage, and implicit defaults
		need their own occurrence and ownership proofs.
	**/
	public function selectExactDynamic(domain:OcamlRepresentationDomain):OcamlRepresentationDecision {
		if (domain != OcamlRepresentationDomain.InternalValue) {
			throw 'reflaxe.ocaml [ocaml-representation:unsupported-dynamic-domain]: Dynamic is admitted only as an internal value, not $domain';
		}
		return register({
			semanticTypeId: "Dynamic",
			domain: domain,
			carrierTypeId: "Obj.t",
			nullPolicy: OcamlRepresentationNullPolicy.RuntimeSentinel,
			identityPolicy: OcamlRepresentationIdentityPolicy.DynamicPayloadIdentity,
			aliasingPolicy: OcamlRepresentationAliasingPolicy.DynamicPayloadAliases,
			storageMutationPolicy: OcamlRepresentationStorageMutationPolicy.ImmutableBinding,
			valueMutationPolicy: OcamlRepresentationValueMutationPolicy.DynamicPayloadMutation,
			boxingPolicy: OcamlRepresentationBoxingPolicy.DynamicCarrier,
			implicitDefaultPolicy: OcamlRepresentationImplicitDefaultPolicy.NotAdmitted,
			reason: "An internal Haxe Dynamic value uses Obj.t so one carrier can preserve the canonical null sentinel, primitive values, and existing reference-bearing payloads. Every concrete input crosses once through a separately sealed occurrence conversion; exact Bool uses the distinguishable runtime Bool box and other admitted concrete values use Obj.repr. Existing Dynamic carriers pass through unchanged.",
			proof: {
				id: "dynamic-obj-carrier-v1",
				claim: "OCaml Obj.repr embeds an already-produced non-Bool target value in Obj.t without rebuilding it; the runtime's Bool box keeps exact Bool distinguishable from OCaml Int. Primitive values retain their value, reference-bearing values retain their existing identity and aliases, and HxRuntime.hx_null already uses the same carrier. This proof covers immutable internal values and callable boundaries only."
			},
			profileEligibility: ["metal", "portable"]
		});
	}

	/**
		Selects the shared mutable runtime container for one sealed anonymous shape.

		`semanticTypeId` is the planner's canonical structural identity, not a
		printed Haxe type or a process-local macro object. The returned `Obj.t`
		carrier preserves one `HxAnon` table across local aliases. This method does
		not authorize field access by itself: each create, initialization, read, or
		write still needs its own occurrence plan and runtime requirement.
	**/
	public function selectAnonymousStructure(semanticTypeId:String):OcamlRepresentationDecision {
		if (semanticTypeId == null || !StringTools.startsWith(semanticTypeId, "anonymous{") || !StringTools.endsWith(semanticTypeId, "}"))
			throw 'reflaxe.ocaml [ocaml-representation:invalid-anonymous-shape]: "$semanticTypeId" is not a canonical anonymous-structure identity';
		return register({
			semanticTypeId: semanticTypeId,
			domain: OcamlRepresentationDomain.InternalValue,
			carrierTypeId: "Obj.t",
			nullPolicy: OcamlRepresentationNullPolicy.RuntimeSentinel,
			identityPolicy: OcamlRepresentationIdentityPolicy.ReferenceIdentity,
			aliasingPolicy: OcamlRepresentationAliasingPolicy.SharedReferenceAliases,
			storageMutationPolicy: OcamlRepresentationStorageMutationPolicy.ImmutableBinding,
			valueMutationPolicy: OcamlRepresentationValueMutationPolicy.MutableRuntimeContainer,
			boxingPolicy: OcamlRepresentationBoxingPolicy.DirectRuntimeContainer,
			implicitDefaultPolicy: OcamlRepresentationImplicitDefaultPolicy.NotAdmitted,
			reason: "An admitted anonymous literal creates one HxAnon runtime table. Copying the Obj.t carrier preserves that table's identity, so writes through one local alias remain visible through every other alias.",
			proof: {
				id: "anonymous-runtime-container-v1",
				claim: "The final typed shape has only fields admitted by the anonymous-structure planner and is not an iterator, key/value pair, sys.FileStat record, method-bearing structure, Dynamic crossing, or structural class conversion. One mutable HxAnon table therefore preserves construction order, reference identity, field mutation, and local aliasing for the bounded direct-literal slice."
			},
			profileEligibility: ["metal", "portable"]
		});
	}

	/**
		Selects the internal carrier for direct `haxe.io.Bytes`.

		The Haxe class type itself remains nullable. This decision fixes the
		carrier, reference identity, shared aliases, and in-container mutation; it
		does not authorize a null cast, storage default, receiver, or operation.
	**/
	public function selectExactBytes(domain:OcamlRepresentationDomain):OcamlRepresentationDecision {
		requireBytesInternalDomain(domain, OcamlBytesRepresentationContract.DIRECT_SEMANTIC_TYPE_ID);
		return selectBytesReferenceCarrier(OcamlBytesRepresentationContract.DIRECT_SEMANTIC_TYPE_ID, OcamlBytesRepresentationContract.DIRECT_PROOF_ID,
			'Direct haxe.io.Bytes is a nullable Haxe reference type. Non-null values use one mutable ${OcamlBytesRepresentationContract.CARRIER_TYPE_ID} container with shape ${OcamlBytesRepresentationContract.CARRIER_SHAPE_ID}: the declared Haxe length is stored separately from one ${OcamlBytesRepresentationContract.DATA_CARRIER_TYPE_ID} value, range-oriented operations use ${OcamlBytesRepresentationContract.RANGE_BOUNDS_POLICY}, and getData/ofData preserve a ${OcamlBytesRepresentationContract.DATA_ALIASING_POLICY}. Copies share the container and observe the same byte mutations. A separate occurrence proof must authorize every construction policy, runtime-null crossing, storage location, receiver, operation, or native boundary.');
	}

	/**
		Selects the target-native mutable carrier for exact `haxe.io.BytesData`.

		The OCaml standard-library override keeps this type opaque to portable
		Haxe while mapping it to the `bytes` value stored inside `HxBytes.t`.
		The representation records shared aliasing only; an occurrence plan must
		still authorize every producer, consumer, null crossing, or mutation.
	**/
	public function selectExactBytesData(domain:OcamlRepresentationDomain):OcamlRepresentationDecision {
		requireBytesInternalDomain(domain, OcamlBytesRepresentationContract.DATA_SEMANTIC_TYPE_ID);
		return register({
			semanticTypeId: OcamlBytesRepresentationContract.DATA_SEMANTIC_TYPE_ID,
			domain: OcamlRepresentationDomain.InternalValue,
			carrierTypeId: OcamlBytesRepresentationContract.DATA_CARRIER_TYPE_ID,
			nullPolicy: OcamlRepresentationNullPolicy.RuntimeSentinel,
			identityPolicy: OcamlRepresentationIdentityPolicy.ReferenceIdentity,
			aliasingPolicy: OcamlRepresentationAliasingPolicy.SharedReferenceAliases,
			storageMutationPolicy: OcamlRepresentationStorageMutationPolicy.ImmutableBinding,
			valueMutationPolicy: OcamlRepresentationValueMutationPolicy.MutableRuntimeContainer,
			boxingPolicy: OcamlRepresentationBoxingPolicy.DirectRuntimeContainer,
			implicitDefaultPolicy: OcamlRepresentationImplicitDefaultPolicy.NotAdmitted,
			reason: "Exact haxe.io.BytesData uses the mutable native bytes value stored inside HxBytes.t. getData and ofData may share this carrier without copying, so mutations remain visible through every alias. This proof does not admit null materialization, arbitrary indexing, storage defaults, calls, or native boundaries without a separate occurrence decision.",
			proof: {
				id: OcamlBytesRepresentationContract.DATA_PROOF_ID,
				claim: "The target-owned haxe.io.BytesData override denotes the mutable OCaml bytes value stored inside HxBytes.t. Reusing that exact carrier preserves reference identity and shared mutations; each operation still requires a revision-bound occurrence proof."
			},
			profileEligibility: ["metal", "portable"]
		});
	}

	/**
		Selects the internal carrier for exact core `Null<haxe.io.Bytes>`.

		The explicit core wrapper receives its own semantic identity even though
		Haxe gives it the same nullable reference value set and target carrier as
		direct `Bytes`.
	**/
	public function selectExactNullBytes(domain:OcamlRepresentationDomain):OcamlRepresentationDecision {
		requireBytesInternalDomain(domain, OcamlBytesRepresentationContract.EXPLICIT_NULL_SEMANTIC_TYPE_ID);
		return selectBytesReferenceCarrier(OcamlBytesRepresentationContract.EXPLICIT_NULL_SEMANTIC_TYPE_ID,
			OcamlBytesRepresentationContract.EXPLICIT_NULL_PROOF_ID,
			'Exact core Null<haxe.io.Bytes> preserves its explicit typed wrapper while using the same nullable Haxe reference value set and ${OcamlBytesRepresentationContract.CARRIER_SHAPE_ID} mutable carrier as direct Bytes. This decision records carrier shape, identity, and alias behavior only; construction, null materialization, storage, conversion, receivers, operations, and native boundaries remain unadmitted.');
	}

	function selectBytesReferenceCarrier(semanticTypeId:String, proofId:String, proofClaim:String):OcamlRepresentationDecision {
		return register({
			semanticTypeId: semanticTypeId,
			domain: OcamlRepresentationDomain.InternalValue,
			carrierTypeId: OcamlBytesRepresentationContract.CARRIER_TYPE_ID,
			nullPolicy: OcamlRepresentationNullPolicy.RuntimeSentinel,
			identityPolicy: OcamlRepresentationIdentityPolicy.ReferenceIdentity,
			aliasingPolicy: OcamlRepresentationAliasingPolicy.SharedReferenceAliases,
			storageMutationPolicy: OcamlRepresentationStorageMutationPolicy.ImmutableBinding,
			valueMutationPolicy: OcamlRepresentationValueMutationPolicy.MutableRuntimeContainer,
			boxingPolicy: OcamlRepresentationBoxingPolicy.DirectRuntimeContainer,
			implicitDefaultPolicy: OcamlRepresentationImplicitDefaultPolicy.NotAdmitted,
			reason: proofClaim,
			proof: {
				id: proofId,
				claim: proofClaim
			},
			profileEligibility: ["metal", "portable"]
		});
	}

	/**
		Revalidates one producer-owned direct Bytes representation reference.

		This lookup never creates a missing decision. Planning selects the
		decision; final sealing and syntax consumption can only verify the exact
		request-owned revision that was already registered.
	**/
	public function requireExactBytesInternal(representationId:String, representationRevision:String, programRevision:String):OcamlRepresentationDecision {
		final decision = require(representationId, programRevision);
		if (decision.id != OcamlBytesRepresentationContract.DIRECT_INTERNAL_REPRESENTATION_ID
			|| decision.revision != representationRevision
			|| decision.semanticTypeId != OcamlBytesRepresentationContract.DIRECT_SEMANTIC_TYPE_ID
			|| decision.carrierTypeId != OcamlBytesRepresentationContract.CARRIER_TYPE_ID
			|| decision.domain != OcamlRepresentationDomain.InternalValue
			|| decision.nullPolicy != OcamlRepresentationNullPolicy.RuntimeSentinel
			|| decision.identityPolicy != OcamlRepresentationIdentityPolicy.ReferenceIdentity
			|| decision.aliasingPolicy != OcamlRepresentationAliasingPolicy.SharedReferenceAliases
			|| decision.storageMutationPolicy != OcamlRepresentationStorageMutationPolicy.ImmutableBinding
			|| decision.valueMutationPolicy != OcamlRepresentationValueMutationPolicy.MutableRuntimeContainer
			|| decision.boxingPolicy != OcamlRepresentationBoxingPolicy.DirectRuntimeContainer
			|| decision.implicitDefaultPolicy != OcamlRepresentationImplicitDefaultPolicy.NotAdmitted
			|| decision.proof.id != OcamlBytesRepresentationContract.DIRECT_PROOF_ID) {
			throw 'reflaxe.ocaml [ocaml-bytes:representation-mismatch]: producer expects the sealed direct Bytes internal carrier, but "$representationId" selects incompatible facts';
		}
		return decision;
	}

	/**
		Revalidates one exact `Null<Bytes>` representation used as read input.

		The nullable semantic identity is preserved until a separate occurrence
		decision authorizes the Haxe-compatible non-null receiver check.
	**/
	public function requireExactNullBytesInternal(representationId:String, representationRevision:String, programRevision:String):OcamlRepresentationDecision {
		final decision = require(representationId, programRevision);
		if (decision.id != OcamlBytesRepresentationContract.EXPLICIT_NULL_INTERNAL_REPRESENTATION_ID
			|| decision.revision != representationRevision
			|| decision.semanticTypeId != OcamlBytesRepresentationContract.EXPLICIT_NULL_SEMANTIC_TYPE_ID
			|| decision.carrierTypeId != OcamlBytesRepresentationContract.CARRIER_TYPE_ID
			|| decision.domain != OcamlRepresentationDomain.InternalValue
			|| decision.nullPolicy != OcamlRepresentationNullPolicy.RuntimeSentinel
			|| decision.identityPolicy != OcamlRepresentationIdentityPolicy.ReferenceIdentity
			|| decision.aliasingPolicy != OcamlRepresentationAliasingPolicy.SharedReferenceAliases
			|| decision.storageMutationPolicy != OcamlRepresentationStorageMutationPolicy.ImmutableBinding
			|| decision.valueMutationPolicy != OcamlRepresentationValueMutationPolicy.MutableRuntimeContainer
			|| decision.boxingPolicy != OcamlRepresentationBoxingPolicy.DirectRuntimeContainer
			|| decision.implicitDefaultPolicy != OcamlRepresentationImplicitDefaultPolicy.NotAdmitted
			|| decision.proof.id != OcamlBytesRepresentationContract.EXPLICIT_NULL_PROOF_ID) {
			throw 'reflaxe.ocaml [ocaml-bytes:null-representation-mismatch]: nullable receiver planning expects the sealed Null<Bytes> internal carrier, but "$representationId" selects incompatible facts';
		}
		return decision;
	}

	/** Revalidates one exact target-owned `BytesData` representation reference. */
	public function requireExactBytesDataInternal(representationId:String, representationRevision:String, programRevision:String):OcamlRepresentationDecision {
		final decision = require(representationId, programRevision);
		if (decision.id != OcamlBytesRepresentationContract.DATA_INTERNAL_REPRESENTATION_ID
			|| decision.revision != representationRevision
			|| decision.semanticTypeId != OcamlBytesRepresentationContract.DATA_SEMANTIC_TYPE_ID
			|| decision.carrierTypeId != OcamlBytesRepresentationContract.DATA_CARRIER_TYPE_ID
			|| decision.domain != OcamlRepresentationDomain.InternalValue
			|| decision.nullPolicy != OcamlRepresentationNullPolicy.RuntimeSentinel
			|| decision.identityPolicy != OcamlRepresentationIdentityPolicy.ReferenceIdentity
			|| decision.aliasingPolicy != OcamlRepresentationAliasingPolicy.SharedReferenceAliases
			|| decision.storageMutationPolicy != OcamlRepresentationStorageMutationPolicy.ImmutableBinding
			|| decision.valueMutationPolicy != OcamlRepresentationValueMutationPolicy.MutableRuntimeContainer
			|| decision.boxingPolicy != OcamlRepresentationBoxingPolicy.DirectRuntimeContainer
			|| decision.implicitDefaultPolicy != OcamlRepresentationImplicitDefaultPolicy.NotAdmitted
			|| decision.proof.id != OcamlBytesRepresentationContract.DATA_PROOF_ID) {
			throw 'reflaxe.ocaml [ocaml-bytes:data-representation-mismatch]: access planning expects the sealed BytesData internal carrier, but "$representationId" selects incompatible facts';
		}
		return decision;
	}

	/** Revalidates the exact generated nominal record for one internal Int64. */
	public function requireExactInt64Internal(representationId:String, representationRevision:String, programRevision:String):OcamlRepresentationDecision {
		final decision = require(representationId, programRevision);
		if (decision.id != OcamlInt64RepresentationContract.INTERNAL_REPRESENTATION_ID
			|| decision.revision != representationRevision
			|| decision.semanticTypeId != OcamlInt64RepresentationContract.SEMANTIC_TYPE_ID
			|| decision.carrierTypeId != OcamlInt64RepresentationContract.TARGET_TYPE_NAME
			|| decision.domain != OcamlRepresentationDomain.InternalValue
			|| decision.nullPolicy != OcamlRepresentationNullPolicy.NonNull
			|| decision.identityPolicy != OcamlRepresentationIdentityPolicy.PrimitiveValue
			|| decision.aliasingPolicy != OcamlRepresentationAliasingPolicy.NoValueAlias
			|| decision.storageMutationPolicy != OcamlRepresentationStorageMutationPolicy.ImmutableBinding
			|| decision.valueMutationPolicy != OcamlRepresentationValueMutationPolicy.ImmutableValue
			|| decision.boxingPolicy != OcamlRepresentationBoxingPolicy.DirectNominalValueCarrier
			|| decision.implicitDefaultPolicy != OcamlRepresentationImplicitDefaultPolicy.NotAdmitted
			|| decision.proof.id != OcamlInt64RepresentationContract.PROOF_ID
			|| decision.nominalTargetModuleName != OcamlInt64RepresentationContract.TARGET_MODULE_NAME
			|| decision.nominalTargetTypeName != OcamlInt64RepresentationContract.TARGET_TYPE_NAME
			|| decision.nominalLayoutRevision != OcamlInt64RepresentationContract.LAYOUT_REVISION) {
			throw 'reflaxe.ocaml [ocaml-int64:representation-mismatch]: Bytes access expects the sealed exact Int64 internal carrier, but "$representationId" selects incompatible facts';
		}
		return decision;
	}

	/** Revalidates the exact internal Float carrier used by sealed Bytes I/O. */
	public function requireExactFloatInternal(representationId:String, representationRevision:String, programRevision:String):OcamlRepresentationDecision {
		final decision = require(representationId, programRevision);
		if (decision.id != OcamlFloatRepresentationContract.INTERNAL_REPRESENTATION_ID
			|| decision.revision != representationRevision
			|| decision.semanticTypeId != OcamlFloatRepresentationContract.SEMANTIC_TYPE_ID
			|| decision.carrierTypeId != OcamlFloatRepresentationContract.CARRIER_TYPE_ID
			|| decision.domain != OcamlRepresentationDomain.InternalValue
			|| decision.nullPolicy != OcamlRepresentationNullPolicy.NonNull
			|| decision.identityPolicy != OcamlRepresentationIdentityPolicy.PrimitiveValue
			|| decision.aliasingPolicy != OcamlRepresentationAliasingPolicy.NoValueAlias
			|| decision.storageMutationPolicy != OcamlRepresentationStorageMutationPolicy.ImmutableBinding
			|| decision.valueMutationPolicy != OcamlRepresentationValueMutationPolicy.ImmutableValue
			|| decision.boxingPolicy != OcamlRepresentationBoxingPolicy.DirectUnboxed
			|| decision.implicitDefaultPolicy != OcamlRepresentationImplicitDefaultPolicy.NotAdmitted
			|| decision.proof.id != OcamlFloatRepresentationContract.PROOF_ID) {
			throw 'reflaxe.ocaml [ocaml-float:representation-mismatch]: Bytes access expects the sealed exact Float internal carrier, but "$representationId" selects incompatible facts';
		}
		return decision;
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

	/** Registers or reuses one immutable flat array shape. */
	function registerRepresentedArray(normalized:OcamlNormalizedRepresentedArray,
			elementRepresentation:OcamlRepresentationDecision):OcamlRepresentedArrayDescriptor {
		final programRevision = requireProgramRevision();
		final expectedArraySemanticTypeId = 'Array<${normalized.elementSemanticTypeId}>';
		if (normalized.arraySemanticTypeId.length == 0
			|| normalized.elementSemanticTypeId.length == 0
			|| normalized.arraySemanticTypeId != expectedArraySemanticTypeId
			|| normalized.sourceForm != "direct-builtin-array"
			|| normalized.closureKind != "closed-monomorphic"
			|| normalized.outerWrapperKind != "none"
			|| normalized.nestingKind != "flat") {
			throw "reflaxe.ocaml [ocaml-representation:invalid-array-shape]: represented arrays must be direct, closed, unwrapped, and flat";
		}
		if (elementRepresentation.programRevision != programRevision
			|| elementRepresentation.semanticTypeId != normalized.elementSemanticTypeId
			|| elementRepresentation.domain != OcamlRepresentationDomain.ArrayElement
			|| elementRepresentation.id.length == 0
			|| !StringTools.startsWith(elementRepresentation.revision, "sha256:")) {
			throw 'reflaxe.ocaml [ocaml-representation:invalid-array-element]: ${normalized.arraySemanticTypeId} must bind an exact current-program ArrayElement representation for ${normalized.elementSemanticTypeId}';
		}
		final profiles = elementRepresentation.profileEligibility.copy();
		profiles.sort(Reflect.compare);
		final key = normalized.arraySemanticTypeId;
		final id = "represented-array:" + normalized.arraySemanticTypeId;
		final arrayCarrierTypeId = elementRepresentation.carrierTypeId + " HxArray.t";
		final reason = 'The direct closed flat ${normalized.arraySemanticTypeId} shape uses ${elementRepresentation.id}@${elementRepresentation.revision} for element storage and composes its ${elementRepresentation.carrierTypeId} carrier with HxArray.t.';
		final proofId = "direct-flat-array-element-binding-v1";
		final proofClaim = "The element decision is registered in the ArrayElement domain for the same program, so one HxArray container can store that exact carrier. This descriptor proves only shape and element binding; domain-specific representation decisions still own outer nullability, identity, aliases, replacement, and boxing.";
		final fingerprint = [
			ARRAY_DESCRIPTOR_MODEL_REVISION,
			normalized.arraySemanticTypeId,
			normalized.sourceForm,
			normalized.closureKind,
			normalized.outerWrapperKind,
			normalized.elementSemanticTypeId,
			elementRepresentation.id,
			elementRepresentation.revision,
			elementRepresentation.carrierTypeId,
			(OcamlRepresentationDomain.ArrayElement : String),
			"HxArray",
			arrayCarrierTypeId,
			"haxe-array",
			"Array",
			normalized.nestingKind,
			reason,
			proofId,
			proofClaim,
			profiles.join(",")
		].join("\n");
		final descriptor:OcamlRepresentedArrayDescriptor = {
			id: id,
			key: key,
			programRevision: programRevision,
			modelRevision: ARRAY_DESCRIPTOR_MODEL_REVISION,
			revision: "sha256:" + Sha256.encode(fingerprint),
			arraySemanticTypeId: normalized.arraySemanticTypeId,
			sourceForm: normalized.sourceForm,
			closureKind: normalized.closureKind,
			outerWrapperKind: normalized.outerWrapperKind,
			elementSemanticTypeId: normalized.elementSemanticTypeId,
			elementRepresentationId: elementRepresentation.id,
			elementRepresentationRevision: elementRepresentation.revision,
			elementCarrierTypeId: elementRepresentation.carrierTypeId,
			elementDomain: OcamlRepresentationDomain.ArrayElement,
			carrierFamilyId: "HxArray",
			arrayCarrierTypeId: arrayCarrierTypeId,
			runtimeCarrierCapabilityId: "haxe-array",
			runtimeKindTagId: "Array",
			nestingKind: normalized.nestingKind,
			reason: reason,
			proofId: proofId,
			proofClaim: proofClaim,
			profileEligibility: profiles
		};
		validateRepresentedArrayDescriptor(descriptor, elementRepresentation, programRevision);
		final existing = representedArraysByKey.get(key);
		if (existing != null) {
			if (existing.revision != descriptor.revision) {
				throw 'reflaxe.ocaml [ocaml-representation:conflicting-array-descriptor]: "$key" was already assigned ${existing.revision}, so it cannot also use ${descriptor.revision}';
			}
			return copyRepresentedArray(existing);
		}
		if (representedArraysById.exists(id))
			throw 'reflaxe.ocaml [ocaml-representation:duplicate-array-identity]: represented array identity "$id" belongs to more than one key';
		representedArraysByKey.set(key, descriptor);
		representedArraysById.set(id, descriptor);
		return copyRepresentedArray(descriptor);
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
		validateArrayDescriptorReference(selection, programRevision);
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
			profileEligibility: canonical.profileEligibility,
			nominalTargetModuleName: canonical.nominalTargetModuleName,
			nominalTargetTypeName: canonical.nominalTargetTypeName,
			nominalLayoutRevision: canonical.nominalLayoutRevision,
			arrayDescriptorId: canonical.arrayDescriptorId,
			arrayDescriptorRevision: canonical.arrayDescriptorRevision
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

	/**
		Rejects a damaged plain-data copy of one registered decision.

		Reports and inspection tools receive copies rather than the registry's
		private objects. This check recomputes the copy's identity and content
		digest, then binds it to the caller's current program. It proves that the
		copy still contains exactly the decision the registry produced; it does not
		admit a new semantic type or replace the closed selectors above.
	**/
	public static function validateDecisionSnapshot(decision:OcamlRepresentationDecision, expectedProgramRevision:String):Void {
		if (decision == null)
			throw "reflaxe.ocaml [ocaml-representation:invalid-decision]: a representation snapshot is missing";
		validateSelection(decision);
		if (expectedProgramRevision == null
			|| expectedProgramRevision.length == 0
			|| decision.programRevision != expectedProgramRevision) {
			throw 'reflaxe.ocaml [ocaml-representation:stale-program-revision]: representation "${decision.id}" belongs to ${decision.programRevision}, not $expectedProgramRevision';
		}
		final canonical = canonicalSelection(decision);
		final expectedKey = decisionKey(canonical.semanticTypeId, canonical.domain);
		final expectedId = "representation:" + canonical.semanticTypeId + ":" + (canonical.domain : String);
		final expectedRevision = "sha256:" + Sha256.encode(selectionFingerprint(canonical));
		if (decision.id != expectedId
			|| decision.key != expectedKey
			|| decision.revision != expectedRevision
			|| decision.profileEligibility.join(",") != canonical.profileEligibility.join(",")) {
			throw 'reflaxe.ocaml [ocaml-representation:stale-decision-snapshot]: representation "${decision.id}" no longer matches its identity, revision, or canonical profiles';
		}
	}

	/** Resolves one represented-array descriptor and checks its exact revision. */
	public function requireRepresentedArray(descriptorId:String, descriptorRevision:String, expectedProgramRevision:String):OcamlRepresentedArrayDescriptor {
		final actualProgramRevision = requireProgramRevision();
		if (expectedProgramRevision != actualProgramRevision) {
			throw 'reflaxe.ocaml [ocaml-representation:stale-array-program-revision]: array descriptor "$descriptorId" was requested for $expectedProgramRevision, but the registry belongs to $actualProgramRevision';
		}
		final descriptor = representedArraysById.get(descriptorId);
		if (descriptor == null)
			throw 'reflaxe.ocaml [ocaml-representation:missing-array-descriptor]: no represented-array descriptor exists for "$descriptorId"';
		if (descriptor.revision != descriptorRevision)
			throw 'reflaxe.ocaml [ocaml-representation:stale-array-descriptor]: "$descriptorId" has ${descriptor.revision}, not $descriptorRevision';
		final element = require(descriptor.elementRepresentationId, expectedProgramRevision);
		validateRepresentedArrayDescriptor(descriptor, element, expectedProgramRevision);
		return copyRepresentedArray(descriptor);
	}

	/**
		Recomputes every descriptor leaf from plain values.

		Reports and cached plans can call this without trusting a stored digest. The
		check follows the descriptor to the exact array-element representation and
		rejects any changed carrier, proof, profile, or program revision.
	**/
	public static function validateRepresentedArrayDescriptor(descriptor:OcamlRepresentedArrayDescriptor, elementRepresentation:OcamlRepresentationDecision,
			expectedProgramRevision:String):Void {
		final profiles = elementRepresentation.profileEligibility.copy();
		profiles.sort(Reflect.compare);
		final expectedArraySemanticTypeId = 'Array<${descriptor.elementSemanticTypeId}>';
		final expectedCarrier = elementRepresentation.carrierTypeId + " HxArray.t";
		final expectedReason = 'The direct closed flat ${descriptor.arraySemanticTypeId} shape uses ${elementRepresentation.id}@${elementRepresentation.revision} for element storage and composes its ${elementRepresentation.carrierTypeId} carrier with HxArray.t.';
		final expectedProofId = "direct-flat-array-element-binding-v1";
		final expectedProofClaim = "The element decision is registered in the ArrayElement domain for the same program, so one HxArray container can store that exact carrier. This descriptor proves only shape and element binding; domain-specific representation decisions still own outer nullability, identity, aliases, replacement, and boxing.";
		final fingerprint = [
			ARRAY_DESCRIPTOR_MODEL_REVISION,
			descriptor.arraySemanticTypeId,
			descriptor.sourceForm,
			descriptor.closureKind,
			descriptor.outerWrapperKind,
			descriptor.elementSemanticTypeId,
			elementRepresentation.id,
			elementRepresentation.revision,
			elementRepresentation.carrierTypeId,
			(OcamlRepresentationDomain.ArrayElement : String),
			"HxArray",
			expectedCarrier,
			"haxe-array",
			"Array",
			descriptor.nestingKind,
			expectedReason,
			expectedProofId,
			expectedProofClaim,
			profiles.join(",")
		].join("\n");
		final expectedRevision = "sha256:" + Sha256.encode(fingerprint);
		if (descriptor.id != "represented-array:" + descriptor.arraySemanticTypeId
			|| descriptor.key != descriptor.arraySemanticTypeId
			|| descriptor.arraySemanticTypeId != expectedArraySemanticTypeId
			|| descriptor.programRevision != expectedProgramRevision
			|| descriptor.modelRevision != ARRAY_DESCRIPTOR_MODEL_REVISION
			|| descriptor.revision != expectedRevision
			|| descriptor.sourceForm != "direct-builtin-array"
			|| descriptor.closureKind != "closed-monomorphic"
			|| descriptor.outerWrapperKind != "none"
			|| descriptor.elementRepresentationId != elementRepresentation.id
			|| descriptor.elementRepresentationRevision != elementRepresentation.revision
			|| descriptor.elementSemanticTypeId != elementRepresentation.semanticTypeId
			|| descriptor.elementCarrierTypeId != elementRepresentation.carrierTypeId
			|| descriptor.elementDomain != OcamlRepresentationDomain.ArrayElement
			|| elementRepresentation.domain != OcamlRepresentationDomain.ArrayElement
			|| descriptor.carrierFamilyId != "HxArray"
			|| descriptor.arrayCarrierTypeId != expectedCarrier
			|| descriptor.runtimeCarrierCapabilityId != "haxe-array"
			|| descriptor.runtimeKindTagId != "Array"
			|| descriptor.nestingKind != "flat"
			|| descriptor.reason != expectedReason
			|| descriptor.proofId != expectedProofId
			|| descriptor.proofClaim != expectedProofClaim
			|| descriptor.profileEligibility.join(",") != profiles.join(",")) {
			throw 'reflaxe.ocaml [ocaml-representation:stale-array-descriptor-leaf]: ${descriptor.id}@${descriptor.revision} does not match its exact ArrayElement representation and derived carrier facts';
		}
	}

	/** Returns every represented-array descriptor in deterministic identity order. */
	public function representedArrays():Array<OcamlRepresentedArrayDescriptor> {
		final ids = [for (id in representedArraysById.keys()) id];
		ids.sort(Reflect.compare);
		return [for (id in ids) copyRepresentedArray(cast representedArraysById.get(id))];
	}

	/** Returns every decision in deterministic identity order. */
	public function decisions():Array<OcamlRepresentationDecision> {
		final ids = [for (id in decisionsById.keys()) id];
		ids.sort(Reflect.compare);
		return [for (id in ids) copyDecision(cast decisionsById.get(id))];
	}

	/** Returns a deterministic digest of the program's current decisions. */
	public function revision():String {
		final entries = representedArrays().map(descriptor -> "array|" + descriptor.id + "|" + descriptor.revision)
			.concat(decisions().map(decision -> "representation|" + decision.id + "|" + decision.revision));
		entries.sort(Reflect.compare);
		return "sha256:" + Sha256.encode(entries.join("\n"));
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

	static function representedArrayReason(descriptor:OcamlRepresentedArrayDescriptor, domain:OcamlRepresentationDomain):String {
		return switch (domain) {
			case InternalValue:
				'An exact ${descriptor.arraySemanticTypeId} immutable binding stores the descriptor-owned ${descriptor.arrayCarrierTypeId} container; aliases share its element mutations while a later source assignment creates a newer binding.';
			case MutableLocalStorage:
				'An exact ${descriptor.arraySemanticTypeId} mutable local stores the descriptor-owned ${descriptor.arrayCarrierTypeId} container in one ref cell; the cell owns whole-array replacement and each HxArray owns shared element mutation.';
			case CapturedLocalStorage:
				'An exact ${descriptor.arraySemanticTypeId} captured local stores the descriptor-owned ${descriptor.arrayCarrierTypeId} container in the ref cell shared with nested functions; the cell owns replacement and each HxArray owns shared element mutation.';
			case InstanceField, StaticField, ArrayElement:
				throw 'reflaxe.ocaml [ocaml-representation:unsupported-array-domain]: no represented ${descriptor.arraySemanticTypeId} local reason exists for $domain';
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
				"An exact Haxe String array slot uses the nullable string carrier; HxArray owns slot replacement, null holes, bounds behavior, and private storage-mode changes.";
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

	static function requireBytesInternalDomain(domain:OcamlRepresentationDomain, semanticTypeId:String):Void {
		if (domain != OcamlRepresentationDomain.InternalValue)
			throw 'reflaxe.ocaml [ocaml-representation:unsupported-bytes-domain]: exact $semanticTypeId is admitted only as an internal value, not $domain';
	}

	public static function monomorphicClassSemanticTypeId(type:Type):Null<String> {
		return switch (type) {
			case TInst(classRef, parameters):
				final classType = classRef.get();
				if (parameters.length > 0 || classType.params.length > 0) {
					null;
				} else {
					(classType.pack ?? []).concat([classType.name]).join(".");
				}
			case _:
				null;
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
		if (selection == null
			|| selection.semanticTypeId == null
			|| selection.carrierTypeId == null
			|| selection.reason == null
			|| selection.semanticTypeId.length == 0
			|| selection.carrierTypeId.length == 0
			|| selection.reason.length == 0)
			throw "reflaxe.ocaml [ocaml-representation:invalid-decision]: semantic type, carrier, and reason must be non-empty";
		if (selection.domain == null
			|| selection.nullPolicy == null
			|| selection.identityPolicy == null
			|| selection.aliasingPolicy == null
			|| selection.storageMutationPolicy == null
			|| selection.valueMutationPolicy == null
			|| selection.boxingPolicy == null
			|| selection.implicitDefaultPolicy == null)
			throw "reflaxe.ocaml [ocaml-representation:invalid-decision]: every decision needs complete domain, null, identity, aliasing, mutation, boxing, and default policies";
		if (selection.proof == null || selection.proof.id == null || selection.proof.claim == null || selection.proof.id.length == 0
			|| selection.proof.claim.length == 0)
			throw "reflaxe.ocaml [ocaml-representation:invalid-decision]: every decision needs a named proof and claim";
		if (selection.profileEligibility == null || selection.profileEligibility.length == 0)
			throw "reflaxe.ocaml [ocaml-representation:invalid-decision]: every decision needs at least one eligible profile";
		final nominalFieldCount = (selection.nominalTargetModuleName == null ? 0 : 1) + (selection.nominalTargetTypeName == null ? 0 : 1)
			+ (selection.nominalLayoutRevision == null ? 0 : 1);
		if (nominalFieldCount != 0 && nominalFieldCount != 3)
			throw "reflaxe.ocaml [ocaml-representation:invalid-decision]: nominal module, type, and layout revision must be supplied together";
		if (nominalFieldCount == 3
			&& (selection.nominalTargetModuleName.length == 0
				|| selection.nominalTargetTypeName.length == 0
				|| !StringTools.startsWith(selection.nominalLayoutRevision, "sha256:")))
			throw "reflaxe.ocaml [ocaml-representation:invalid-decision]: nominal carrier metadata is incomplete or has an invalid layout revision";
		final arrayFieldCount = (selection.arrayDescriptorId == null ? 0 : 1) + (selection.arrayDescriptorRevision == null ? 0 : 1);
		if (arrayFieldCount != 0 && arrayFieldCount != 2)
			throw "reflaxe.ocaml [ocaml-representation:invalid-decision]: array descriptor identity and revision must be supplied together";
		if (arrayFieldCount == 2
			&& (selection.arrayDescriptorId.length == 0 || !StringTools.startsWith(selection.arrayDescriptorRevision, "sha256:")))
			throw "reflaxe.ocaml [ocaml-representation:invalid-decision]: array descriptor metadata is incomplete or has an invalid revision";
	}

	/**
		Rejects a representation that names a missing, stale, or unrelated array
		descriptor before the decision can enter the program registry.
	**/
	function validateArrayDescriptorReference(selection:OcamlRepresentationSelection, programRevision:String):Void {
		if (selection.arrayDescriptorId == null)
			return;
		final descriptor = requireRepresentedArray(selection.arrayDescriptorId, selection.arrayDescriptorRevision, programRevision);
		if (selection.semanticTypeId != descriptor.arraySemanticTypeId
			|| selection.carrierTypeId != descriptor.arrayCarrierTypeId
			|| selection.profileEligibility.join(",") != descriptor.profileEligibility.join(",")) {
			throw 'reflaxe.ocaml [ocaml-representation:array-descriptor-mismatch]: ${selection.semanticTypeId}/${selection.carrierTypeId} does not match ${descriptor.id}@${descriptor.revision}';
		}
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
			profileEligibility: uniqueProfiles,
			nominalTargetModuleName: selection.nominalTargetModuleName,
			nominalTargetTypeName: selection.nominalTargetTypeName,
			nominalLayoutRevision: selection.nominalLayoutRevision,
			arrayDescriptorId: selection.arrayDescriptorId,
			arrayDescriptorRevision: selection.arrayDescriptorRevision
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
			selection.profileEligibility.join(","),
			selection.nominalTargetModuleName ?? "",
			selection.nominalTargetTypeName ?? "",
			selection.nominalLayoutRevision ?? "",
			selection.arrayDescriptorId ?? "",
			selection.arrayDescriptorRevision ?? ""
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
			profileEligibility: decision.profileEligibility.copy(),
			nominalTargetModuleName: decision.nominalTargetModuleName,
			nominalTargetTypeName: decision.nominalTargetTypeName,
			nominalLayoutRevision: decision.nominalLayoutRevision,
			arrayDescriptorId: decision.arrayDescriptorId,
			arrayDescriptorRevision: decision.arrayDescriptorRevision
		};
	}

	static function copyRepresentedArray(descriptor:OcamlRepresentedArrayDescriptor):OcamlRepresentedArrayDescriptor {
		return {
			id: descriptor.id,
			key: descriptor.key,
			programRevision: descriptor.programRevision,
			modelRevision: descriptor.modelRevision,
			revision: descriptor.revision,
			arraySemanticTypeId: descriptor.arraySemanticTypeId,
			sourceForm: descriptor.sourceForm,
			closureKind: descriptor.closureKind,
			outerWrapperKind: descriptor.outerWrapperKind,
			elementSemanticTypeId: descriptor.elementSemanticTypeId,
			elementRepresentationId: descriptor.elementRepresentationId,
			elementRepresentationRevision: descriptor.elementRepresentationRevision,
			elementCarrierTypeId: descriptor.elementCarrierTypeId,
			elementDomain: descriptor.elementDomain,
			carrierFamilyId: descriptor.carrierFamilyId,
			arrayCarrierTypeId: descriptor.arrayCarrierTypeId,
			runtimeCarrierCapabilityId: descriptor.runtimeCarrierCapabilityId,
			runtimeKindTagId: descriptor.runtimeKindTagId,
			nestingKind: descriptor.nestingKind,
			reason: descriptor.reason,
			proofId: descriptor.proofId,
			proofClaim: descriptor.proofClaim,
			profileEligibility: descriptor.profileEligibility.copy()
		};
	}

	static function copyMonomorphicField(field:OcamlMonomorphicClassField):OcamlMonomorphicClassField {
		return {
			sourceFieldName: field.sourceFieldName,
			targetFieldName: field.targetFieldName,
			semanticTypeId: field.semanticTypeId,
			carrierTypeId: field.carrierTypeId,
			representationId: field.representationId,
			declarationOrder: field.declarationOrder
		};
	}

	static function copyMonomorphicClass(decision:OcamlMonomorphicClassDecision):OcamlMonomorphicClassDecision {
		return {
			id: decision.id,
			key: decision.key,
			programRevision: decision.programRevision,
			revision: decision.revision,
			semanticTypeId: decision.semanticTypeId,
			sourceModuleId: decision.sourceModuleId,
			sourceTypeName: decision.sourceTypeName,
			targetModuleName: decision.targetModuleName,
			targetTypeName: decision.targetTypeName,
			canonicalCarrierTypeId: decision.canonicalCarrierTypeId,
			fields: decision.fields.map(copyMonomorphicField),
			proofId: decision.proofId,
			proofClaim: decision.proofClaim
		};
	}
}
#end
