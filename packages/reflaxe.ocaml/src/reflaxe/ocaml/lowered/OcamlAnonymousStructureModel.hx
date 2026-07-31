package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
import haxe.crypto.Sha256;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;

/** The anonymous-object action whose meaning was fixed before OCaml syntax. */
enum abstract OcamlAnonymousStructureOperationKind(String) from String to String {
	/** Allocate one empty mutable anonymous-object container. */
	final Create = "create";

	/** Store one source-ordered field while constructing an object literal. */
	final InitializeField = "initialize-field";

	/** Read one statically known field from an admitted anonymous value. */
	final ReadField = "read-field";

	/** Replace one statically known field and return the assigned Haxe value. */
	final WriteField = "write-field";

	/**
		Read, update, and replace one statically known field.

		This first compound-write boundary admits only `Int += Int`. Other
		compound operators remain outside the model and must not be approximated
		by target syntax.
	**/
	final CompoundWriteField = "compound-write-field";
}

/** The exact Haxe operation applied between a loaded field and a new value. */
enum abstract OcamlAnonymousStructureFieldOperator(String) from String to String {
	/** Haxe `Int` addition with signed 32-bit overflow behavior. */
	final IntAdd = "int-add";
}

/** How one typed Haxe field value enters the `Obj.t` slot used by `HxAnon`. */
enum abstract OcamlAnonymousStructureStoreConversion(String) from String to String {
	/** Preserve an Int or String value through OCaml's checked universal carrier. */
	final ObjRepr = "obj-repr";

	/**
		Use the target's distinct Bool box.

		OCaml represents small integers and booleans with overlapping immediate
		values. The dedicated box keeps a stored Haxe `false` distinguishable from
		the integer zero.
	**/
	final BoxBool = "box-bool";
}

/** How one `Obj.t` field slot becomes its already selected Haxe carrier. */
enum abstract OcamlAnonymousStructureLoadConversion(String) from String to String {
	/** Recover an Int or String value from the universal field slot. */
	final ObjObj = "obj-obj";

	/** Validate and recover the target's distinct stored Bool value. */
	final UnboxBool = "unbox-bool";
}

/** One field in the normalized anonymous shape. */
typedef OcamlAnonymousStructureField = {
	/** Field name as seen by typed Haxe code. */
	final name:String;

	/** Position in name-sorted canonical shape order. */
	final canonicalOrder:Int;

	/** Exact Haxe semantic type selected for the field. */
	final semanticTypeId:String;

	/** Exact OCaml carrier used before the value enters the `HxAnon` slot. */
	final carrierTypeId:String;

	/** Program representation decision that owns the field carrier. */
	final representationId:String;

	/** Revision of the field representation decision. */
	final representationRevision:String;

	/** Exact conversion used when storing this field in `HxAnon`. */
	final storeConversion:OcamlAnonymousStructureStoreConversion;

	/** Exact conversion used when reading this field from `HxAnon`. */
	final loadConversion:OcamlAnonymousStructureLoadConversion;
}

/**
	One path-independent representation of an admitted anonymous-object shape.

	Fields are sorted by name so harmless typed-tree traversal changes do not
	change the identity. Literal evaluation order lives in the operation records,
	where source order is behaviorally significant.
**/
typedef OcamlAnonymousStructureDecision = {
	final id:String;
	final semanticTypeId:String;
	final carrierTypeId:String;
	final fields:Array<OcamlAnonymousStructureField>;
	final representationId:String;
	final representationRevision:String;
	final representationDomain:String;
	final nullPolicy:String;
	final identityPolicy:String;
	final aliasingPolicy:String;
	final mutationPolicy:String;
	final proofId:String;
	final proofClaim:String;
	final programRevision:String;
	final revision:String;
}

