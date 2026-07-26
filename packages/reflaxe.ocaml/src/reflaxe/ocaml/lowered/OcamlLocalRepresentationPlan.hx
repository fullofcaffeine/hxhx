package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;

/** How syntax construction must convert one value crossing a local-carrier boundary. */
enum abstract OcamlLocalCarrierConversion(String) from String to String {
	/** The family has not yet migrated this conversion into the sealed plan. */
	final LegacyCoercion = "legacy-coercion";

	/** The typed value already uses exactly the selected carrier. */
	final Identity = "identity";

	/** A null sentinel or existing exact `Null<Int>` already uses `Obj.t`. */
	final PreserveNullableIntCarrier = "preserve-nullable-int-carrier";

	/** An exact non-null Haxe Int must enter `Obj.t` through `Obj.repr`. */
	final BoxExactIntToNullableInt = "box-exact-int-to-nullable-int";

	/** A flow-refined `Null<Int>` read must reject null before returning `int`. */
	final CheckedUnboxNullableInt = "checked-unbox-nullable-int";
}

/** The source role that requires one local-carrier conversion. */
enum abstract OcamlLocalConversionRole(String) from String to String {
	final Initializer = "initializer";
	final Assignment = "assignment";
	final Read = "read";
}

/** Unsafe target mechanism justified by one admitted local conversion. */
enum abstract OcamlUnsafeOperationKind(String) from String to String {
	final ObjReprExactInt = "obj-repr-exact-int";
	final CheckedNullableIntUnwrap = "checked-nullable-int-unwrap";
}

