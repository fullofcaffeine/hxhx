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
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationProof;
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
	local cells, and direct fields. A proven monomorphic class may additionally
	occupy one captured local cell when every whole-value replacement already
	produces that exact nominal carrier.
**/
class OcamlRepresentationRegistry {
	public static inline final MODEL_REVISION = "ocaml-representation-v16";

	var currentProgramRevision:Null<String> = null;
	final decisionsByKey:StringMap<OcamlRepresentationDecision> = new StringMap();
	final decisionsById:StringMap<OcamlRepresentationDecision> = new StringMap();
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
			profileEligibility: canonical.profileEligibility,
			nominalTargetModuleName: canonical.nominalTargetModuleName,
			nominalTargetTypeName: canonical.nominalTargetTypeName,
			nominalLayoutRevision: canonical.nominalLayoutRevision
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
		if (selection.semanticTypeId.length == 0 || selection.carrierTypeId.length == 0 || selection.reason.length == 0)
			throw "reflaxe.ocaml [ocaml-representation:invalid-decision]: semantic type, carrier, and reason must be non-empty";
		if (selection.proof.id.length == 0 || selection.proof.claim.length == 0)
			throw "reflaxe.ocaml [ocaml-representation:invalid-decision]: every decision needs a named proof and claim";
		if (selection.profileEligibility.length == 0)
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
			nominalLayoutRevision: selection.nominalLayoutRevision
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
			selection.nominalLayoutRevision ?? ""
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
			nominalLayoutRevision: decision.nominalLayoutRevision
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
