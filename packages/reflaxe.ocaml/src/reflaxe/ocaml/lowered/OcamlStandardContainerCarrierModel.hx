package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
import haxe.crypto.Sha256;
#if macro
import haxe.macro.Type;
import haxe.macro.TypeTools;
#end
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/** The private OCaml storage family selected from a standard Haxe container. */
enum OcamlStandardContainerCarrierKind {
	ArrayCarrier;
	BytesCarrier;
}

/** One immutable private-type choice for a standard Haxe container occurrence. */
typedef OcamlStandardContainerCarrierDecision = {
	final id:String;
	final revision:String;
	final ownerId:String;
	final programRevision:String;
	final pipelineRevision:String;
	final source:OcamlLoweredSourceSpan;
	final sourceDeclarationId:String;
	final kind:OcamlStandardContainerCarrierKind;
	final semanticTypeId:String;
	final elementSemanticTypeId:String;
	final exactSymbol:String;
	final profileEligibility:Array<String>;
	final runtimeRequirementIds:Array<String>;
	final runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence>;
	final proofId:String;
	final proofClaim:String;
}

#if macro
/**
	Keeps the Array element type inside the active compiler request.

	The detached decision contains only plain values. It does not retain the Haxe
	compiler's mutable type objects after this type occurrence is materialized.
**/
typedef OcamlStandardContainerCarrierMaterialization = {
	final decision:OcamlStandardContainerCarrierDecision;
	final elementType:Null<Type>;
}
#end

/**
	Authorizes private Array and Bytes carrier names from canonical Haxe types.

	A carrier is the concrete OCaml type that stores a Haxe value. A generated
	name such as `HxArray.t` is not evidence by itself. The final typed Haxe
	declaration, request revision, and hidden occurrence identity must all match.
**/
class OcamlStandardContainerCarrierContract {
	public static inline final CARRIER_PROOF_ID = "typed-standard-container-carrier-runtime-use-v1";
	public static inline final CARRIER_PROOF_CLAIM = "The final Haxe type is the canonical Array<T> or haxe.io.Bytes class. Its exact source declaration and semantic type select one HxArray.t or HxBytes.t carrier before OCaml type syntax. A target name, user-defined lookalike, or generated type string alone does not authorize the carrier.";
	public static inline final ARRAY_RUNTIME_CAPABILITY = "haxe-array-carrier";
	public static inline final BYTES_RUNTIME_CAPABILITY = "haxe-bytes-carrier";
	public static inline final RUNTIME_ROLE = "standard-container-carrier-type";

	#if macro
	/**
		Seals one private carrier choice from an exact typed Haxe container.

		The owner identifies one target type occurrence. Array element types remain
		request-local so nested types can obtain their own independent authority.
	**/
	public static function seal(type:Type, ownerId:String, programRevision:String, pipelineRevision:String,
			?source:OcamlLoweredSourceSpan):Null<OcamlStandardContainerCarrierMaterialization> {
		final selected = select(type);
		if (selected == null)
			return null;
		final stableOwner = required(ownerId, "owner identity");
		final stableProgramRevision = required(programRevision, "program revision");
		final stablePipelineRevision = required(pipelineRevision, "target pipeline revision");
		final stableSource = source == null ? selected.source : source;
		requireSource(stableOwner, stableSource);
		final semanticTypeId = TypeTools.toString(type);
		final elementSemanticTypeId = selected.elementType == null ? "<none>" : TypeTools.toString(selected.elementType);
		final exactSymbol = symbolForKind(selected.kind);
		final capability = runtimeCapabilityForKind(selected.kind);
		final id = "standard-container-carrier:" + Sha256.encode([
			stableOwner,
			stableProgramRevision,
			stablePipelineRevision,
			stableSource.file,
			Std.string(stableSource.min),
			Std.string(stableSource.max),
			selected.sourceDeclarationId,
			kindId(selected.kind),
			semanticTypeId,
			elementSemanticTypeId,
			exactSymbol
		].join("|")).substr(0, 24);
		final requirementId = id + ":runtime:" + capability;
		final profileEligibility = ["metal", "portable"];
		final revision = revisionFor(id, stableOwner, stableProgramRevision, stablePipelineRevision, stableSource, selected.sourceDeclarationId,
			selected.kind, semanticTypeId, elementSemanticTypeId, exactSymbol, profileEligibility, requirementId);
		final occurrence:OcamlRuntimeUseOccurrence = {
			id: id + ":runtime-use:" + RUNTIME_ROLE,
			planRevision: revision,
			ownerId: id,
			requirementId: requirementId,
			domain: OcamlRuntimeUseDomain.TypeIdentifier,
			exactSymbol: exactSymbol,
			role: RUNTIME_ROLE,
			order: 0,
			source: copySource(stableSource),
			profileEligibility: profileEligibility.copy(),
			cardinality: 1
		};
		return {
			decision: {
				id: id,
				revision: revision,
				ownerId: stableOwner,
				programRevision: stableProgramRevision,
				pipelineRevision: stablePipelineRevision,
				source: copySource(stableSource),
				sourceDeclarationId: selected.sourceDeclarationId,
				kind: selected.kind,
				semanticTypeId: semanticTypeId,
				elementSemanticTypeId: elementSemanticTypeId,
				exactSymbol: exactSymbol,
				profileEligibility: profileEligibility,
				runtimeRequirementIds: [requirementId],
				runtimeUseOccurrences: [occurrence],
				proofId: CARRIER_PROOF_ID,
				proofClaim: CARRIER_PROOF_CLAIM
			},
			elementType: selected.elementType
		};
	}