/** Revision-bound proof for one admitted unsafe target operation. */
typedef OcamlUnsafeOperationRecord = {
	final id:String;
	final conversionId:String;
	final operation:OcamlUnsafeOperationKind;
	final source:OcamlLoweredSourceSpan;
	final inputSemanticTypeId:String;
	final inputCarrierTypeId:String;
	final outputSemanticTypeId:String;
	final outputCarrierTypeId:String;
	final reason:String;
	final proofId:String;
	final proofClaim:String;
	final profileEligibility:Array<String>;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/** One immutable answer for one initializer, assignment, or read occurrence. */
typedef OcamlLocalConversionDecision = {
	final id:String;
	final localId:Int;
	final role:OcamlLocalConversionRole;
	final source:OcamlLoweredSourceSpan;
	final inputSemanticTypeId:String;
	final inputCarrierTypeId:String;
	final outputSemanticTypeId:String;
	final outputCarrierTypeId:String;
	final conversion:OcamlLocalCarrierConversion;
	final reason:String;
	final proofId:String;
	final proofClaim:String;
	final profileEligibility:Array<String>;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
	final unsafeOperation:Null<OcamlUnsafeOperationRecord>;
}

/** One function-local reference to a program-owned representation decision. */
typedef OcamlLocalRepresentationReference = {
	final localId:Int;
	final representationId:String;
	final semanticTypeId:String;
	final domain:OcamlRepresentationDomain;
}

/** Complete representation status for one admitted or mutated local. */
enum OcamlLocalRepresentationChoice {
	/** Syntax must resolve this exact program-owned decision. */
	ProgramDecision(representationId:String, semanticTypeId:String, domain:OcamlRepresentationDomain);

	/** This semantic type remains deliberately on the legacy mapper for now. */
	Unmigrated(semanticTypeId:String);
}

/** One explicit representation and local-carrier conversion choice for a local. */
typedef OcamlLocalRepresentationDecision = {
	final localId:Int;
	final choice:OcamlLocalRepresentationChoice;
	final initializerConversion:OcamlLocalCarrierConversion;
	final assignmentConversion:OcamlLocalCarrierConversion;
	final readConversion:OcamlLocalCarrierConversion;
}

/**
	Immutable representation references for admitted or mutated locals in one function.

	The program registry owns carrier policy. This function plan retains only the
	stable decision identity selected for each local, so syntax construction can
	validate and consume the answer without reclassifying the Haxe type. Carrier
	conversions are sealed separately so initialization, whole-value
	replacement, and reads cannot fall back to generic same-class casts.
**/
class OcamlLocalRepresentationPlan {
	final orderedDecisions:Array<OcamlLocalRepresentationDecision>;
	final decisionsByLocalId:Map<Int, OcamlLocalRepresentationDecision> = [];
	final orderedConversions:Array<OcamlLocalConversionDecision>;
	final conversionsById:Map<String, OcamlLocalConversionDecision> = [];

	public final count:Int;
	public final admittedCount:Int;
	public final conversionCount:Int;
	public final unsafeOperationCount:Int;
	public final revision:String;

	public function new(decisions:Array<OcamlLocalRepresentationDecision>, ?conversions:Array<OcamlLocalConversionDecision>) {
		orderedDecisions = decisions.map(copyDecision);
		orderedDecisions.sort((left, right) -> left.localId - right.localId);
		var admitted = 0;
		for (decision in orderedDecisions) {
			if (decisionsByLocalId.exists(decision.localId))
				throw 'reflaxe.ocaml [ocaml-representation:duplicate-local-choice]: local ${decision.localId} has more than one representation choice';
			decisionsByLocalId.set(decision.localId, decision);
			switch (decision.choice) {
				case ProgramDecision(_, _, _):
					admitted += 1;
				case Unmigrated(_):
					if (decision.initializerConversion != OcamlLocalCarrierConversion.LegacyCoercion
						|| decision.assignmentConversion != OcamlLocalCarrierConversion.LegacyCoercion
						|| decision.readConversion != OcamlLocalCarrierConversion.LegacyCoercion) {
						throw 'reflaxe.ocaml [ocaml-representation:unmigrated-conversion]: local ${decision.localId} is unmigrated but selects a non-legacy carrier conversion';
					}
			}
		}
		count = orderedDecisions.length;
		admittedCount = admitted;
		orderedConversions = (conversions ?? []).map(copyConversion);
		orderedConversions.sort((left, right) -> Reflect.compare(left.id, right.id));
		var unsafeCount = 0;
		for (conversion in orderedConversions) {
			if (conversionsById.exists(conversion.id)) {
				final existing = conversionsById.get(conversion.id);
				throw 'reflaxe.ocaml [ocaml-representation:duplicate-local-conversion]: occurrence "${conversion.id}" identifies both local ${existing.localId} ${existing.role} at ${existing.source.file}:${existing.source.min}-${existing.source.max} and local ${conversion.localId} ${conversion.role} at ${conversion.source.file}:${conversion.source.min}-${conversion.source.max}';
			}
			final localDecision = decisionsByLocalId.get(conversion.localId);
			if (localDecision == null)
				throw 'reflaxe.ocaml [ocaml-representation:conversion-without-local]: occurrence "${conversion.id}" refers to unplanned local ${conversion.localId}';
			switch (localDecision.choice) {
				case ProgramDecision(_, "Null<Int>", _):
					validateNullIntConversion(conversion);
				case ProgramDecision(_, semanticTypeId, _):
					throw 'reflaxe.ocaml [ocaml-representation:wrong-conversion-family]: occurrence "${conversion.id}" selects a Null<Int> conversion for $semanticTypeId';
				case Unmigrated(_):
					throw 'reflaxe.ocaml [ocaml-representation:unmigrated-occurrence-conversion]: occurrence "${conversion.id}" belongs to an unmigrated local';
			}
			if (conversion.unsafeOperation != null)
				unsafeCount += 1;
			conversionsById.set(conversion.id, conversion);
		}
		conversionCount = orderedConversions.length;
		unsafeOperationCount = unsafeCount;
		revision = "sha256:" + Sha256.encode(orderedDecisions.map(decisionFingerprint).concat(orderedConversions.map(conversionFingerprint)).join("\n"));
	}

	/**
		Builds the deterministic key shared by final typed planning and syntax.

		The identity uses the sealed function/body binding, typed local identity,
		source role, and normalized source span. It never depends on a traversal
		counter, local name, or rendered expression text.
	**/
	public static function occurrenceId(binding:OcamlFunctionPlanBinding, localId:Int, role:OcamlLocalConversionRole, source:OcamlLoweredSourceSpan):String {
		return "local-conversion:" + Sha256.encode([
			binding.functionId,
			binding.programRevision,
			binding.bodyRevision,
			binding.pipelineRevision,
			Std.string(localId),
			(role : String),
			source.file,
			Std.string(source.min),
			Std.string(source.max)
		].join("\n")).substr(0, 32);
	}

	/** Resolves one occurrence without reclassifying the conversion it needs. */
	public function conversionFor(binding:OcamlFunctionPlanBinding, localId:Int, role:OcamlLocalConversionRole,
			source:OcamlLoweredSourceSpan):Null<OcamlLocalConversionDecision> {
		final decision = conversionsById.get(occurrenceId(binding, localId, role, source));
		return decision == null ? null : copyConversion(decision);
	}

	/** Returns every conversion in deterministic identity order. */
	public function conversions():Array<OcamlLocalConversionDecision> {
		return orderedConversions.map(copyConversion);
	}

	/** Returns the admitted unsafe-operation ledger in conversion order. */
	public function unsafeOperations():Array<OcamlUnsafeOperationRecord> {
		return [
			for (conversion in orderedConversions)
				if (conversion.unsafeOperation != null) copyUnsafeOperation(conversion.unsafeOperation)
		];
	}

	/** Returns the sealed program-decision or explicit-unmigrated choice. */
	public function choiceFor(localId:Int):Null<OcamlLocalRepresentationChoice> {
		final decision = decisionsByLocalId.get(localId);
		return decision == null ? null : copyChoice(decision.choice);
	}

	/** Returns the sealed initializer conversion for one planned local. */
	public function initializerConversionFor(localId:Int):Null<OcamlLocalCarrierConversion> {
		final decision = decisionsByLocalId.get(localId);
		return decision == null ? null : decision.initializerConversion;
	}

	/** Returns the sealed whole-value assignment conversion for one planned local. */
	public function assignmentConversionFor(localId:Int):Null<OcamlLocalCarrierConversion> {
		final decision = decisionsByLocalId.get(localId);
		return decision == null ? null : decision.assignmentConversion;
	}

	/** Returns the sealed conversion applied when syntax reads one planned local. */
	public function readConversionFor(localId:Int):Null<OcamlLocalCarrierConversion> {
		final decision = decisionsByLocalId.get(localId);
		return decision == null ? null : decision.readConversion;
	}

	/** Returns a defensive copy of one local's registry reference. */
	public function referenceFor(localId:Int):Null<OcamlLocalRepresentationReference> {
		final choice = choiceFor(localId);
		return switch (choice) {
			case ProgramDecision(representationId, semanticTypeId, domain): {
					localId: localId,
					representationId: representationId,
					semanticTypeId: semanticTypeId,
					domain: domain
				};
			case Unmigrated(_), null: null;
		}
	}

	/** Returns all references in deterministic local-id order. */
	public function references():Array<OcamlLocalRepresentationReference> {
		final references:Array<OcamlLocalRepresentationReference> = [];
		for (decision in orderedDecisions) {
			switch (decision.choice) {
				case ProgramDecision(representationId, semanticTypeId, domain):
					references.push({
						localId: decision.localId,
						representationId: representationId,
						semanticTypeId: semanticTypeId,
						domain: domain
					});
				case Unmigrated(_):
			}
		}
		return references;
	}

	static function copyDecision(decision:OcamlLocalRepresentationDecision):OcamlLocalRepresentationDecision {
		return {
			localId: decision.localId,
			choice: copyChoice(decision.choice),
			initializerConversion: decision.initializerConversion,
			assignmentConversion: decision.assignmentConversion,
			readConversion: decision.readConversion
		};
	}

	static function copyChoice(choice:OcamlLocalRepresentationChoice):OcamlLocalRepresentationChoice {
		return switch (choice) {
			case ProgramDecision(representationId, semanticTypeId, domain): ProgramDecision(representationId, semanticTypeId, domain);
			case Unmigrated(semanticTypeId): Unmigrated(semanticTypeId);
		}
	}

	static function decisionFingerprint(decision:OcamlLocalRepresentationDecision):String {
		final choiceFingerprint = switch (decision.choice) {
			case ProgramDecision(representationId, semanticTypeId,
				domain): '${decision.localId}|program|$representationId|$semanticTypeId|${(domain : String)}';
			case Unmigrated(semanticTypeId): '${decision.localId}|unmigrated|$semanticTypeId';
		}
		return choiceFingerprint + "|initializer:" + (decision.initializerConversion : String) + "|assignment:" + (decision.assignmentConversion : String)
			+ "|read:" + (decision.readConversion : String);
	}

	static function validateNullIntConversion(decision:OcamlLocalConversionDecision):Void {
		if (decision.id.length == 0
			|| decision.reason.length == 0
			|| decision.proofId.length == 0
			|| decision.proofClaim.length == 0
			|| decision.functionId.length == 0
			|| decision.programRevision.length == 0
			|| decision.bodyRevision.length == 0
			|| decision.pipelineRevision.length == 0)
			throw "reflaxe.ocaml [ocaml-representation:invalid-local-conversion]: identity, reason, proof, and revision binding must be non-empty";
		if (decision.source.file.length == 0 || decision.source.min < 0 || decision.source.max < decision.source.min)
			throw 'reflaxe.ocaml [ocaml-representation:invalid-local-conversion-source]: occurrence "${decision.id}" has an invalid normalized source span';
		switch (decision.role) {
			case Initializer, Assignment, Read:
			case other:
				throw 'reflaxe.ocaml [ocaml-representation:invalid-local-conversion-role]: occurrence "${decision.id}" uses unsupported role "$other"';
		}
		if (decision.profileEligibility.length == 0)
			throw 'reflaxe.ocaml [ocaml-representation:invalid-local-conversion]: occurrence "${decision.id}" has no eligible profile';
		final profiles:Map<String, Bool> = [];
		for (profile in decision.profileEligibility) {
			if (profile.length == 0 || profiles.exists(profile))
				throw 'reflaxe.ocaml [ocaml-representation:invalid-local-conversion-profile]: occurrence "${decision.id}" has an empty or duplicate profile';
			profiles.set(profile, true);
		}
		switch (decision.conversion) {
			case PreserveNullableIntCarrier:
				requireConversionShape(decision, "Null<Int>", "Obj.t", "Null<Int>", "Obj.t");
				if (decision.unsafeOperation != null)
					throw 'reflaxe.ocaml [ocaml-representation:unexpected-unsafe-operation]: carrier-preserving occurrence "${decision.id}" must not claim an unsafe target operation';
			case BoxExactIntToNullableInt:
				requireConversionShape(decision, "Int", "int", "Null<Int>", "Obj.t");
				requireUnsafeOperation(decision, OcamlUnsafeOperationKind.ObjReprExactInt);
			case CheckedUnboxNullableInt:
				requireConversionShape(decision, "Null<Int>", "Obj.t", "Int", "int");
				requireUnsafeOperation(decision, OcamlUnsafeOperationKind.CheckedNullableIntUnwrap);
			case LegacyCoercion, Identity:
				throw 'reflaxe.ocaml [ocaml-representation:invalid-null-int-conversion]: occurrence "${decision.id}" uses ${decision.conversion} instead of an exact Null<Int> conversion';
		}
	}

	static function requireConversionShape(decision:OcamlLocalConversionDecision, inputSemanticTypeId:String, inputCarrierTypeId:String,
			outputSemanticTypeId:String, outputCarrierTypeId:String):Void {
		if (decision.inputSemanticTypeId != inputSemanticTypeId
			|| decision.inputCarrierTypeId != inputCarrierTypeId
			|| decision.outputSemanticTypeId != outputSemanticTypeId
			|| decision.outputCarrierTypeId != outputCarrierTypeId) {
			throw 'reflaxe.ocaml [ocaml-representation:wrong-conversion-carrier]: occurrence "${decision.id}" selects ${decision.inputSemanticTypeId}/${decision.inputCarrierTypeId} -> ${decision.outputSemanticTypeId}/${decision.outputCarrierTypeId}, expected $inputSemanticTypeId/$inputCarrierTypeId -> $outputSemanticTypeId/$outputCarrierTypeId';
		}
	}

	static function requireUnsafeOperation(decision:OcamlLocalConversionDecision, expected:OcamlUnsafeOperationKind):Void {
		final operation = decision.unsafeOperation;
		if (operation == null || operation.operation != expected)
			throw 'reflaxe.ocaml [ocaml-representation:missing-unsafe-proof]: occurrence "${decision.id}" must own unsafe operation $expected';
		final expectedId = decision.id + ":unsafe:" + (expected : String);
		if (operation.id != expectedId
			|| operation.conversionId != decision.id
			|| operation.source.file != decision.source.file
			|| operation.source.min != decision.source.min
			|| operation.source.max != decision.source.max
			|| operation.inputSemanticTypeId != decision.inputSemanticTypeId
			|| operation.inputCarrierTypeId != decision.inputCarrierTypeId
			|| operation.outputSemanticTypeId != decision.outputSemanticTypeId
			|| operation.outputCarrierTypeId != decision.outputCarrierTypeId
			|| operation.reason != decision.reason
			|| operation.proofId != decision.proofId
			|| operation.proofClaim != decision.proofClaim
			|| operation.profileEligibility.join(",") != decision.profileEligibility.join(",")
			|| operation.functionId != decision.functionId
			|| operation.programRevision != decision.programRevision
			|| operation.bodyRevision != decision.bodyRevision
			|| operation.pipelineRevision != decision.pipelineRevision) {
			throw 'reflaxe.ocaml [ocaml-representation:unsafe-proof-mismatch]: unsafe operation "${operation.id}" does not match occurrence "${decision.id}"';
		}
	}

	static function copyConversion(decision:OcamlLocalConversionDecision):OcamlLocalConversionDecision {
		return {
			id: decision.id,
			localId: decision.localId,
			role: decision.role,
			source: copySource(decision.source),
			inputSemanticTypeId: decision.inputSemanticTypeId,
			inputCarrierTypeId: decision.inputCarrierTypeId,
			outputSemanticTypeId: decision.outputSemanticTypeId,
			outputCarrierTypeId: decision.outputCarrierTypeId,
			conversion: decision.conversion,
			reason: decision.reason,
			proofId: decision.proofId,
			proofClaim: decision.proofClaim,
			profileEligibility: decision.profileEligibility.copy(),
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision,
			unsafeOperation: decision.unsafeOperation == null ? null : copyUnsafeOperation(decision.unsafeOperation)
		};
	}

	static function copyUnsafeOperation(operation:OcamlUnsafeOperationRecord):OcamlUnsafeOperationRecord {
		return {
			id: operation.id,
			conversionId: operation.conversionId,
			operation: operation.operation,
			source: copySource(operation.source),
			inputSemanticTypeId: operation.inputSemanticTypeId,
			inputCarrierTypeId: operation.inputCarrierTypeId,
			outputSemanticTypeId: operation.outputSemanticTypeId,
			outputCarrierTypeId: operation.outputCarrierTypeId,
			reason: operation.reason,
			proofId: operation.proofId,
			proofClaim: operation.proofClaim,
			profileEligibility: operation.profileEligibility.copy(),
			functionId: operation.functionId,
			programRevision: operation.programRevision,
			bodyRevision: operation.bodyRevision,
			pipelineRevision: operation.pipelineRevision
		};
	}

	static function copySource(source:OcamlLoweredSourceSpan):OcamlLoweredSourceSpan {
		return {file: source.file, min: source.min, max: source.max};
	}

	static function conversionFingerprint(decision:OcamlLocalConversionDecision):String {
		final unsafe = decision.unsafeOperation == null ? "safe" : [
			decision.unsafeOperation.id,
			(decision.unsafeOperation.operation : String),
			decision.unsafeOperation.reason,
			decision.unsafeOperation.proofId,
			decision.unsafeOperation.proofClaim
		].join("|");
		return [
			decision.id,
			Std.string(decision.localId),
			(decision.role : String),
			decision.source.file,
			Std.string(decision.source.min),
			Std.string(decision.source.max),
			decision.inputSemanticTypeId,
			decision.inputCarrierTypeId,
			decision.outputSemanticTypeId,
			decision.outputCarrierTypeId,
			(decision.conversion : String),
			decision.reason,
			decision.proofId,
			decision.proofClaim,
			decision.profileEligibility.join(","),
			decision.functionId,
			decision.programRevision,
			decision.bodyRevision,
			decision.pipelineRevision,
			unsafe
		].join("|");
	}
}
#end
