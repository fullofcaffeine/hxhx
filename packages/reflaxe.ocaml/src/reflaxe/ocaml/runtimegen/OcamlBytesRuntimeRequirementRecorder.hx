package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime || eval)
import reflaxe.ocaml.lowered.OcamlBytesMutationModel.OcamlBytesMutationContract;
import reflaxe.ocaml.lowered.OcamlBytesMutationModel.OcamlBytesMutationDecision;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessContract;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessDecision;
import reflaxe.ocaml.lowered.OcamlBytesProducerModel.OcamlBytesProducerContract;
import reflaxe.ocaml.lowered.OcamlBytesProducerModel.OcamlBytesProducerDecision;
import reflaxe.ocaml.lowered.OcamlBytesReadModel.OcamlBytesReadContract;
import reflaxe.ocaml.lowered.OcamlBytesReadModel.OcamlBytesReadDecision;
import reflaxe.ocaml.lowered.OcamlBytesRepresentationModel.OcamlBytesRepresentationContract;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementCause;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSourceKind;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSubjectKind;

/**
	Translates sealed Bytes decisions into occurrence-local runtime requirements.

	The generic ledger owns storage, normalization, duplicate rejection, and
	revisioning. This recorder owns only the mapping from an already-validated
	Bytes producer, read, mutation, or access decision to the exact `HxBytes`
	requirement it implies. Keeping that mapping separate prevents the ledger
	from becoming a second owner of every Bytes decision model.
**/
class OcamlBytesRuntimeRequirementRecorder {
	public static inline final HAXE_BYTES_MUTATION = OcamlBytesMutationContract.RUNTIME_CAPABILITY;
	public static inline final HAXE_BYTES_MUTATION_NULLABLE_INT = OcamlBytesMutationContract.NULLABLE_INT_RUNTIME_CAPABILITY;
	public static inline final HAXE_BYTES_ACCESS = OcamlBytesAccessContract.RUNTIME_CAPABILITY;
	public static inline final HAXE_BYTES_ACCESS_NULLABLE_INT = OcamlBytesAccessContract.NULLABLE_INT_RUNTIME_CAPABILITY;
	public static inline final HAXE_BYTES_PRODUCER = OcamlBytesProducerContract.RUNTIME_CAPABILITY;
	public static inline final HAXE_BYTES_READ = OcamlBytesReadContract.RUNTIME_CAPABILITY;
	public static inline final HAXE_BYTES_READ_NULLABLE_RECEIVER = OcamlBytesReadContract.NULLABLE_RECEIVER_RUNTIME_CAPABILITY;

	/**
		Records why one sealed non-null Bytes producer needs `HxBytes`.

		The requirement is deliberately occurrence-local. It explains only the
		supported producer result and does not authorize nullable storage,
		receiver calls, indexing, or mutation.
	**/
	public static function recordProducer(ledger:OcamlRuntimeRequirementLedger, decision:OcamlBytesProducerDecision):Void {
		OcamlBytesProducerContract.requireDecision(decision);
		final requirementId = decision.id + ":runtime:" + HAXE_BYTES_PRODUCER;
		if (decision.runtimeRequirementIds[0] != requirementId)
			throw 'Bytes producer "${decision.id}" does not name its exact runtime requirement.';
		ledger.record({
			id: requirementId,
			sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
			sourceId: decision.id,
			source: decision.source,
			semanticCapability: HAXE_BYTES_PRODUCER,
			cause: OcamlRuntimeRequirementCause.LoweringDecision,
			decisionId: decision.id,
			subject: {
				kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
				id: OcamlBytesProducerContract.SEMANTIC_TYPE_ID
			},
			implementationFeature: "haxe-bytes-producer-v2",
			rootModules: ["HxBytes"],
			profileEligibility: ["metal", "portable"],
			explanation: 'The sealed ${decision.calleeId} ${decision.kind} operation creates a non-null haxe.io.Bytes value through HxBytes using ${decision.constructionPolicy}; nullable storage, receivers, indexing, and mutation require separate decisions.'
		});
	}

