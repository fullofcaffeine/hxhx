package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
import haxe.crypto.Sha256;
#if macro
import haxe.macro.Context;
import haxe.macro.Type.ClassType;
import haxe.macro.Type.ClassField;
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypeTools;
#end
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/**
	The concrete OCaml carrier required by one standard Haxe Map declaration.

	The kind comes from the canonical Haxe source declaration, not the shared
	`HxMap` native symbol. This preserves key semantics after `@:native` rewrites
	`StringMap`, `IntMap`, and `ObjectMap` to the same target module.
**/
enum OcamlStandardMapCarrierKind {
	StringKeys;
	IntKeys;
	ObjectIdentityKeys;
}

/** One immutable choice of private OCaml storage for a standard Haxe Map type. */
typedef OcamlStandardMapCarrierDecision = {
	final id:String;
	final revision:String;
	final ownerId:String;
	final programRevision:String;
	final pipelineRevision:String;
	final source:OcamlLoweredSourceSpan;
	final sourceDeclarationId:String;
	final kind:OcamlStandardMapCarrierKind;
	final keySemanticTypeId:String;
	final valueSemanticTypeId:String;
	final exactSymbol:String;
	final profileEligibility:Array<String>;
	final runtimeRequirementIds:Array<String>;
	final runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence>;
	final proofId:String;
	final proofClaim:String;
}

#if macro
/**
	Request-local Haxe types used to build one sealed carrier decision.

	The decision contains only plain values. These `Type` values stay inside the
	active compiler request and only provide parameters for ordinary type lowering.
**/
typedef OcamlStandardMapCarrierMaterialization = {
	final decision:OcamlStandardMapCarrierDecision;
	final keyType:Null<Type>;
	final valueType:Null<Type>;
}
#end

/** Typed evidence for one exact target-authored standard Map pair iterator. */
typedef OcamlStandardMapPairProducer = {
	final sourceDeclarationId:String;
	final iteratorSemanticTypeId:String;
	final keySemanticTypeId:String;
	final valueSemanticTypeId:String;
	final proofId:String;
	final proofClaim:String;
}

/**
	Classifies standard Map declarations from their typed source identity.
**/
class OcamlStandardMapCarrierContract {
	public static inline final CARRIER_PROOF_ID = "typed-standard-map-carrier-runtime-use-v1";
	public static inline final CARRIER_PROOF_CLAIM = "The final Haxe type is the canonical haxe.ds.Map abstract or the canonical haxe.ds.StringMap, IntMap, or ObjectMap class. Its exact key family and key/value semantic types select one HxMap carrier name before OCaml type syntax. A target name, native rewrite, or generated type string alone does not authorize the carrier.";
	public static inline final MAP_RUNTIME_CAPABILITY = OcamlRuntimeRequirementLedger.HAXE_MAP;
	public static inline final RUNTIME_ROLE = "standard-map-carrier-type";
	public static inline final PAIR_PRODUCER_PROOF_ID = "target-native-standard-map-pair-producer-v1";
	public static inline final PAIR_PRODUCER_PROOF_CLAIM = "The final typed iterator initializer is the exact target-authored NativeHxMapIterator.of_array call around NativeHxMap.pairs_string, pairs_int, or pairs_object. The nested pair helper's Array<{key:K,value:V}> result determines the key and value types before field syntax. A shared native symbol, an arbitrary Iterator of anonymous objects, anonymous shape, or the key/value field names alone do not satisfy this proof.";

	#if macro
	/**
		Returns the standard carrier kind, or `null` for a non-Map declaration.
	**/
	public static function kindForClass(classType:ClassType):Null<OcamlStandardMapCarrierKind> {
		final rewrittenName = (classType.pack ?? []).concat([classType.name]).join(".");
		final sourceName = OcamlTypedDeclarationIdentity.canonicalSourceName(classType.meta, rewrittenName, "a class");
		return switch (sourceName) {
			case "haxe.ds.StringMap": StringKeys;
			case "haxe.ds.IntMap": IntKeys;
			case "haxe.ds.ObjectMap": ObjectIdentityKeys;
			case _: null;
		};
	}
	#end

