package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
import haxe.crypto.Sha256;
#if macro
import haxe.macro.Type.ClassType;
#end
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/** One generated class record whose runtime class marker has an exact owner. */
typedef OcamlClassIdentityMarkerDecision = {
	final id:String;
	final revision:String;
	final programRevision:String;
	final pipelineRevision:String;
	final source:OcamlLoweredSourceSpan;
	final sourceDeclarationId:String;
	final runtimeClassName:String;
	final emissionRole:String;
	final profileEligibility:Array<String>;
	final runtimeRequirementIds:Array<String>;
	final runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence>;
	final proofId:String;
	final proofClaim:String;
}

/**
	Authorizes the private runtime class marker in one generated class record.

	Every class instance stores a marker that lets `Type.getClass` recover its
	Haxe class. The ordinary constructor and `Type.createEmptyInstance` each emit
	their own record, so each output location receives a separate permission.
**/
class OcamlClassIdentityMarkerPlan {
	public static inline final MODEL_REVISION = "ocaml-class-identity-marker-v1";
	public static inline final CONSTRUCTOR_ROLE = "constructor-record";
	public static inline final EMPTY_INSTANCE_ROLE = "empty-instance-record";
	public static inline final EXACT_SYMBOL = "HxType.class_";
	public static inline final RUNTIME_CAPABILITY = "haxe-class-identity-marker";
	public static inline final IMPLEMENTATION_FEATURE = "haxe-class-identity-marker-v1";
	public static inline final RUNTIME_ROLE = "class-identity-marker";
	public static inline final PROOF_ID = "typed-class-identity-marker-runtime-use-v1";
	public static inline final PROOF_CLAIM = "The final typed Haxe class and one exact generated record role authorize one HxType.class_ marker. The constructor record and empty-instance record do not share an occurrence identity.";

	#if macro
	/** Seals one class-marker occurrence from an exact typed class declaration. */
	public static function seal(classType:ClassType, runtimeClassName:String, emissionRole:String, programRevision:String,
			pipelineRevision:String):OcamlClassIdentityMarkerDecision {
		if (classType == null)
			throw "reflaxe.ocaml [ocaml-class-marker:missing-class]: class identity marker requires a typed Haxe class";
		final rewrittenName = (classType.pack ?? []).concat([classType.name]).join(".");
		final stableRuntimeName = required(runtimeClassName, "runtime class name");
		if (stableRuntimeName != rewrittenName)
			throw 'reflaxe.ocaml [ocaml-class-marker:wrong-runtime-name]: typed class $rewrittenName cannot authorize marker name $stableRuntimeName';
		final sourceDeclarationId = OcamlTypedDeclarationIdentity.canonicalSourceName(classType.meta, rewrittenName, "a class marker declaration");
		final source = OcamlLoweredOrigin.sourceSpan(classType.pos);
		final stableRole = requireRole(emissionRole);
		final stableProgramRevision = required(programRevision, "program revision");
		final stablePipelineRevision = required(pipelineRevision, "target pipeline revision");
		requireSource(sourceDeclarationId, source);
		final id = idFor(sourceDeclarationId, stableRuntimeName, stableRole, stableProgramRevision, stablePipelineRevision, source);
		final requirementId = id + ":runtime:" + RUNTIME_CAPABILITY;
		final profiles = ["metal", "portable"];
		final revision = revisionFor(id, stableProgramRevision, stablePipelineRevision, source, sourceDeclarationId, stableRuntimeName, stableRole, profiles,
			requirementId);
		final occurrence:OcamlRuntimeUseOccurrence = {
			id: id + ":runtime-use:" + RUNTIME_ROLE,
			planRevision: revision,
			ownerId: id,
			requirementId: requirementId,
			domain: OcamlRuntimeUseDomain.ExpressionIdentifier,
			exactSymbol: EXACT_SYMBOL,
			role: RUNTIME_ROLE,
			order: 0,
			source: copySource(source),
			profileEligibility: profiles.copy(),
			cardinality: 1
		};
		return {
			id: id,
			revision: revision,
			programRevision: stableProgramRevision,
			pipelineRevision: stablePipelineRevision,
			source: copySource(source),
			sourceDeclarationId: sourceDeclarationId,
			runtimeClassName: stableRuntimeName,
			emissionRole: stableRole,
			profileEligibility: profiles,
			runtimeRequirementIds: [requirementId],
			runtimeUseOccurrences: [occurrence],
			proofId: PROOF_ID,
			proofClaim: PROOF_CLAIM
		};
	}
	#end