	/**
		Records why one sealed mutating Bytes operation needs `HxBytes`.

		The requirement explains only the exact destination mutation and its
		closed range, overlap, and byte-value policies. It does not authorize
		inline-expanded BytesData operations or other Bytes write families.
	**/
	public static function recordMutation(ledger:OcamlRuntimeRequirementLedger, decision:OcamlBytesMutationDecision):Void {
		OcamlBytesMutationContract.requireDecision(decision);
		final requirementId = OcamlBytesMutationContract.runtimeRequirementId(decision.id);
		if (decision.runtimeRequirementIds[0] != requirementId)
			throw 'Bytes mutation "${decision.id}" does not name its exact runtime requirement.';
		ledger.record({
			id: requirementId,
			sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
			sourceId: decision.id,
			source: decision.source,
			semanticCapability: HAXE_BYTES_MUTATION,
			cause: OcamlRuntimeRequirementCause.LoweringDecision,
			decisionId: decision.id,
			subject: {
				kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
				id: OcamlBytesRepresentationContract.DIRECT_SEMANTIC_TYPE_ID
			},
			implementationFeature: "haxe-bytes-mutation-v1",
			rootModules: ["HxBytes"],
			profileEligibility: ["metal", "portable"],
			explanation: 'The sealed ${decision.calleeId} ${decision.kind} operation mutates one exact haxe.io.Bytes destination through HxBytes after fixing receiver and argument evaluation, range validation, ${decision.overlapPolicy} overlap, and ${decision.valuePolicy} byte behavior; the call returns effect-only Void and does not authorize other write families.'
		});
		if (decision.runtimeRequirementIds.length == 2) {
			final nullableRequirementId = OcamlBytesMutationContract.nullableIntRuntimeRequirementId(decision.id);
			if (decision.runtimeRequirementIds[1] != nullableRequirementId)
				throw 'Bytes mutation "${decision.id}" does not name its exact nullable Int runtime requirement.';
			ledger.record({
				id: nullableRequirementId,
				sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
				sourceId: decision.id,
				source: decision.source,
				semanticCapability: HAXE_BYTES_MUTATION_NULLABLE_INT,
				cause: OcamlRuntimeRequirementCause.LoweringDecision,
				decisionId: decision.id,
				subject: {
					kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: "Null<Int>"
				},
				implementationFeature: "haxe-nullable-int-v1",
				rootModules: ["HxRuntime"],
				profileEligibility: ["metal", "portable"],
				explanation: 'The sealed ${decision.calleeId} mutation receives a nullable integer where HxBytes requires an exact Int, so HxRuntime rejects null before the selected mutation runs.'
			});
		}
	}

	/**
		Records why one sealed byte access or data-alias operation needs `HxBytes`.

		The requirement is occurrence-local and carries the already-selected
		bounds, byte-value, mutation, alias, and result policies. It does not
		authorize arbitrary `BytesData` indexing or any other Bytes method.
	**/
	public static function recordAccess(ledger:OcamlRuntimeRequirementLedger, decision:OcamlBytesAccessDecision):Void {
		OcamlBytesAccessContract.requireDecision(decision);
		final requirementId = OcamlBytesAccessContract.runtimeRequirementId(decision.id);
		if (decision.runtimeRequirementIds[0] != requirementId)
			throw 'Bytes access "${decision.id}" does not name its exact runtime requirement.';
		ledger.record({
			id: requirementId,
			sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
			sourceId: decision.id,
			source: decision.source,
			semanticCapability: HAXE_BYTES_ACCESS,
			cause: OcamlRuntimeRequirementCause.LoweringDecision,
			decisionId: decision.id,
			subject: {
				kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
				id: OcamlBytesRepresentationContract.DIRECT_SEMANTIC_TYPE_ID
			},
			implementationFeature: "haxe-bytes-access-v5",
			rootModules: ["HxBytes"],
			profileEligibility: ["metal", "portable"],
			explanation: 'The sealed ${decision.calleeId} ${decision.kind} operation calls HxBytes after evaluating raw inputs once in source order and then applying ${decision.argumentConversions.join(",")} conversions in argument order. It fixes ${decision.boundsPolicy} bounds, a ${decision.accessWidthBytes}-byte access, ${decision.byteOrderPolicy} ordering, ${decision.valuePolicy} value behavior, ${decision.mutationPolicy} mutation, ${decision.aliasPolicy} aliasing, and ${decision.resultKind} result behavior. Nullable Int multi-byte arguments preserve present values and fail null without mutation through the OCaml target\'s deterministic OutsideBounds policy. Float32 rounds through IEEE-754 binary32 while Float64 preserves the admitted binary64 value; NaN classification is preserved without claiming one cross-target payload. Other Bytes and BytesData operations require separate decisions.'
		});
		if (decision.runtimeRequirementIds.length == 2) {
			final nullableRequirementId = OcamlBytesAccessContract.nullableIntRuntimeRequirementId(decision.id);
			if (decision.runtimeRequirementIds[1] != nullableRequirementId)
				throw 'Bytes access "${decision.id}" does not name its exact nullable Int runtime requirement.';
			ledger.record({
				id: nullableRequirementId,
				sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
				sourceId: decision.id,
				source: decision.source,
				semanticCapability: HAXE_BYTES_ACCESS_NULLABLE_INT,
				cause: OcamlRuntimeRequirementCause.LoweringDecision,
				decisionId: decision.id,
				subject: {
					kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: "Null<Int>"
				},
				implementationFeature: "haxe-nullable-int-v1",
				rootModules: ["HxRuntime"],
				profileEligibility: ["metal", "portable"],
				explanation: 'The sealed ${decision.calleeId} access receives a nullable integer where a single-byte HxBytes operation requires an exact Int, so HxRuntime rejects null before the selected access runs.'
			});
		}
	}