	/** Rejects request-local Array element data that no longer matches its seal. */
	public static function requireMaterialization(materialization:OcamlStandardContainerCarrierMaterialization):Void {
		if (materialization == null)
			throw "reflaxe.ocaml [ocaml-standard-container-carrier:missing-materialization]: standard container type lowering requires a sealed materialization";
		requireDecision(materialization.decision);
		final elementTypeId = materialization.elementType == null ? "<none>" : TypeTools.toString(materialization.elementType);
		if (elementTypeId != materialization.decision.elementSemanticTypeId)
			throw 'reflaxe.ocaml [ocaml-standard-container-carrier:stale-materialization]: carrier "${materialization.decision.id}" no longer matches its request-local element type';
	}
	#end

	/** Rejects changed type, request, runtime, or hidden occurrence facts. */
	public static function requireDecision(decision:OcamlStandardContainerCarrierDecision):Void {
		if (decision == null)
			throw "reflaxe.ocaml [ocaml-standard-container-carrier:missing-decision]: standard container type lowering requires a sealed decision";
		requireSource(decision.id, decision.source);
		final expectedSymbol = symbolForKind(decision.kind);
		final expectedCapability = runtimeCapabilityForKind(decision.kind);
		final expectedRequirementId = decision.id + ":runtime:" + expectedCapability;
		final expectedRevision = revisionFor(decision.id, decision.ownerId, decision.programRevision, decision.pipelineRevision, decision.source,
			decision.sourceDeclarationId, decision.kind, decision.semanticTypeId, decision.elementSemanticTypeId, decision.exactSymbol,
			decision.profileEligibility, expectedRequirementId);
		if (decision.id.length == 0
			|| decision.ownerId.length == 0
			|| decision.programRevision.length == 0
			|| decision.pipelineRevision.length == 0
			|| decision.sourceDeclarationId != sourceDeclarationForKind(decision.kind)
			|| decision.semanticTypeId.length == 0
			|| (decision.kind == ArrayCarrier && decision.elementSemanticTypeId == "<none>")
			|| (decision.kind == BytesCarrier && decision.elementSemanticTypeId != "<none>")
			|| decision.exactSymbol != expectedSymbol
			|| decision.profileEligibility.join(",") != "metal,portable"
			|| decision.runtimeRequirementIds.length != 1
			|| decision.runtimeRequirementIds[0] != expectedRequirementId
			|| decision.runtimeUseOccurrences.length != 1
			|| decision.proofId != CARRIER_PROOF_ID
			|| decision.proofClaim != CARRIER_PROOF_CLAIM
			|| decision.revision != expectedRevision)
			throw 'reflaxe.ocaml [ocaml-standard-container-carrier:stale-decision]: carrier "${decision.id}" no longer matches its sealed type facts';
		final occurrence = decision.runtimeUseOccurrences[0];
		if (occurrence.id != decision.id + ":runtime-use:" + RUNTIME_ROLE
			|| occurrence.planRevision != decision.revision
			|| occurrence.ownerId != decision.id
			|| occurrence.requirementId != expectedRequirementId
			|| occurrence.domain != OcamlRuntimeUseDomain.TypeIdentifier
			|| occurrence.exactSymbol != expectedSymbol
			|| occurrence.role != RUNTIME_ROLE
			|| occurrence.order != 0
			|| occurrence.source.file != decision.source.file
			|| occurrence.source.min != decision.source.min
			|| occurrence.source.max != decision.source.max
			|| occurrence.profileEligibility.join(",") != "metal,portable"
			|| occurrence.cardinality != 1)
			throw 'reflaxe.ocaml [ocaml-standard-container-carrier:stale-runtime-use]: carrier "${decision.id}" has changed runtime-use facts';
	}

	/** Returns a plain-value copy for request-owned final-output staging. */
	public static function copyDecision(decision:OcamlStandardContainerCarrierDecision):OcamlStandardContainerCarrierDecision {
		requireDecision(decision);
		return {
			id: decision.id,
			revision: decision.revision,
			ownerId: decision.ownerId,
			programRevision: decision.programRevision,
			pipelineRevision: decision.pipelineRevision,
			source: copySource(decision.source),
			sourceDeclarationId: decision.sourceDeclarationId,
			kind: decision.kind,
			semanticTypeId: decision.semanticTypeId,
			elementSemanticTypeId: decision.elementSemanticTypeId,
			exactSymbol: decision.exactSymbol,
			profileEligibility: decision.profileEligibility.copy(),
			runtimeRequirementIds: decision.runtimeRequirementIds.copy(),
			runtimeUseOccurrences: decision.runtimeUseOccurrences.map(copyOccurrence),
			proofId: decision.proofId,
			proofClaim: decision.proofClaim
		};
	}