/**
	One exact source occurrence that uses the admitted anonymous representation.

	The record contains the operation's evaluation schedule and both its input
	and result carriers. Target syntax can therefore materialize the action
	without deciding whether it is a create, read, write, boxing, or unboxing
	boundary.
**/
typedef OcamlAnonymousStructureOperationDecision = {
	final id:String;
	final occurrenceId:String;
	final source:OcamlLoweredSourceSpan;
	final kind:OcamlAnonymousStructureOperationKind;
	final structureId:String;
	final structureRevision:String;
	final structureRepresentationId:String;
	final structureRepresentationRevision:String;
	final fieldName:Null<String>;
	final fieldCanonicalOrder:Int;
	final fieldSourceOrder:Int;
	final fieldSemanticTypeId:String;
	final fieldCarrierTypeId:String;
	final fieldRepresentationId:String;
	final fieldRepresentationRevision:String;
	final storeConversion:Null<OcamlAnonymousStructureStoreConversion>;
	final loadConversion:Null<OcamlAnonymousStructureLoadConversion>;
	final fieldOperator:Null<OcamlAnonymousStructureFieldOperator>;
	final evaluationSchedule:Array<String>;
	final resultSemanticTypeId:String;
	final resultCarrierTypeId:String;
	final resultRepresentationId:String;
	final resultRepresentationRevision:String;
	final runtimeModule:String;
	final runtimeReadOperation:Null<String>;
	final runtimeOperation:String;
	final runtimeRequirementIds:Array<String>;
	final proofId:String;
	final proofClaim:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/** Pure validation and identity rules shared by planning, reports, and tests. */
class OcamlAnonymousStructureContract {
	public static inline final MODEL_REVISION = "ocaml-anonymous-structure-v3";
	public static inline final OCCURRENCE_PREFIX = "anonymous-occurrence:";
	public static inline final RUNTIME_CAPABILITY = "haxe-anonymous-structure";
	public static inline final INT32_ADD_CAPABILITY = "haxe-int32-add";
	public static inline final RUNTIME_MODULE = "HxAnon";
	public static inline final INT32_ADD_MODULE = "HxInt";
	public static inline final PROOF_ID = "direct-anonymous-runtime-operations-v3";
	public static inline final PROOF_CLAIM = "This proof is local to each admitted anonymous-object occurrence, not to the whole function. It owns construction and source-ordered initialization for a direct literal with exact Int, Bool, or String fields. It owns a field operation only when the receiver is that literal or an unchanged local alias. Iterator, key/value, sys.FileStat, method, Dynamic, structural-conversion, pattern-expansion, raw, and adapter operations remain outside this plan even when another expression in the same function uses one of those boundaries. The validated structure uses one mutable HxAnon table. Reads evaluate the receiver once, plain writes evaluate the receiver before the assigned value, and admitted Int += writes evaluate the receiver once, load the old value, evaluate the right-hand side once, apply Haxe Int32 addition, store the result, and return it. Local copies preserve one shared reference so mutations remain visible through aliases.";

	/** Builds the stable representation identity for a normalized shape. */
	public static function structureId(semanticTypeId:String):String {
		return "anonymous-structure:" + Sha256.encode(MODEL_REVISION + "\n" + semanticTypeId).substr(0, 24);
	}

	/** Builds the stable operation identity from all behavior-bearing facts. */
	public static function operationId(decision:OcamlAnonymousStructureOperationDecision):String {
		return "anonymous-operation:" + Sha256.encode(operationFingerprint(decision)).substr(0, 24);
	}

	/** Returns the `HxAnon` runtime requirement owned by one operation. */
	public static function runtimeRequirementId(operationId:String):String {
		return operationId + ":runtime:" + RUNTIME_CAPABILITY;
	}

	/** Returns every runtime requirement selected by an operation, in stable order. */
	public static function runtimeRequirementIds(operationId:String, kind:OcamlAnonymousStructureOperationKind):Array<String> {
		final out = [runtimeRequirementId(operationId)];
		if (kind == OcamlAnonymousStructureOperationKind.CompoundWriteField)
			out.push(operationId + ":runtime:" + INT32_ADD_CAPABILITY);
		return out;
	}

	/** Fails when a structure no longer matches the bounded representation proof. */
	public static function requireStructure(decision:OcamlAnonymousStructureDecision):Void {
		if (decision == null)
			throw "reflaxe.ocaml [ocaml-anonymous:missing-structure]: anonymous structure decision is missing";
		if (decision.id != structureId(decision.semanticTypeId)
			|| !StringTools.startsWith(decision.semanticTypeId, "anonymous{")
			|| !StringTools.endsWith(decision.semanticTypeId, "}")
			|| decision.carrierTypeId != "Obj.t"
			|| decision.representationDomain != "internal-value"
			|| decision.nullPolicy != "runtime-sentinel"
			|| decision.identityPolicy != "reference-identity"
			|| decision.aliasingPolicy != "shared-reference-aliases"
			|| decision.mutationPolicy != "mutable-runtime-container"
			|| decision.proofId != PROOF_ID
			|| decision.proofClaim != PROOF_CLAIM
			|| decision.programRevision.length == 0
			|| !StringTools.startsWith(decision.revision, "sha256:")) {
			throw 'reflaxe.ocaml [ocaml-anonymous:invalid-structure]: anonymous structure "${decision.id}" does not match the sealed runtime-container contract';
		}
		final names:Map<String, Bool> = [];
		for (index in 0...decision.fields.length) {
			final field = decision.fields[index];
			if (field.canonicalOrder != index
				|| field.name.length == 0
				|| names.exists(field.name)
				|| !isAdmittedFieldCarrier(field.semanticTypeId, field.carrierTypeId, field.storeConversion, field.loadConversion)
				|| field.representationId.length == 0
				|| !StringTools.startsWith(field.representationRevision, "sha256:")) {
				throw 'reflaxe.ocaml [ocaml-anonymous:invalid-field]: anonymous structure "${decision.id}" has an invalid field at canonical order $index';
			}
			if (index > 0 && Reflect.compare(decision.fields[index - 1].name, field.name) >= 0)
				throw 'reflaxe.ocaml [ocaml-anonymous:reordered-field]: anonymous structure "${decision.id}" fields are not in strict name order';
			names.set(field.name, true);
		}
		final expectedRevision = structureRevision(decision);
		if (decision.revision != expectedRevision)
			throw 'reflaxe.ocaml [ocaml-anonymous:stale-structure]: anonymous structure "${decision.id}" has revision ${decision.revision}, expected $expectedRevision';
	}

	/** Fails when one operation does not exactly match its sealed structure. */
	public static function requireOperation(operation:OcamlAnonymousStructureOperationDecision, structure:OcamlAnonymousStructureDecision):Void {
		requireStructure(structure);
		if (operation == null)
			throw "reflaxe.ocaml [ocaml-anonymous:missing-operation]: anonymous operation is missing";
		if (operation.structureId != structure.id
			|| operation.structureRevision != structure.revision
			|| operation.structureRepresentationId != structure.representationId
			|| operation.structureRepresentationRevision != structure.representationRevision
			|| operation.functionId.length == 0
			|| operation.programRevision != structure.programRevision
			|| operation.bodyRevision.length == 0
			|| operation.pipelineRevision.length == 0
			|| operation.occurrenceId.length == 0
			|| operation.runtimeModule != RUNTIME_MODULE
			|| operation.proofId != PROOF_ID
			|| operation.proofClaim != PROOF_CLAIM) {
			throw 'reflaxe.ocaml [ocaml-anonymous:stale-operation]: anonymous operation "${operation.id}" does not match structure "${structure.id}" or its owning function';
		}
		final hasFieldIndex = operation.fieldCanonicalOrder >= 0 && operation.fieldCanonicalOrder < structure.fields.length;
		final field = operation.fieldName == null || !hasFieldIndex ? null : structure.fields[operation.fieldCanonicalOrder];
		if (operation.kind == OcamlAnonymousStructureOperationKind.Create) {
			requireCreate(operation);
		} else {
			if (field == null
				|| field.name != operation.fieldName
				|| field.semanticTypeId != operation.fieldSemanticTypeId
				|| field.carrierTypeId != operation.fieldCarrierTypeId
				|| field.representationId != operation.fieldRepresentationId
				|| field.representationRevision != operation.fieldRepresentationRevision) {
				throw 'reflaxe.ocaml [ocaml-anonymous:wrong-field]: anonymous operation "${operation.id}" does not match canonical field ${operation.fieldCanonicalOrder}';
			}
			switch (operation.kind) {
				case InitializeField:
					requireInitialize(operation, field);
				case ReadField:
					requireRead(operation, field);
				case WriteField:
					requireWrite(operation, field);
				case CompoundWriteField:
					requireCompoundWrite(operation, field);
				case Create:
			}
		}
		final expectedRuntimeRequirements = runtimeRequirementIds(operation.id, operation.kind);
		if (operation.runtimeRequirementIds.join("\n") != expectedRuntimeRequirements.join("\n")) {
			throw 'reflaxe.ocaml [ocaml-anonymous:wrong-runtime]: anonymous operation "${operation.id}" does not name its exact runtime requirements';
		}
		if (operation.id != operationId(copyOperation(operation, "")))
			throw 'reflaxe.ocaml [ocaml-anonymous:stale-operation]: anonymous operation "${operation.id}" does not match its canonical facts';
	}

	/** Computes the path-independent shape revision. */
	public static function structureRevision(decision:OcamlAnonymousStructureDecision):String {
		return "sha256:" + Sha256.encode([
			MODEL_REVISION,
			decision.semanticTypeId,
			decision.carrierTypeId,
			decision.representationId,
			decision.representationRevision,
			decision.representationDomain,
			decision.nullPolicy,
			decision.identityPolicy,
			decision.aliasingPolicy,
			decision.mutationPolicy,
			decision.proofId,
			decision.proofClaim,
			decision.programRevision
		].concat(decision.fields.map(field -> [
			field.name,
			Std.string(field.canonicalOrder),
			field.semanticTypeId,
			field.carrierTypeId,
			field.representationId,
			field.representationRevision,
			(field.storeConversion : String),
			(field.loadConversion : String)
			].join("|"))).join("\n"));
	}

	static function requireCreate(operation:OcamlAnonymousStructureOperationDecision):Void {
		if (operation.fieldName != null
			|| operation.fieldCanonicalOrder != -1
			|| operation.fieldSourceOrder != -1
			|| operation.fieldSemanticTypeId != ""
			|| operation.fieldCarrierTypeId != ""
			|| operation.fieldRepresentationId != ""
			|| operation.fieldRepresentationRevision != ""
			|| operation.storeConversion != null
			|| operation.loadConversion != null
			|| operation.fieldOperator != null
			|| operation.evaluationSchedule.join(",") != "create-container,result-container"
			|| operation.resultSemanticTypeId.length == 0
			|| operation.resultCarrierTypeId != "Obj.t"
			|| operation.resultRepresentationId != operation.structureRepresentationId
			|| operation.resultRepresentationRevision != operation.structureRepresentationRevision
			|| operation.runtimeReadOperation != null
			|| operation.runtimeOperation != "create") {
			throw 'reflaxe.ocaml [ocaml-anonymous:invalid-create]: anonymous create "${operation.id}" has conflicting field, result, or schedule facts';
		}
	}

	static function requireInitialize(operation:OcamlAnonymousStructureOperationDecision, field:OcamlAnonymousStructureField):Void {
		if (operation.fieldSourceOrder < 0
			|| operation.storeConversion != field.storeConversion
			|| operation.loadConversion != null
			|| operation.fieldOperator != null
			|| operation.evaluationSchedule.join(",") != "field-value,box-field-value,store-field"
			|| operation.resultSemanticTypeId != "Void"
			|| operation.resultCarrierTypeId != ""
			|| operation.resultRepresentationId != ""
			|| operation.resultRepresentationRevision != ""
			|| operation.runtimeReadOperation != null
			|| operation.runtimeOperation != "set") {
			throw 'reflaxe.ocaml [ocaml-anonymous:invalid-initializer]: anonymous initializer "${operation.id}" has conflicting carrier, result, or schedule facts';
		}
	}

	static function requireRead(operation:OcamlAnonymousStructureOperationDecision, field:OcamlAnonymousStructureField):Void {
		if (operation.fieldSourceOrder != -1
			|| operation.storeConversion != null
			|| operation.loadConversion != field.loadConversion
			|| operation.fieldOperator != null
			|| operation.evaluationSchedule.join(",") != "receiver,lookup-field,unbox-field-value,result-value"
			|| !hasFieldResult(operation, field)
			|| operation.runtimeReadOperation != null
			|| operation.runtimeOperation != "get") {
			throw 'reflaxe.ocaml [ocaml-anonymous:invalid-read]: anonymous read "${operation.id}" has conflicting carrier, result, or schedule facts';
		}
	}

	static function requireWrite(operation:OcamlAnonymousStructureOperationDecision, field:OcamlAnonymousStructureField):Void {
		if (operation.fieldSourceOrder != -1
			|| operation.storeConversion != field.storeConversion
			|| operation.loadConversion != null
			|| operation.fieldOperator != null
			|| operation.evaluationSchedule.join(",") != "receiver,field-value,box-field-value,store-field,result-value"
			|| !hasFieldResult(operation, field)
			|| operation.runtimeReadOperation != null
			|| operation.runtimeOperation != "set") {
			throw 'reflaxe.ocaml [ocaml-anonymous:invalid-write]: anonymous write "${operation.id}" has conflicting carrier, result, or schedule facts';
		}
	}

	static function requireCompoundWrite(operation:OcamlAnonymousStructureOperationDecision, field:OcamlAnonymousStructureField):Void {
		if (field.semanticTypeId != "Int"
			|| field.carrierTypeId != "int"
			|| operation.fieldSourceOrder != -1
			|| operation.storeConversion != field.storeConversion
			|| operation.loadConversion != field.loadConversion
			|| operation.fieldOperator != OcamlAnonymousStructureFieldOperator.IntAdd
			|| operation.evaluationSchedule.join(",") != "receiver,lookup-field,unbox-old-field-value,field-value,apply-field-operator,box-field-value,store-field,result-value"
			|| !hasFieldResult(operation, field)
			|| operation.runtimeReadOperation != "get"
			|| operation.runtimeOperation != "set") {
			throw 'reflaxe.ocaml [ocaml-anonymous:invalid-compound-write]: anonymous compound write "${operation.id}" does not describe exact Int += behavior';
		}
	}

	static function hasFieldResult(operation:OcamlAnonymousStructureOperationDecision, field:OcamlAnonymousStructureField):Bool {
		return operation.resultSemanticTypeId == field.semanticTypeId
			&& operation.resultCarrierTypeId == field.carrierTypeId
			&& operation.resultRepresentationId == field.representationId
			&& operation.resultRepresentationRevision == field.representationRevision;
	}

	static function isAdmittedFieldCarrier(semanticTypeId:String, carrierTypeId:String, store:OcamlAnonymousStructureStoreConversion,
			load:OcamlAnonymousStructureLoadConversion):Bool {
		return switch (semanticTypeId) {
			case "Int": carrierTypeId == "int" && store == OcamlAnonymousStructureStoreConversion.ObjRepr && load == OcamlAnonymousStructureLoadConversion.ObjObj;
			case "Bool": carrierTypeId == "bool" && store == OcamlAnonymousStructureStoreConversion.BoxBool && load == OcamlAnonymousStructureLoadConversion.UnboxBool;
			case "String": carrierTypeId == "string" && store == OcamlAnonymousStructureStoreConversion.ObjRepr && load == OcamlAnonymousStructureLoadConversion.ObjObj;
			case _:
				false;
		}
	}

	static function operationFingerprint(decision:OcamlAnonymousStructureOperationDecision):String {
		return [
			MODEL_REVISION,
			decision.occurrenceId,
			decision.source.file,
			Std.string(decision.source.min),
			Std.string(decision.source.max),
			(decision.kind : String),
			decision.structureId,
			decision.structureRevision,
			decision.structureRepresentationId,
			decision.structureRepresentationRevision,
			decision.fieldName ?? "",
			Std.string(decision.fieldCanonicalOrder),
			Std.string(decision.fieldSourceOrder),
			decision.fieldSemanticTypeId,
			decision.fieldCarrierTypeId,
			decision.fieldRepresentationId,
			decision.fieldRepresentationRevision,
			decision.storeConversion == null ? "" : (decision.storeConversion : String),
			decision.loadConversion == null ? "" : (decision.loadConversion : String),
			decision.fieldOperator == null ? "" : (decision.fieldOperator : String),
			decision.evaluationSchedule.join(","),
			decision.resultSemanticTypeId,
			decision.resultCarrierTypeId,
			decision.resultRepresentationId,
			decision.resultRepresentationRevision,
			decision.runtimeModule,
			decision.runtimeReadOperation ?? "",
			decision.runtimeOperation,
			decision.proofId,
			decision.proofClaim,
			decision.functionId,
			decision.programRevision,
			decision.bodyRevision,
			decision.pipelineRevision
		].join("\n");
	}

	/**
		Copies an operation while replacing its identity.

		When the identity changes, the helper also derives the one runtime
		requirement that is scoped to that new identity. When the identity stays
		the same, every fact is copied exactly so plan construction and report
		inspection can detect corrupted runtime data instead of repairing it
		before validation.
	**/
	public static function copyOperation(decision:OcamlAnonymousStructureOperationDecision, id:String):OcamlAnonymousStructureOperationDecision {
		return {
			id: id,
			occurrenceId: decision.occurrenceId,
			source: {file: decision.source.file, min: decision.source.min, max: decision.source.max},
			kind: decision.kind,
			structureId: decision.structureId,
			structureRevision: decision.structureRevision,
			structureRepresentationId: decision.structureRepresentationId,
			structureRepresentationRevision: decision.structureRepresentationRevision,
			fieldName: decision.fieldName,
			fieldCanonicalOrder: decision.fieldCanonicalOrder,
			fieldSourceOrder: decision.fieldSourceOrder,
			fieldSemanticTypeId: decision.fieldSemanticTypeId,
			fieldCarrierTypeId: decision.fieldCarrierTypeId,
			fieldRepresentationId: decision.fieldRepresentationId,
			fieldRepresentationRevision: decision.fieldRepresentationRevision,
			storeConversion: decision.storeConversion,
			loadConversion: decision.loadConversion,
			fieldOperator: decision.fieldOperator,
			evaluationSchedule: decision.evaluationSchedule.copy(),
			resultSemanticTypeId: decision.resultSemanticTypeId,
			resultCarrierTypeId: decision.resultCarrierTypeId,
			resultRepresentationId: decision.resultRepresentationId,
			resultRepresentationRevision: decision.resultRepresentationRevision,
			runtimeModule: decision.runtimeModule,
			runtimeReadOperation: decision.runtimeReadOperation,
			runtimeOperation: decision.runtimeOperation,
			runtimeRequirementIds: id == decision.id ? decision.runtimeRequirementIds.copy() : runtimeRequirementIds(id, decision.kind),
			proofId: decision.proofId,
			proofClaim: decision.proofClaim,
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
	}
}
#end