	#if macro
	/**
		Seals the concrete OCaml storage type for one exact standard Haxe Map type.

		The owner identifies one target type occurrence. The returned Haxe `Type`
		values are request-local; only `decision` can enter reports or durable plans.
	**/
	public static function seal(type:Type, ownerId:String, programRevision:String, pipelineRevision:String,
			?source:OcamlLoweredSourceSpan):Null<OcamlStandardMapCarrierMaterialization> {
		final selected = select(type);
		if (selected == null)
			return null;
		final stableOwner = required(ownerId, "owner identity");
		final stableProgramRevision = required(programRevision, "program revision");
		final stablePipelineRevision = required(pipelineRevision, "target pipeline revision");
		final stableSource = source == null ? selected.source : source;
		requireSource(stableOwner, stableSource);
		final keySemanticTypeId = semanticTypeId(selected.keyType);
		final valueSemanticTypeId = semanticTypeId(selected.valueType);
		final exactSymbol = symbolForKind(selected.kind);
		final id = "standard-map-carrier:" + Sha256.encode([
			stableOwner,
			stableProgramRevision,
			stablePipelineRevision,
			stableSource.file,
			Std.string(stableSource.min),
			Std.string(stableSource.max),
			selected.sourceDeclarationId,
			kindId(selected.kind),
			keySemanticTypeId,
			valueSemanticTypeId,
			exactSymbol
		].join("|")).substr(0, 24);
		final requirementId = id + ":runtime:" + MAP_RUNTIME_CAPABILITY;
		final profileEligibility = ["metal", "portable"];
		final revision = revisionFor(id, stableOwner, stableProgramRevision, stablePipelineRevision, stableSource, selected.sourceDeclarationId,
			selected.kind, keySemanticTypeId, valueSemanticTypeId, exactSymbol, profileEligibility, requirementId);
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
				keySemanticTypeId: keySemanticTypeId,
				valueSemanticTypeId: valueSemanticTypeId,
				exactSymbol: exactSymbol,
				profileEligibility: profileEligibility,
				runtimeRequirementIds: [requirementId],
				runtimeUseOccurrences: [occurrence],
				proofId: CARRIER_PROOF_ID,
				proofClaim: CARRIER_PROOF_CLAIM
			},
			keyType: selected.keyType,
			valueType: selected.valueType
		};
	}

	/** Rejects a request-local materialization that no longer matches its decision. */
	public static function requireMaterialization(materialization:OcamlStandardMapCarrierMaterialization):Void {
		if (materialization == null)
			throw "reflaxe.ocaml [ocaml-standard-map-carrier:missing-materialization]: standard Map carrier type lowering requires a sealed materialization";
		requireDecision(materialization.decision);
		if (semanticTypeId(materialization.keyType) != materialization.decision.keySemanticTypeId
			|| semanticTypeId(materialization.valueType) != materialization.decision.valueSemanticTypeId)
			throw 'reflaxe.ocaml [ocaml-standard-map-carrier:stale-materialization]: carrier "${materialization.decision.id}" no longer matches its request-local key and value types';
	}
	#end

	/** Rejects changed carrier facts before they can authorize target syntax. */
	public static function requireDecision(decision:OcamlStandardMapCarrierDecision):Void {
		if (decision == null)
			throw "reflaxe.ocaml [ocaml-standard-map-carrier:missing-decision]: standard Map carrier type lowering requires a sealed decision";
		requireSource(decision.id, decision.source);
		final expectedSymbol = symbolForKind(decision.kind);
		final expectedRequirementId = decision.id + ":runtime:" + MAP_RUNTIME_CAPABILITY;
		final expectedRevision = revisionFor(decision.id, decision.ownerId, decision.programRevision, decision.pipelineRevision, decision.source,
			decision.sourceDeclarationId, decision.kind, decision.keySemanticTypeId, decision.valueSemanticTypeId, decision.exactSymbol,
			decision.profileEligibility, expectedRequirementId);
		if (decision.id.length == 0
			|| decision.ownerId.length == 0
			|| decision.programRevision.length == 0
			|| decision.pipelineRevision.length == 0
			|| decision.sourceDeclarationId.length == 0
			|| decision.keySemanticTypeId.length == 0
			|| decision.valueSemanticTypeId.length == 0
			|| decision.exactSymbol != expectedSymbol
			|| decision.profileEligibility.join(",") != "metal,portable"
			|| decision.runtimeRequirementIds.length != 1
			|| decision.runtimeRequirementIds[0] != expectedRequirementId
			|| decision.runtimeUseOccurrences.length != 1
			|| decision.proofId != CARRIER_PROOF_ID
			|| decision.proofClaim != CARRIER_PROOF_CLAIM
			|| decision.revision != expectedRevision)
			throw 'reflaxe.ocaml [ocaml-standard-map-carrier:stale-decision]: carrier "${decision.id}" no longer matches its sealed type facts';
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
			throw 'reflaxe.ocaml [ocaml-standard-map-carrier:stale-runtime-use]: carrier "${decision.id}" has changed runtime-use facts';
	}

	/**
		Returns a detached copy that can stay in request-owned staging state.

		The type mapper can discard a candidate target type before final output. The
		copy therefore retains only checked strings, numbers, enums, and arrays. It
		does not retain the Haxe `Type` objects used to select the carrier.
	**/
	public static function copyDecision(decision:OcamlStandardMapCarrierDecision):OcamlStandardMapCarrierDecision {
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
			keySemanticTypeId: decision.keySemanticTypeId,
			valueSemanticTypeId: decision.valueSemanticTypeId,
			exactSymbol: decision.exactSymbol,
			profileEligibility: decision.profileEligibility.copy(),
			runtimeRequirementIds: decision.runtimeRequirementIds.copy(),
			runtimeUseOccurrences: decision.runtimeUseOccurrences.map(copyOccurrence),
			proofId: decision.proofId,
			proofClaim: decision.proofClaim
		};
	}

	#if macro
	/**
		Recognizes the final target-authored standard Map pair iterator.

		The target's standard `StringMap`, `IntMap`, and `ObjectMap` methods are
		inlined before this planner runs. Their final typed form is the exact
		`NativeHxMapIterator.of_array(NativeHxMap.pairs_*(map))` helper chain.
		Retaining that complete declaration chain lets later field planning
		preserve the tuple carrier without accepting arbitrary pair-shaped values.
	**/
	public static function pairProducerForExpression(expression:TypedExpr):Null<OcamlStandardMapPairProducer> {
		final selected = switch (expression.expr) {
			case TCall({expr: TField(_, FStatic(iteratorClassRef, iteratorFieldRef))}, [pairsExpression]):
				final iteratorClass = iteratorClassRef.get();
				final iteratorSource = OcamlTypedDeclarationIdentity.canonicalSourceName(iteratorClass.meta,
					(iteratorClass.pack ?? []).concat([iteratorClass.name]).join("."), "a class");
				if (iteratorSource != "haxe.ds.NativeHxMapIterator"
					|| iteratorFieldRef.get().name != "of_array") null; else switch (pairsExpression.expr) {
					case TCall({expr: TField(_, FStatic(mapClassRef, pairsFieldRef))}, [_]):
						final mapClass = mapClassRef.get();
						final mapSource = OcamlTypedDeclarationIdentity.canonicalSourceName(mapClass.meta,
							(mapClass.pack ?? []).concat([mapClass.name]).join("."), "a class");
						final pairFunction = pairsFieldRef.get().name;
						if (mapSource == "haxe.ds.NativeHxMap"
							&& (pairFunction == "pairs_string" || pairFunction == "pairs_int" || pairFunction == "pairs_object")) {
							{pairsExpression: pairsExpression, pairFunction: pairFunction};
						} else null;
					case _:
						null;
				}
			case _:
				null;
		}
		if (selected == null)
			return null;
		final types = pairTypesFromArray(selected.pairsExpression.t);
		if (types == null
			|| (selected.pairFunction == "pairs_string" && types.key != "String")
			|| (selected.pairFunction == "pairs_int" && types.key != "Int")
			|| (selected.pairFunction == "pairs_object" && (types.key == "String" || types.key == "Int")))
			return null;
		return {
			sourceDeclarationId: 'haxe.ds.NativeHxMapIterator.of_array(haxe.ds.NativeHxMap.${selected.pairFunction})',
			iteratorSemanticTypeId: TypeTools.toString(expression.t),
			keySemanticTypeId: types.key,
			valueSemanticTypeId: types.value,
			proofId: PAIR_PRODUCER_PROOF_ID,
			proofClaim: PAIR_PRODUCER_PROOF_CLAIM
		};
	}

	static function pairTypesFromArray(type:Type):Null<{key:String, value:String}> {
		return switch (TypeTools.follow(type)) {
			case TInst(arrayRef, [pairType]) if (arrayRef.get().pack.length == 0 && arrayRef.get().name == "Array"):
				switch (TypeTools.follow(pairType)) {
					case TAnonymous(anonymousRef): pairTypesFromFields(anonymousRef.get().fields);
					case _:
						null;
				}
			case _:
				null;
		}
	}

	static function pairTypesFromFields(fields:Array<ClassField>):Null<{key:String, value:String}> {
		final key = Lambda.find(fields, field -> field.name == "key");
		final value = Lambda.find(fields, field -> field.name == "value");
		return key == null || value == null ? null : {
			key: TypeTools.toString(key.type),
			value: TypeTools.toString(value.type)
		};
	}
	#end

	public static function symbolForKind(kind:OcamlStandardMapCarrierKind):String {
		return switch (kind) {
			case StringKeys: "HxMap.string_map";
			case IntKeys: "HxMap.int_map";
			case ObjectIdentityKeys: "HxMap.obj_map";
		};
	}

	static function kindId(kind:OcamlStandardMapCarrierKind):String {
		return switch (kind) {
			case StringKeys: "string";
			case IntKeys: "int";
			case ObjectIdentityKeys: "object-identity";
		};
	}

	#if macro
	static function select(type:Type):Null<{
		sourceDeclarationId:String,
		source:OcamlLoweredSourceSpan,
		kind:OcamlStandardMapCarrierKind,
		keyType:Null<Type>,
		valueType:Null<Type>
	}> {
		return switch (type) {
			case TInst(classRef, parameters):
				final classType = classRef.get();
				final kind = kindForClass(classType);
				if (kind == null) {
					null;
				} else {
					final sourceDeclarationId = OcamlTypedDeclarationIdentity.canonicalSourceName(classType.meta,
						(classType.pack ?? []).concat([classType.name]).join("."), "a class");
					switch (kind) {
						case StringKeys:
							{
								sourceDeclarationId: sourceDeclarationId,
								source: OcamlLoweredOrigin.sourceSpan(classType.pos),
								kind: kind,
								keyType: Context.getType("String"),
								valueType: parameters.length > 0 ? parameters[0] : null
							};
						case IntKeys:
							{
								sourceDeclarationId: sourceDeclarationId,
								source: OcamlLoweredOrigin.sourceSpan(classType.pos),
								kind: kind,
								keyType: Context.getType("Int"),
								valueType: parameters.length > 0 ? parameters[0] : null
							};
						case ObjectIdentityKeys:
							{
								sourceDeclarationId: sourceDeclarationId,
								source: OcamlLoweredOrigin.sourceSpan(classType.pos),
								kind: kind,
								keyType: parameters.length > 0 ? parameters[0] : null,
								valueType: parameters.length > 1 ? parameters[1] : null
							};
					}
				}
			case TAbstract(abstractRef, parameters):
				final abstractType = abstractRef.get();
				final rewrittenName = (abstractType.pack ?? []).concat([abstractType.name]).join(".");
				final sourceDeclarationId = OcamlTypedDeclarationIdentity.canonicalSourceName(abstractType.meta, rewrittenName, "an abstract");
				if (sourceDeclarationId != "haxe.ds.Map") {
					null;
				} else {
					final keyType:Null<Type> = parameters.length > 0 ? parameters[0] : null;
					final valueType:Null<Type> = parameters.length > 1 ? parameters[1] : null;
					{
						sourceDeclarationId: sourceDeclarationId,
						source: OcamlLoweredOrigin.sourceSpan(abstractType.pos),
						kind: keyKind(keyType),
						keyType: keyType,
						valueType: valueType
					};
				}
			case TType(typeRef, parameters):
				final typeDefinition = typeRef.get();
				final rewrittenName = (typeDefinition.pack ?? []).concat([typeDefinition.name]).join(".");
				final sourceDeclarationId = OcamlTypedDeclarationIdentity.canonicalSourceName(typeDefinition.meta, rewrittenName, "a typedef");
				final resolvesToStandardMap = switch (TypeTools.follow(type)) {
					case TAbstract(abstractRef, _):
						final abstractType = abstractRef.get();
						final abstractName = OcamlTypedDeclarationIdentity.canonicalSourceName(abstractType.meta,
							(abstractType.pack ?? []).concat([abstractType.name]).join("."), "an abstract");
						abstractName == "haxe.ds.Map";
					case _:
						false;
				};
				if (sourceDeclarationId != "Map" || !resolvesToStandardMap) {
					null;
				} else {
					final keyType:Null<Type> = parameters.length > 0 ? parameters[0] : null;
					final valueType:Null<Type> = parameters.length > 1 ? parameters[1] : null;
					{
						sourceDeclarationId: sourceDeclarationId,
						source: OcamlLoweredOrigin.sourceSpan(typeDefinition.pos),
						kind: keyKind(keyType),
						keyType: keyType,
						valueType: valueType
					};
				}
			case _:
				null;
		};
	}

	static function keyKind(keyType:Null<Type>):OcamlStandardMapCarrierKind {
		if (keyType == null)
			return OcamlStandardMapCarrierKind.ObjectIdentityKeys;
		return switch (TypeTools.follow(keyType)) {
			case TInst(classRef, _) if (classRef.get().pack.length == 0 && classRef.get().name == "String"):
				OcamlStandardMapCarrierKind.StringKeys;
			case TAbstract(abstractRef, _) if (abstractRef.get().pack.length == 0 && abstractRef.get().name == "Int"):
				OcamlStandardMapCarrierKind.IntKeys;
			case _:
				OcamlStandardMapCarrierKind.ObjectIdentityKeys;
		};
	}

	static function semanticTypeId(type:Null<Type>):String {
		return type == null ? "<unspecified>" : TypeTools.toString(type);
	}
	#end

	static function revisionFor(id:String, ownerId:String, programRevision:String, pipelineRevision:String, source:OcamlLoweredSourceSpan,
			sourceDeclarationId:String, kind:OcamlStandardMapCarrierKind, keySemanticTypeId:String, valueSemanticTypeId:String, exactSymbol:String,
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
			keySemanticTypeId,
			valueSemanticTypeId,
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
			throw 'reflaxe.ocaml [ocaml-standard-map-carrier:invalid-$label]: standard Map carrier requires a non-empty $label';
		return value;
	}

	static function requireSource(ownerId:String, source:OcamlLoweredSourceSpan):Void {
		if (source == null || source.file == null || source.file.length == 0 || source.min < 0 || source.max < source.min)
			throw 'reflaxe.ocaml [ocaml-standard-map-carrier:invalid-source]: carrier "$ownerId" has no valid source span';
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