	public static function symbolForKind(kind:OcamlStandardContainerCarrierKind):String {
		return switch (kind) {
			case ArrayCarrier: "HxArray.t";
			case BytesCarrier: "HxBytes.t";
		};
	}

	public static function runtimeModuleForKind(kind:OcamlStandardContainerCarrierKind):String {
		return switch (kind) {
			case ArrayCarrier: "HxArray";
			case BytesCarrier: "HxBytes";
		};
	}

	public static function runtimeCapabilityForKind(kind:OcamlStandardContainerCarrierKind):String {
		return switch (kind) {
			case ArrayCarrier: ARRAY_RUNTIME_CAPABILITY;
			case BytesCarrier: BYTES_RUNTIME_CAPABILITY;
		};
	}

	public static function implementationFeatureForKind(kind:OcamlStandardContainerCarrierKind):String {
		return switch (kind) {
			case ArrayCarrier: "haxe-array-carrier-v1";
			case BytesCarrier: "haxe-bytes-carrier-v1";
		};
	}

	#if macro
	static function select(type:Type):Null<{
		sourceDeclarationId:String,
		source:OcamlLoweredSourceSpan,
		kind:OcamlStandardContainerCarrierKind,
		elementType:Null<Type>
	}> {
		return switch (type) {
			case TInst(classRef, parameters):
				final classType = classRef.get();
				final rewrittenName = (classType.pack ?? []).concat([classType.name]).join(".");
				final sourceDeclarationId = OcamlTypedDeclarationIdentity.canonicalSourceName(classType.meta, rewrittenName, "a class");
				switch (sourceDeclarationId) {
					case "Array" if (parameters.length == 1):
						{
							sourceDeclarationId: sourceDeclarationId,
							source: OcamlLoweredOrigin.sourceSpan(classType.pos),
							kind: ArrayCarrier,
							elementType: parameters[0]
						};
					case "haxe.io.Bytes" if (parameters.length == 0):
						{
							sourceDeclarationId: sourceDeclarationId,
							source: OcamlLoweredOrigin.sourceSpan(classType.pos),
							kind: BytesCarrier,
							elementType: null
						};
					case _:
						null;
				}
			case _:
				null;
		};
	}
	#end

	static function sourceDeclarationForKind(kind:OcamlStandardContainerCarrierKind):String {
		return switch (kind) {
			case ArrayCarrier: "Array";
			case BytesCarrier: "haxe.io.Bytes";
		};
	}

	static function kindId(kind:OcamlStandardContainerCarrierKind):String {
		return switch (kind) {
			case ArrayCarrier: "array";
			case BytesCarrier: "bytes";
		};
	}

	static function revisionFor(id:String, ownerId:String, programRevision:String, pipelineRevision:String, source:OcamlLoweredSourceSpan,
			sourceDeclarationId:String, kind:OcamlStandardContainerCarrierKind, semanticTypeId:String, elementSemanticTypeId:String, exactSymbol:String,
			profileEligibility:Array<String>, requirementId:String):String {
		final fields = [
			CARRIER_PROOF_ID,
			id,
			ownerId,
			programRevision,
			pipelineRevision,
			source.file,
			Std.string(source.min),
			Std.string(source.max),
			sourceDeclarationId,
			kindId(kind),
			semanticTypeId,
			elementSemanticTypeId,
			exactSymbol,
			profileEligibility.join(","),
			requirementId,
			RUNTIME_ROLE,
			CARRIER_PROOF_CLAIM
		];
		return "sha256:" + Sha256.encode(fields.map(value -> value.length + ":" + value).join("|"));
	}

	static function required(value:String, label:String):String {
		if (value == null || StringTools.trim(value).length == 0)
			throw 'reflaxe.ocaml [ocaml-standard-container-carrier:invalid-$label]: standard container carrier requires a non-empty $label';
		return value;
	}

	static function requireSource(ownerId:String, source:OcamlLoweredSourceSpan):Void {
		if (source == null || source.file == null || source.file.length == 0 || source.min < 0 || source.max < source.min)
			throw 'reflaxe.ocaml [ocaml-standard-container-carrier:invalid-source]: carrier "$ownerId" has no valid source span';
	}

	static function copySource(source:OcamlLoweredSourceSpan):OcamlLoweredSourceSpan {
		return {file: source.file, min: source.min, max: source.max};
	}

	static function copyOccurrence(source:OcamlRuntimeUseOccurrence):OcamlRuntimeUseOccurrence {
		return {
			id: source.id,
			planRevision: source.planRevision,
			ownerId: source.ownerId,
			requirementId: source.requirementId,
			domain: source.domain,
			exactSymbol: source.exactSymbol,
			role: source.role,
			order: source.order,
			source: copySource(source.source),
			profileEligibility: source.profileEligibility.copy(),
			cardinality: source.cardinality
		};
	}
}
#end