	/**
		Records why one sealed read-only Bytes operation needs `HxBytes`.

		The requirement names only the exact read decision. It does not authorize
		indexed access, mutation, nullable materialization, or deferred Float
		result families.
	**/
	public static function recordRead(ledger:OcamlRuntimeRequirementLedger, decision:OcamlBytesReadDecision):Void {
		OcamlBytesReadContract.requireDecision(decision);
		final requirementId = OcamlBytesReadContract.runtimeRequirementId(decision.id);
		if (decision.runtimeRequirementIds[0] != requirementId)
			throw 'Bytes read "${decision.id}" does not name its exact runtime requirement.';
		ledger.record({
			id: requirementId,
			sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
			sourceId: decision.id,
			source: decision.source,
			semanticCapability: HAXE_BYTES_READ,
			cause: OcamlRuntimeRequirementCause.LoweringDecision,
			decisionId: decision.id,
			subject: {
				kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
				id: OcamlBytesRepresentationContract.DIRECT_SEMANTIC_TYPE_ID
			},
			implementationFeature: "haxe-bytes-read-v1",
			rootModules: ["HxBytes"],
			profileEligibility: ["metal", "portable"],
			explanation: 'The sealed ${decision.calleeId} ${decision.kind} operation reads an exact haxe.io.Bytes value through HxBytes after fixing the typed receiver input, its ${decision.receiverConversion} conversion, and argument evaluation order. Writes, indexed access, other nullable materialization, and Float results require separate decisions.'
		});
		if (decision.runtimeRequirementIds.length == 2) {
			final nullableRequirementId = OcamlBytesReadContract.nullableReceiverRuntimeRequirementId(decision.id);
			if (decision.runtimeRequirementIds[1] != nullableRequirementId)
				throw 'Bytes read "${decision.id}" does not name its exact nullable receiver runtime requirement.';
			ledger.record({
				id: nullableRequirementId,
				sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
				sourceId: decision.id,
				source: decision.source,
				semanticCapability: HAXE_BYTES_READ_NULLABLE_RECEIVER,
				cause: OcamlRuntimeRequirementCause.LoweringDecision,
				decisionId: decision.id,
				subject: {
					kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: OcamlBytesRepresentationContract.EXPLICIT_NULL_SEMANTIC_TYPE_ID
				},
				implementationFeature: "haxe-nullable-bytes-receiver-v1",
				rootModules: ["HxRuntime"],
				profileEligibility: ["metal", "portable"],
				explanation: 'The sealed ${decision.calleeId} read receives exact Null<haxe.io.Bytes>, so HxRuntime tests the materialized receiver and throws the typed Null Access value before any read argument is evaluated.'
			});
		}
	}
}
#end