	/** Rejects changed class, request, output-role, requirement, or use facts. */
	public static function requireDecision(decision:OcamlClassIdentityMarkerDecision):Void {
		if (decision == null)
			throw "reflaxe.ocaml [ocaml-class-marker:missing-decision]: class identity marker requires a sealed decision";
		requireSource(decision.sourceDeclarationId, decision.source);
		final stableRole = requireRole(decision.emissionRole);
		final expectedId = idFor(decision.sourceDeclarationId, decision.runtimeClassName, stableRole, decision.programRevision, decision.pipelineRevision,
			decision.source);
		final expectedRequirementId = expectedId + ":runtime:" + RUNTIME_CAPABILITY;
		final expectedRevision = revisionFor(expectedId, decision.programRevision, decision.pipelineRevision, decision.source, decision.sourceDeclarationId,
			decision.runtimeClassName, stableRole, decision.profileEligibility, expectedRequirementId);
		if (decision.id != expectedId
			|| decision.runtimeClassName.length == 0
			|| decision.profileEligibility.join(",") != "metal,portable"
			|| decision.runtimeRequirementIds.length != 1
			|| decision.runtimeRequirementIds[0] != expectedRequirementId
			|| decision.runtimeUseOccurrences.length != 1
			|| decision.proofId != PROOF_ID
			|| decision.proofClaim != PROOF_CLAIM
			|| decision.revision != expectedRevision)
			throw 'reflaxe.ocaml [ocaml-class-marker:stale-decision]: marker "${decision.id}" no longer matches its sealed class or output role';
		final occurrence = decision.runtimeUseOccurrences[0];
		if (occurrence.id != decision.id + ":runtime-use:" + RUNTIME_ROLE
			|| occurrence.planRevision != decision.revision
			|| occurrence.ownerId != decision.id
			|| occurrence.requirementId != expectedRequirementId
			|| occurrence.domain != OcamlRuntimeUseDomain.ExpressionIdentifier
			|| occurrence.exactSymbol != EXACT_SYMBOL
			|| occurrence.role != RUNTIME_ROLE
			|| occurrence.order != 0
			|| occurrence.source.file != decision.source.file
			|| occurrence.source.min != decision.source.min
			|| occurrence.source.max != decision.source.max
			|| occurrence.profileEligibility.join(",") != "metal,portable"
			|| occurrence.cardinality != 1)
			throw 'reflaxe.ocaml [ocaml-class-marker:stale-runtime-use]: marker "${decision.id}" has changed runtime-use facts';
	}

	static function idFor(sourceDeclarationId:String, runtimeClassName:String, emissionRole:String, programRevision:String, pipelineRevision:String,
			source:OcamlLoweredSourceSpan):String {
		final fields = [
			required(sourceDeclarationId, "source declaration identity"),
			required(runtimeClassName, "runtime class name"),
			requireRole(emissionRole),
			required(programRevision, "program revision"),
			required(pipelineRevision, "target pipeline revision"),
			source.file,
			Std.string(source.min),
			Std.string(source.max)
		];
		return "class-identity-marker:" + Sha256.encode(fields.map(value -> value.length + ":" + value).join("|")).substr(0, 24);
	}

	static function revisionFor(id:String, programRevision:String, pipelineRevision:String, source:OcamlLoweredSourceSpan, sourceDeclarationId:String,
			runtimeClassName:String, emissionRole:String, profileEligibility:Array<String>, requirementId:String):String {
		final fields = [
			MODEL_REVISION,
			id,
			programRevision,
			pipelineRevision,
			source.file,
			Std.string(source.min),
			Std.string(source.max),
			sourceDeclarationId,
			runtimeClassName,
			emissionRole,
			profileEligibility.join(","),
			requirementId,
			EXACT_SYMBOL,
			RUNTIME_ROLE,
			PROOF_ID,
			PROOF_CLAIM
		];
		return "sha256:" + Sha256.encode(fields.map(value -> value.length + ":" + value).join("|"));
	}

	static function requireRole(role:String):String {
		return switch (required(role, "emission role")) {
			case CONSTRUCTOR_ROLE: CONSTRUCTOR_ROLE;
			case EMPTY_INSTANCE_ROLE: EMPTY_INSTANCE_ROLE;
			case other: throw 'reflaxe.ocaml [ocaml-class-marker:unsupported-role]: class identity marker cannot be emitted for $other';
		};
	}

	static function required(value:String, label:String):String {
		if (value == null || StringTools.trim(value).length == 0)
			throw 'reflaxe.ocaml [ocaml-class-marker:invalid-$label]: class identity marker requires a non-empty $label';
		return value;
	}

	static function requireSource(ownerId:String, source:OcamlLoweredSourceSpan):Void {
		if (source == null || source.file == null || source.file.length == 0 || source.min < 0 || source.max < source.min)
			throw 'reflaxe.ocaml [ocaml-class-marker:invalid-source]: class "$ownerId" has no valid source span';
	}

	static function copySource(source:OcamlLoweredSourceSpan):OcamlLoweredSourceSpan {
		return {file: source.file, min: source.min, max: source.max};
	}
}
#end
