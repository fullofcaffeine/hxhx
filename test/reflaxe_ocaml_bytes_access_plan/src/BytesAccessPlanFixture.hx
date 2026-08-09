package;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type.ClassField;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessAliasPolicy;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessArgumentConversion;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessByteOrderPolicy;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessBoundsPolicy;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessContract;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessDecision;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessInvocationKind;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessKind;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessMutationPolicy;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessResultKind;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessValuePolicy;
import reflaxe.ocaml.lowered.OcamlBytesAccessPlan;
import reflaxe.ocaml.lowered.OcamlBytesAccessPlan.OcamlBytesAccessPlanner;
import reflaxe.ocaml.lowered.OcamlBytesRepresentationModel.OcamlBytesRepresentationContract;
import reflaxe.ocaml.lowered.OcamlFloatRepresentationModel.OcamlFloatRepresentationContract;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlFunctionPlanRegistry;
import reflaxe.ocaml.lowered.OcamlInt64RepresentationModel.OcamlInt64RepresentationContract;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationBoxingPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;
import reflaxe.ocaml.lowered.OcamlRepresentationRegistry;
import reflaxe.ocaml.runtimegen.OcamlBytesRuntimeRequirementRecorder;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;

/**
	Proves that the real target override leaves exact Bytes-access calls to seal.

	The fixture checks deterministic occurrence plans and representation
	decisions, then corrupts individual facts so stale or incomplete records
	cannot reach OCaml syntax or runtime packaging.
**/
class BytesAccessPlanFixture {
	static inline final PROGRAM_REVISION = "program:bytes-access-fixture";
	static inline final BODY_REVISION = "body:bytes-access-fixture";
	static inline final PIPELINE_REVISION = "pipeline:bytes-access-fixture";
	static var expectedFailureIndex = 0;

	public static macro function run():Expr {
		final representations = new OcamlRepresentationRegistry();
		representations.beginProgram(PROGRAM_REVISION);
		final cases = caseFields();
		final decisions:Array<OcamlBytesAccessDecision> = [];
		final expectedKinds = [
			"get" => OcamlBytesAccessKind.Get,
			"getNullablePosition" => OcamlBytesAccessKind.Get,
			"set" => OcamlBytesAccessKind.Set,
			"setNullableValue" => OcamlBytesAccessKind.Set,
			"getUInt16" => OcamlBytesAccessKind.GetUInt16,
			"getUInt16NullablePosition" => OcamlBytesAccessKind.GetUInt16,
			"setUInt16" => OcamlBytesAccessKind.SetUInt16,
			"setUInt16NullablePosition" => OcamlBytesAccessKind.SetUInt16,
			"setUInt16NullableValue" => OcamlBytesAccessKind.SetUInt16,
			"setUInt16NullablePositionAndValue" => OcamlBytesAccessKind.SetUInt16,
			"getInt32" => OcamlBytesAccessKind.GetInt32,
			"getInt32NullablePosition" => OcamlBytesAccessKind.GetInt32,
			"setInt32" => OcamlBytesAccessKind.SetInt32,
			"setInt32NullablePosition" => OcamlBytesAccessKind.SetInt32,
			"setInt32NullableValue" => OcamlBytesAccessKind.SetInt32,
			"getInt64" => OcamlBytesAccessKind.GetInt64,
			"getInt64NullablePosition" => OcamlBytesAccessKind.GetInt64,
			"setInt64" => OcamlBytesAccessKind.SetInt64,
			"setInt64NullablePosition" => OcamlBytesAccessKind.SetInt64,
			"getFloat" => OcamlBytesAccessKind.GetFloat32,
			"getFloatNullablePosition" => OcamlBytesAccessKind.GetFloat32,
			"setFloat" => OcamlBytesAccessKind.SetFloat32,
			"setFloatNullablePosition" => OcamlBytesAccessKind.SetFloat32,
			"getDouble" => OcamlBytesAccessKind.GetFloat64,
			"getDoubleNullablePosition" => OcamlBytesAccessKind.GetFloat64,
			"setDouble" => OcamlBytesAccessKind.SetFloat64,
			"setDoubleNullablePosition" => OcamlBytesAccessKind.SetFloat64,
			"getData" => OcamlBytesAccessKind.GetData,
			"fastGet" => OcamlBytesAccessKind.FastGet,
			"getInSourceOrder" => OcamlBytesAccessKind.Get,
			"setInSourceOrder" => OcamlBytesAccessKind.Set,
			"setNullablePositionInSourceOrder" => OcamlBytesAccessKind.Set,
			"getUInt16InSourceOrder" => OcamlBytesAccessKind.GetUInt16,
			"setInt32InSourceOrder" => OcamlBytesAccessKind.SetInt32,
			"setUInt16NullablePositionInSourceOrder" => OcamlBytesAccessKind.SetUInt16,
			"setUInt16NullableValueInSourceOrder" => OcamlBytesAccessKind.SetUInt16,
			"getInt64InSourceOrder" => OcamlBytesAccessKind.GetInt64,
			"setInt64InSourceOrder" => OcamlBytesAccessKind.SetInt64,
			"setInt64NullablePositionInSourceOrder" => OcamlBytesAccessKind.SetInt64,
			"getFloatInSourceOrder" => OcamlBytesAccessKind.GetFloat32,
			"setFloatInSourceOrder" => OcamlBytesAccessKind.SetFloat32,
			"setFloatNullablePositionInSourceOrder" => OcamlBytesAccessKind.SetFloat32,
			"getDoubleInSourceOrder" => OcamlBytesAccessKind.GetFloat64,
			"setDoubleInSourceOrder" => OcamlBytesAccessKind.SetFloat64,
			"getDataInSourceOrder" => OcamlBytesAccessKind.GetData,
			"fastGetInSourceOrder" => OcamlBytesAccessKind.FastGet
		];
		for (name => kind in expectedKinds) {
			final field = requireField(cases, name);
			final body = requireBody(field);
			final binding = binding(name);
			final first = new OcamlBytesAccessPlanner(binding, representations).plan(body);
			final second = new OcamlBytesAccessPlanner(binding, representations).plan(body);
			if (first.revision != second.revision)
				Context.error('Bytes access case "$name" has a non-deterministic plan revision.', field.pos);
			final planned = first.decisions();
			if (planned.length != 1)
				Context.error('Bytes access case "$name" expected one decision, received ${planned.length}: ${TypedExprTools.toString(body)}', field.pos);
			final decision = planned[0];
			final invocation = kind == OcamlBytesAccessKind.FastGet ? OcamlBytesAccessInvocationKind.Static : OcamlBytesAccessInvocationKind.Instance;
			final expectedOrder = invocation == OcamlBytesAccessInvocationKind.Instance ? [-1].concat([
				for (index in 0...decision.argumentCount)
					index
			]) : [for (index in 0...decision.argumentCount) index];
			if (decision.kind != kind
				|| decision.invocationKind != invocation
				|| decision.evaluationOrder.join(",") != expectedOrder.join(",")
				|| decision.boundsPolicy != OcamlBytesAccessContract.boundsPolicy(kind)
				|| decision.accessWidthBytes != OcamlBytesAccessContract.accessWidthBytes(kind)
				|| decision.byteOrderPolicy != OcamlBytesAccessContract.byteOrderPolicy(kind)
				|| decision.valuePolicy != OcamlBytesAccessContract.valuePolicy(kind)
				|| decision.mutationPolicy != OcamlBytesAccessContract.mutationPolicy(kind)
				|| decision.aliasPolicy != OcamlBytesAccessContract.aliasPolicy(kind)
				|| decision.resultKind != OcamlBytesAccessContract.resultKind(kind)
				|| decision.runtimeOperation != OcamlBytesAccessContract.fieldName(kind)) {
				Context.error('Bytes access case "$name" disagrees with its typed access contract.', field.pos);
			}
			if (kind == OcamlBytesAccessKind.GetData) {
				if (decision.resultSemanticTypeId != OcamlBytesRepresentationContract.DATA_SEMANTIC_TYPE_ID
					|| decision.resultCarrierTypeId != OcamlBytesRepresentationContract.DATA_CARRIER_TYPE_ID
					|| decision.aliasPolicy != OcamlBytesAccessAliasPolicy.SharedNativeDataAlias
					|| decision.mutationPolicy != OcamlBytesAccessMutationPolicy.ReturnMutableAlias) {
					Context.error('Bytes access case "$name" did not seal the mutable BytesData alias.', field.pos);
				}
			}
			if (kind == OcamlBytesAccessKind.Set
				&& (decision.valuePolicy != OcamlBytesAccessValuePolicy.MaskLowEightBits
					|| decision.resultKind != OcamlBytesAccessResultKind.EffectOnlyVoid)) {
				Context.error('Bytes access case "$name" did not seal low-byte mutation and effect-only Void.', field.pos);
			}
			switch (kind) {
				case GetUInt16:
					requireNumericPolicy(decision, 2, OcamlBytesAccessValuePolicy.UnsignedSixteenBitRead, OcamlBytesAccessMutationPolicy.ReadOnly,
						OcamlBytesAccessResultKind.ExactInt, field.pos);
				case SetUInt16:
					requireNumericPolicy(decision, 2, OcamlBytesAccessValuePolicy.MaskLowSixteenBits, OcamlBytesAccessMutationPolicy.MutateReceiverBytes,
						OcamlBytesAccessResultKind.EffectOnlyVoid, field.pos);
				case GetInt32:
					requireNumericPolicy(decision, 4, OcamlBytesAccessValuePolicy.SignedThirtyTwoBitRead, OcamlBytesAccessMutationPolicy.ReadOnly,
						OcamlBytesAccessResultKind.ExactInt, field.pos);
				case SetInt32:
					requireNumericPolicy(decision, 4, OcamlBytesAccessValuePolicy.PreserveLowThirtyTwoBits,
						OcamlBytesAccessMutationPolicy.MutateReceiverBytes, OcamlBytesAccessResultKind.EffectOnlyVoid, field.pos);
				case GetInt64:
					requireNumericPolicy(decision, 8, OcamlBytesAccessValuePolicy.SignedSixtyFourBitRead, OcamlBytesAccessMutationPolicy.ReadOnly,
						OcamlBytesAccessResultKind.ExactInt64, field.pos);
					if (decision.resultSemanticTypeId != OcamlInt64RepresentationContract.SEMANTIC_TYPE_ID
						|| decision.resultCarrierTypeId != OcamlInt64RepresentationContract.TARGET_TYPE_NAME
						|| decision.resultRepresentationId != OcamlInt64RepresentationContract.INTERNAL_REPRESENTATION_ID) {
						Context.error('Bytes access case "$name" did not seal the exact Int64 result carrier.', field.pos);
					}
				case SetInt64:
					requireNumericPolicy(decision, 8, OcamlBytesAccessValuePolicy.PreserveSixtyFourBits, OcamlBytesAccessMutationPolicy.MutateReceiverBytes,
						OcamlBytesAccessResultKind.EffectOnlyVoid, field.pos);
					if (decision.argumentSemanticTypeIds[1] != OcamlInt64RepresentationContract.SEMANTIC_TYPE_ID
						|| decision.argumentCarrierTypeIds[1] != OcamlInt64RepresentationContract.TARGET_TYPE_NAME
						|| decision.argumentRepresentationIds[1] != OcamlInt64RepresentationContract.INTERNAL_REPRESENTATION_ID) {
						Context.error('Bytes access case "$name" did not seal the exact Int64 value argument.', field.pos);
					}
				case GetFloat32:
					requireNumericPolicy(decision, 4, OcamlBytesAccessValuePolicy.Ieee754Binary32, OcamlBytesAccessMutationPolicy.ReadOnly,
						OcamlBytesAccessResultKind.ExactFloat, field.pos);
					requireExactFloatResult(decision, name, field.pos);
				case SetFloat32:
					requireNumericPolicy(decision, 4, OcamlBytesAccessValuePolicy.Ieee754Binary32, OcamlBytesAccessMutationPolicy.MutateReceiverBytes,
						OcamlBytesAccessResultKind.EffectOnlyVoid, field.pos);
					requireExactFloatArgument(decision, name, field.pos);
				case GetFloat64:
					requireNumericPolicy(decision, 8, OcamlBytesAccessValuePolicy.Ieee754Binary64, OcamlBytesAccessMutationPolicy.ReadOnly,
						OcamlBytesAccessResultKind.ExactFloat, field.pos);
					requireExactFloatResult(decision, name, field.pos);
				case SetFloat64:
					requireNumericPolicy(decision, 8, OcamlBytesAccessValuePolicy.Ieee754Binary64, OcamlBytesAccessMutationPolicy.MutateReceiverBytes,
						OcamlBytesAccessResultKind.EffectOnlyVoid, field.pos);
					requireExactFloatArgument(decision, name, field.pos);
				case _:
			}
			if (kind == OcamlBytesAccessKind.FastGet
				&& (decision.argumentSemanticTypeIds[0] != OcamlBytesRepresentationContract.DATA_SEMANTIC_TYPE_ID
					|| decision.boundsPolicy != OcamlBytesAccessBoundsPolicy.NativeDataChecked
					|| decision.receiverRepresentationId.length != 0)) {
				Context.error('Bytes access case "$name" did not seal the exact checked BytesData read.', field.pos);
			}
			if (name == "getNullablePosition" || name == "setNullablePositionInSourceOrder") {
				requireNullableIntConversion(decision, 0, OcamlBytesAccessArgumentConversion.RequireNonNullInt, field.pos);
			} else if (name == "setNullableValue") {
				requireNullableIntConversion(decision, 1, OcamlBytesAccessArgumentConversion.RequireNonNullInt, field.pos);
			} else {
				switch (name) {
					case "getUInt16NullablePosition", "setUInt16NullablePosition", "getInt32NullablePosition", "setInt32NullablePosition",
						"getInt64NullablePosition", "setInt64NullablePosition", "setUInt16NullablePositionInSourceOrder",
						"setInt64NullablePositionInSourceOrder", "getFloatNullablePosition", "setFloatNullablePosition", "getDoubleNullablePosition",
						"setDoubleNullablePosition", "setFloatNullablePositionInSourceOrder":
						requireNullableIntConversion(decision, 0, OcamlBytesAccessArgumentConversion.RequireMultiByteIntOrOutsideBounds, field.pos);
					case "setUInt16NullableValue", "setInt32NullableValue", "setUInt16NullableValueInSourceOrder":
						requireNullableIntConversion(decision, 1, OcamlBytesAccessArgumentConversion.RequireMultiByteIntOrOutsideBounds, field.pos);
					case "setUInt16NullablePositionAndValue":
						requireNullableIntConversion(decision, 0, OcamlBytesAccessArgumentConversion.RequireMultiByteIntOrOutsideBounds, field.pos);
						requireNullableIntConversion(decision, 1, OcamlBytesAccessArgumentConversion.RequireMultiByteIntOrOutsideBounds, field.pos);
					case _:
				}
			}
			final expectedRuntimeSymbols = [];
			for (conversion in decision.argumentConversions)
				switch (conversion) {
					case Identity:
					case RequireNonNullInt:
						expectedRuntimeSymbols.push("HxRuntime.nullable_int_unwrap");
					case RequireMultiByteIntOrOutsideBounds:
						expectedRuntimeSymbols.push("HxBytes.requireMultiByteInt");
				}
			expectedRuntimeSymbols.push("HxBytes." + decision.runtimeOperation);
			if (decision.runtimeUseOccurrences.map(use -> use.exactSymbol).join(",") != expectedRuntimeSymbols.join(","))
				Context.error('Bytes access case "$name" has no exact private-runtime use inventory.', field.pos);
			final occurrence = accessOccurrence(body);
			if (occurrence == null || first.requireFor(occurrence, representations).id != decision.id)
				Context.error('Bytes access case "$name" did not resolve its exact sealed occurrence.', field.pos);
			decisions.push(decision);
		}

		final lookalike = requireBody(requireField(cases, "userLookalike"));
		if (new OcamlBytesAccessPlanner(binding("userLookalike"), representations).plan(lookalike).decisions().length != 0)
			Context.error("User-defined access lookalikes were admitted as haxe.io.Bytes calls.", Context.currentPos());
		for (entry in unadmittedCases()) {
			if (!containsExactTargetCall(entry.expression, entry.fieldName))
				Context.error('Unsupported Bytes access case "${entry.name}" did not retain the exact target-selected declaration.', Context.currentPos());
			if (new OcamlBytesAccessPlanner(binding(entry.name), representations).plan(entry.expression).decisions().length != 0)
				Context.error('Unsupported Bytes access case "${entry.name}" was admitted by the exact UInt16/Int32 planner.', Context.currentPos());
		}

		final dataRepresentation = representations.selectExactBytesData(reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain.InternalValue);
		if (dataRepresentation.semanticTypeId != OcamlBytesRepresentationContract.DATA_SEMANTIC_TYPE_ID
			|| dataRepresentation.carrierTypeId != OcamlBytesRepresentationContract.DATA_CARRIER_TYPE_ID
			|| dataRepresentation.proof.id != OcamlBytesRepresentationContract.DATA_PROOF_ID) {
			Context.error("The exact BytesData representation does not preserve the target-native mutable alias.", Context.currentPos());
		}
		final int64Representation = representations.selectExactInt64(OcamlRepresentationDomain.InternalValue);
		if (int64Representation.semanticTypeId != OcamlInt64RepresentationContract.SEMANTIC_TYPE_ID
			|| int64Representation.carrierTypeId != OcamlInt64RepresentationContract.TARGET_TYPE_NAME
			|| int64Representation.boxingPolicy != OcamlRepresentationBoxingPolicy.DirectNominalValueCarrier
			|| int64Representation.nominalTargetModuleName != OcamlInt64RepresentationContract.TARGET_MODULE_NAME
			|| int64Representation.nominalTargetTypeName != OcamlInt64RepresentationContract.TARGET_TYPE_NAME
			|| int64Representation.nominalLayoutRevision != OcamlInt64RepresentationContract.LAYOUT_REVISION) {
			Context.error("The exact Int64 representation does not preserve its sealed nominal value carrier.", Context.currentPos());
		}
		if (OcamlInt64RepresentationContract.LAYOUT_REVISION != "sha256:a209a8988fdb10e76ef47bed3d5f136791f380450f862b72bf9cad0683df6a2d") {
			Context.error("The exact Int64 carrier layout changed without an explicit field-layout review.", Context.currentPos());
		}
		representations.requireExactInt64Internal(int64Representation.id, int64Representation.revision, PROGRAM_REVISION);
		expectThrows("representation-mismatch",
			() -> representations.requireExactInt64Internal(int64Representation.id, "sha256:" + StringTools.lpad("", "0", 64), PROGRAM_REVISION));
		final exactFloatType = Context.typeof(macro(0.0 : Float));
		final nullableFloatType = Context.typeof(macro(null : Null<Float>));
		if (!OcamlRepresentationRegistry.isExactFloat(exactFloatType) || OcamlRepresentationRegistry.isExactFloat(nullableFloatType)) {
			Context.error("The exact Float predicate admitted a nullable or non-core representation.", Context.currentPos());
		}
		final floatRepresentation = representations.selectExactFloat(OcamlRepresentationDomain.InternalValue);
		if (floatRepresentation.semanticTypeId != OcamlFloatRepresentationContract.SEMANTIC_TYPE_ID
			|| floatRepresentation.carrierTypeId != OcamlFloatRepresentationContract.CARRIER_TYPE_ID
			|| floatRepresentation.id != OcamlFloatRepresentationContract.INTERNAL_REPRESENTATION_ID
			|| floatRepresentation.boxingPolicy != OcamlRepresentationBoxingPolicy.DirectUnboxed
			|| floatRepresentation.proof.id != OcamlFloatRepresentationContract.PROOF_ID
			|| floatRepresentation.nominalTargetModuleName != null
			|| floatRepresentation.nominalTargetTypeName != null
			|| floatRepresentation.nominalLayoutRevision != null) {
			Context.error("The exact Float representation exceeded its reviewed internal value carrier.", Context.currentPos());
		}
		representations.requireExactFloatInternal(floatRepresentation.id, floatRepresentation.revision, PROGRAM_REVISION);
		expectThrows("representation-mismatch",
			() -> representations.requireExactFloatInternal(floatRepresentation.id, "sha256:" + StringTools.lpad("", "0", 64), PROGRAM_REVISION));
		expectThrows("unsupported-float-domain", () -> representations.selectExactFloat(OcamlRepresentationDomain.InstanceField));

		final ledger = new OcamlRuntimeRequirementLedger();
		ledger.beginProgram(PROGRAM_REVISION);
		for (decision in decisions)
			OcamlBytesRuntimeRequirementRecorder.recordAccess(ledger, decision);
		final requirements = ledger.requirementsSorted();
		final nullableRequirementCount = decisions.filter(decision -> Lambda.exists(decision.argumentConversions,
			conversion -> conversion == OcamlBytesAccessArgumentConversion.RequireNonNullInt))
			.length;
		final expectedRequirementCount = decisions.length + nullableRequirementCount;
		if (requirements.length != expectedRequirementCount)
			Context.error('Expected $expectedRequirementCount Bytes access requirements, received ${requirements.length}.', Context.currentPos());
		for (requirement in requirements) {
			final accessRequirement = requirement.semanticCapability == OcamlBytesRuntimeRequirementRecorder.HAXE_BYTES_ACCESS
				&& requirement.subject.id == OcamlBytesRepresentationContract.DIRECT_SEMANTIC_TYPE_ID
				&& requirement.rootModules.join(",") == "HxBytes";
			final nullableRequirement = requirement.semanticCapability == OcamlBytesRuntimeRequirementRecorder.HAXE_BYTES_ACCESS_NULLABLE_INT
				&& requirement.subject.id == "Null<Int>"
				&& requirement.rootModules.join(",") == "HxRuntime";
			if (!accessRequirement && !nullableRequirement) {
				Context.error('Runtime requirement "${requirement.id}" does not select the exact HxBytes access contract.', Context.currentPos());
			}
		}

		final sample = Lambda.find(decisions, decision -> decision.kind == OcamlBytesAccessKind.GetData
			&& decision.functionId == "BytesAccessCases.getData");
		if (sample == null)
			Context.error("The Bytes access fixture has no getData decision.", Context.currentPos());
		expectThrows("duplicate-access", () -> new OcamlBytesAccessPlan([sample, sample]));
		expectThrows("conflicting-access", () -> new OcamlBytesAccessPlan([sample, reseal(sample, {bodyRevision: sample.bodyRevision + ":conflict"})]));
		expectThrows("invalid-access", () -> new OcamlBytesAccessPlan([copy(sample, {kind: OcamlBytesAccessKind.Get})]));
		expectThrows("invalid-access", () -> new OcamlBytesAccessPlan([reseal(sample, {evaluationOrder: []})]));
		expectThrows("invalid-access", () -> new OcamlBytesAccessPlan([reseal(sample, {aliasPolicy: OcamlBytesAccessAliasPolicy.NoNewAlias})]));
		expectThrows("invalid-access", () -> new OcamlBytesAccessPlan([reseal(sample, {occurrenceId: "bytes-access-occurrence:not-a-digest"})]));
		expectThrows("invalid-access", () -> new OcamlBytesAccessPlan([
			reseal(sample, {boundsPolicy: OcamlBytesAccessBoundsPolicy.DeclaredBytesChecked})
		]));
		expectThrows("invalid-access-runtime-use", () -> new OcamlBytesAccessPlan([copy(sample, {runtimeUseOccurrences: []})]));
		final wrongRuntimeUse:Dynamic = Reflect.copy(sample.runtimeUseOccurrences[0]);
		Reflect.setField(wrongRuntimeUse, "exactSymbol", "HxBytes.get");
		expectThrows("invalid-access-runtime-use", () -> new OcamlBytesAccessPlan([copy(sample, {runtimeUseOccurrences: [wrongRuntimeUse]})]));
		final numericSample = Lambda.find(decisions,
			decision -> decision.kind == OcamlBytesAccessKind.GetUInt16 && decision.functionId == "BytesAccessCases.getUInt16");
		if (numericSample == null)
			Context.error("The Bytes access fixture has no getUInt16 decision.", Context.currentPos());
		expectThrows("invalid-access", () -> new OcamlBytesAccessPlan([reseal(numericSample, {accessWidthBytes: 1})]));
		expectThrows("invalid-access", () -> new OcamlBytesAccessPlan([
			reseal(numericSample, {byteOrderPolicy: OcamlBytesAccessByteOrderPolicy.NotApplicable})
		]));
		expectThrows("invalid-access", () -> new OcamlBytesAccessPlan([
			reseal(numericSample, {valuePolicy: OcamlBytesAccessValuePolicy.UnsignedByteRead})
		]));
		expectThrows("invalid-access-argument", () -> new OcamlBytesAccessPlan([
			reseal(numericSample, {
				argumentInputSemanticTypeIds: ["Null<Int>"],
				argumentInputCarrierTypeIds: ["Obj.t"],
				argumentConversions: [OcamlBytesAccessArgumentConversion.RequireNonNullInt]
			})
		]));
		final nullableNumericSample = Lambda.find(decisions,
			decision -> decision.kind == OcamlBytesAccessKind.GetUInt16
				&& decision.functionId == "BytesAccessCases.getUInt16NullablePosition");
		if (nullableNumericSample == null)
			Context.error("The Bytes access fixture has no nullable getUInt16 decision.", Context.currentPos());
		final doubleNullableSample = Lambda.find(decisions, decision -> decision.functionId == "BytesAccessCases.setUInt16NullablePositionAndValue");
		if (doubleNullableSample == null || doubleNullableSample.runtimeUseOccurrences.length != 3)
			Context.error("The Bytes access fixture has no two-conversion access decision.", Context.currentPos());
		final reversedRuntimeUses = doubleNullableSample.runtimeUseOccurrences.copy();
		reversedRuntimeUses.reverse();
		expectThrows("invalid-access-runtime-use", () -> new OcamlBytesAccessPlan([copy(doubleNullableSample, {runtimeUseOccurrences: reversedRuntimeUses})]));
		expectThrows("invalid-access-argument", () -> new OcamlBytesAccessPlan([
			reseal(nullableNumericSample, {argumentConversions: [OcamlBytesAccessArgumentConversion.RequireNonNullInt]})
		]));
		final int64ReadSample = Lambda.find(decisions,
			decision -> decision.kind == OcamlBytesAccessKind.GetInt64 && decision.functionId == "BytesAccessCases.getInt64");
		if (int64ReadSample == null)
			Context.error("The Bytes access fixture has no getInt64 decision.", Context.currentPos());
		expectThrows("invalid-access", () -> new OcamlBytesAccessPlan([reseal(int64ReadSample, {accessWidthBytes: 4})]));
		expectThrows("invalid-access", () -> new OcamlBytesAccessPlan([
			reseal(int64ReadSample, {boundsPolicy: OcamlBytesAccessBoundsPolicy.NativeDataChecked})
		]));
		expectThrows("invalid-access", () -> new OcamlBytesAccessPlan([
			reseal(int64ReadSample, {byteOrderPolicy: OcamlBytesAccessByteOrderPolicy.NotApplicable})
		]));
		expectThrows("invalid-access", () -> new OcamlBytesAccessPlan([
			reseal(int64ReadSample, {valuePolicy: OcamlBytesAccessValuePolicy.SignedThirtyTwoBitRead})
		]));
		expectThrows("invalid-access", () -> new OcamlBytesAccessPlan([reseal(int64ReadSample, {runtimeOperation: "getInt32"})]));
		expectThrows("invalid-access", () -> new OcamlBytesAccessPlan([reseal(int64ReadSample, {evaluationOrder: [0, -1]})]));
		expectThrows("invalid-access-result", () -> new OcamlBytesAccessPlan([
			reseal(int64ReadSample, {
				resultSemanticTypeId: "Int",
				resultCarrierTypeId: "int",
				resultRepresentationId: numericSample.resultRepresentationId,
				resultRepresentationRevision: numericSample.resultRepresentationRevision
			})
		]));
		expectThrows("stale-access", () -> new OcamlBytesAccessPlan([int64ReadSample]).requirePlanBinding({
			functionId: int64ReadSample.functionId,
			programRevision: int64ReadSample.programRevision,
			bodyRevision: int64ReadSample.bodyRevision,
			pipelineRevision: int64ReadSample.pipelineRevision + ":changed"
		}));
		final int64WriteSample = Lambda.find(decisions,
			decision -> decision.kind == OcamlBytesAccessKind.SetInt64 && decision.functionId == "BytesAccessCases.setInt64");
		if (int64WriteSample == null)
			Context.error("The Bytes access fixture has no setInt64 decision.", Context.currentPos());
		final wrongInt64InputSemantics = int64WriteSample.argumentInputSemanticTypeIds.copy();
		final wrongInt64InputCarriers = int64WriteSample.argumentInputCarrierTypeIds.copy();
		final wrongInt64Semantics = int64WriteSample.argumentSemanticTypeIds.copy();
		final wrongInt64Carriers = int64WriteSample.argumentCarrierTypeIds.copy();
		wrongInt64InputSemantics[1] = "Int";
		wrongInt64InputCarriers[1] = "int";
		wrongInt64Semantics[1] = "Int";
		wrongInt64Carriers[1] = "int";
		expectThrows("invalid-access-argument", () -> new OcamlBytesAccessPlan([
			reseal(int64WriteSample, {
				argumentInputSemanticTypeIds: wrongInt64InputSemantics,
				argumentInputCarrierTypeIds: wrongInt64InputCarriers,
				argumentSemanticTypeIds: wrongInt64Semantics,
				argumentCarrierTypeIds: wrongInt64Carriers
			})
		]));
		final float32ReadSample = Lambda.find(decisions,
			decision -> decision.kind == OcamlBytesAccessKind.GetFloat32 && decision.functionId == "BytesAccessCases.getFloat");
		if (float32ReadSample == null)
			Context.error("The Bytes access fixture has no getFloat decision.", Context.currentPos());
		expectThrows("invalid-access", () -> new OcamlBytesAccessPlan([reseal(float32ReadSample, {accessWidthBytes: 8})]));
		expectThrows("invalid-access", () -> new OcamlBytesAccessPlan([
			reseal(float32ReadSample, {valuePolicy: OcamlBytesAccessValuePolicy.Ieee754Binary64})
		]));
		expectThrows("invalid-access", () -> new OcamlBytesAccessPlan([reseal(float32ReadSample, {runtimeOperation: "getDouble"})]));
		expectThrows("invalid-access-result", () -> new OcamlBytesAccessPlan([
			reseal(float32ReadSample, {
				resultSemanticTypeId: "Int",
				resultCarrierTypeId: "int",
				resultRepresentationId: numericSample.resultRepresentationId,
				resultRepresentationRevision: numericSample.resultRepresentationRevision
			})
		]));
		final float32WriteSample = Lambda.find(decisions,
			decision -> decision.kind == OcamlBytesAccessKind.SetFloat32 && decision.functionId == "BytesAccessCases.setFloat");
		if (float32WriteSample == null)
			Context.error("The Bytes access fixture has no setFloat decision.", Context.currentPos());
		final wrongFloatInputSemantics = float32WriteSample.argumentInputSemanticTypeIds.copy();
		final wrongFloatInputCarriers = float32WriteSample.argumentInputCarrierTypeIds.copy();
		final wrongFloatSemantics = float32WriteSample.argumentSemanticTypeIds.copy();
		final wrongFloatCarriers = float32WriteSample.argumentCarrierTypeIds.copy();
		wrongFloatInputSemantics[1] = "Int";
		wrongFloatInputCarriers[1] = "int";
		wrongFloatSemantics[1] = "Int";
		wrongFloatCarriers[1] = "int";
		expectThrows("invalid-access-argument", () -> new OcamlBytesAccessPlan([
			reseal(float32WriteSample, {
				argumentInputSemanticTypeIds: wrongFloatInputSemantics,
				argumentInputCarrierTypeIds: wrongFloatInputCarriers,
				argumentSemanticTypeIds: wrongFloatSemantics,
				argumentCarrierTypeIds: wrongFloatCarriers
			})
		]));
		final float64ReadSample = Lambda.find(decisions,
			decision -> decision.kind == OcamlBytesAccessKind.GetFloat64 && decision.functionId == "BytesAccessCases.getDouble");
		if (float64ReadSample == null)
			Context.error("The Bytes access fixture has no getDouble decision.", Context.currentPos());
		expectThrows("invalid-access", () -> new OcamlBytesAccessPlan([reseal(float64ReadSample, {accessWidthBytes: 4})]));
		expectThrows("invalid-access", () -> new OcamlBytesAccessPlan([
			reseal(float64ReadSample, {valuePolicy: OcamlBytesAccessValuePolicy.Ieee754Binary32})
		]));
		final float64WriteSample = Lambda.find(decisions,
			decision -> decision.kind == OcamlBytesAccessKind.SetFloat64 && decision.functionId == "BytesAccessCases.setDouble");
		if (float64WriteSample == null)
			Context.error("The Bytes access fixture has no setDouble decision.", Context.currentPos());
		expectThrows("invalid-access", () -> new OcamlBytesAccessPlan([
			reseal(float64WriteSample, {byteOrderPolicy: OcamlBytesAccessByteOrderPolicy.NotApplicable})
		]));
		expectThrows("invalid-access-result", () -> new OcamlBytesAccessPlan([reseal(sample, {resultCarrierTypeId: "Obj.t"})]));
		expectThrows("invalid-access",
			() -> OcamlBytesRuntimeRequirementRecorder.recordAccess(ledger, copy(sample, {calleeId: sample.calleeId + ":tampered"})));
		expectThrows("stale-access", () -> new OcamlBytesAccessPlan([sample]).requirePlanBinding({
			functionId: sample.functionId,
			programRevision: sample.programRevision,
			bodyRevision: sample.bodyRevision + ":changed",
			pipelineRevision: sample.pipelineRevision
		}));

		final getDataBody = requireBody(requireField(cases, "getData"));
		final getDataOccurrence = accessOccurrence(getDataBody);
		expectThrows("missing-access", () -> new OcamlBytesAccessPlan([]).requireFor(getDataOccurrence, representations));
		final missingRepresentations = new OcamlRepresentationRegistry();
		missingRepresentations.beginProgram(PROGRAM_REVISION);
		expectThrows("missing-decision", () -> new OcamlBytesAccessPlan([sample]).requireFor(getDataOccurrence, missingRepresentations));
		final firstSharedSpanOccurrence:TypedExpr = {
			expr: getDataOccurrence.expr,
			pos: getDataOccurrence.pos,
			t: getDataOccurrence.t
		};
		final secondSharedSpanOccurrence:TypedExpr = {
			expr: getDataOccurrence.expr,
			pos: getDataOccurrence.pos,
			t: getDataOccurrence.t
		};
		final sharedSpanRoot:TypedExpr = {
			expr: TBlock([firstSharedSpanOccurrence, secondSharedSpanOccurrence]),
			pos: getDataOccurrence.pos,
			t: getDataOccurrence.t
		};
		final sharedSpanPlan = new OcamlBytesAccessPlanner(binding("sharedSpan"), representations).plan(sharedSpanRoot);
		final sharedSpanDecisions = sharedSpanPlan.decisions();
		if (sharedSpanDecisions.length != 2
			|| sharedSpanDecisions[0].occurrenceId == sharedSpanDecisions[1].occurrenceId
			|| sharedSpanDecisions[0].source.file != sharedSpanDecisions[1].source.file
			|| sharedSpanDecisions[0].source.min != sharedSpanDecisions[1].source.min
			|| sharedSpanDecisions[0].source.max != sharedSpanDecisions[1].source.max
			|| sharedSpanPlan.requireFor(firstSharedSpanOccurrence, representations)
				.id == sharedSpanPlan.requireFor(secondSharedSpanOccurrence, representations)
				.id) {
			Context.error("Distinct typed Bytes accesses with one shared source span did not retain exact structural identities.", Context.currentPos());
		}

		final standaloneRegistry = new OcamlFunctionPlanRegistry();
		standaloneRegistry.beginProgram(PROGRAM_REVISION);
		final standaloneOwner = "field-initializer:static:BytesAccessCases::data";
		final firstStandalone = standaloneRegistry.sealStandaloneExpression(standaloneOwner, getDataBody, representations);
		final secondStandalone = standaloneRegistry.sealStandaloneExpression(standaloneOwner, getDataBody, representations);
		standaloneRegistry.requireStandaloneExpressionPlan(getDataBody, firstStandalone, representations);
		if (firstStandalone.bytesAccesses.revision != secondStandalone.bytesAccesses.revision
			|| firstStandalone.bytesAccesses.decisions().length != 1) {
			Context.error("Standalone Bytes access planning did not preserve the exact expression binding.", Context.currentPos());
		}

		Sys.println("REFLAXE_OCAML_BYTES_ACCESS_PLAN_FIXTURE:PASS");
		return macro null;
	}

	static function requireNumericPolicy(decision:OcamlBytesAccessDecision, width:Int, valuePolicy:OcamlBytesAccessValuePolicy,
			mutationPolicy:OcamlBytesAccessMutationPolicy, resultKind:OcamlBytesAccessResultKind, position:haxe.macro.Expr.Position):Void {
		if (decision.boundsPolicy != OcamlBytesAccessBoundsPolicy.DeclaredBytesChecked
			|| decision.accessWidthBytes != width
			|| decision.byteOrderPolicy != OcamlBytesAccessByteOrderPolicy.LittleEndian
			|| decision.valuePolicy != valuePolicy
			|| decision.mutationPolicy != mutationPolicy
			|| decision.aliasPolicy != OcamlBytesAccessAliasPolicy.NoNewAlias
			|| decision.resultKind != resultKind) {
			Context.error('Bytes numeric access "${decision.id}" did not seal its exact $width-byte policy.', position);
		}
	}

	static function requireExactFloatResult(decision:OcamlBytesAccessDecision, name:String, position:haxe.macro.Expr.Position):Void {
		if (decision.resultSemanticTypeId != OcamlFloatRepresentationContract.SEMANTIC_TYPE_ID
			|| decision.resultCarrierTypeId != OcamlFloatRepresentationContract.CARRIER_TYPE_ID
			|| decision.resultRepresentationId != OcamlFloatRepresentationContract.INTERNAL_REPRESENTATION_ID) {
			Context.error('Bytes access case "$name" did not seal the exact Float result carrier.', position);
		}
	}

	static function requireExactFloatArgument(decision:OcamlBytesAccessDecision, name:String, position:haxe.macro.Expr.Position):Void {
		if (decision.argumentSemanticTypeIds[1] != OcamlFloatRepresentationContract.SEMANTIC_TYPE_ID
			|| decision.argumentCarrierTypeIds[1] != OcamlFloatRepresentationContract.CARRIER_TYPE_ID
			|| decision.argumentRepresentationIds[1] != OcamlFloatRepresentationContract.INTERNAL_REPRESENTATION_ID) {
			Context.error('Bytes access case "$name" did not seal the exact Float value argument.', position);
		}
	}

	static function requireNullableIntConversion(decision:OcamlBytesAccessDecision, index:Int, expected:OcamlBytesAccessArgumentConversion,
			position:haxe.macro.Expr.Position):Void {
		if (decision.argumentInputSemanticTypeIds[index] != "Null<Int>"
			|| decision.argumentSemanticTypeIds[index] != "Int"
			|| decision.argumentConversions[index] != expected) {
			Context.error('Bytes access "${decision.id}" did not seal nullable Int argument $index.', position);
		}
	}

	static function binding(name:String):OcamlFunctionPlanBinding {
		return {
			functionId: "BytesAccessCases." + name,
			programRevision: PROGRAM_REVISION,
			bodyRevision: BODY_REVISION + ":" + name,
			pipelineRevision: PIPELINE_REVISION
		};
	}

	static function unadmittedCases():Array<{name:String, fieldName:String, expression:TypedExpr}> {
		return [
			{
				name: "setFloatNullableValue",
				fieldName: "setFloat",
				expression: Context.typeExpr(macro function(bytes:haxe.io.Bytes, position:Int, value:Null<Float>):Void {
					bytes.setFloat(position, value);
				})
			},
			{
				name: "setDoubleNullableValue",
				fieldName: "setDouble",
				expression: Context.typeExpr(macro function(bytes:haxe.io.Bytes, position:Int, value:Null<Float>):Void {
					bytes.setDouble(position, value);
				})
			},
		];
	}

	static function containsExactTargetCall(expression:TypedExpr, fieldName:String):Bool {
		var found = false;
		function visit(candidate:TypedExpr):Void {
			if (found)
				return;
			switch (candidate.expr) {
				case TCall({expr: TField(_, FInstance(classRef, _, fieldRef))}, _):
					final classType = classRef.get();
					if (classType.module == "haxe.io.Bytes" && classType.name == "Bytes" && fieldRef.get().name == fieldName) {
						found = true;
						return;
					}
				case _:
			}
			TypedExprTools.iter(candidate, visit);
		}
		visit(expression);
		return found;
	}

	static function caseFields():Map<String, ClassField> {
		return switch (Context.getType("BytesAccessCases")) {
			case TInst(classRef, _): [for (field in classRef.get().statics.get()) field.name => field];
			case _: Context.error("BytesAccessCases did not resolve to a class.", Context.currentPos());
		}
	}

	static function requireField(fields:Map<String, ClassField>, name:String):ClassField {
		final field = fields.get(name);
		if (field == null)
			Context.error('Missing typed Bytes access case "$name".', Context.currentPos());
		return field;
	}

	static function requireBody(field:ClassField):TypedExpr {
		final body = field.expr();
		if (body == null)
			Context.error('Bytes access case "${field.name}" has no typed body.', field.pos);
		return body;
	}

	static function accessOccurrence(body:TypedExpr):Null<TypedExpr> {
		var found:Null<TypedExpr> = null;
		function visit(expression:TypedExpr):Void {
			if (found != null)
				return;
			if (OcamlBytesAccessPlan.admittedOccurrence(expression) != null) {
				found = expression;
				return;
			}
			TypedExprTools.iter(expression, visit);
		}
		visit(body);
		return found;
	}

	static function copy(decision:OcamlBytesAccessDecision, changes:Dynamic):OcamlBytesAccessDecision {
		final value:Dynamic = {};
		for (field in Reflect.fields(decision))
			Reflect.setField(value, field, Reflect.field(decision, field));
		for (field in Reflect.fields(changes))
			Reflect.setField(value, field, Reflect.field(changes, field));
		return cast value;
	}

	static function reseal(decision:OcamlBytesAccessDecision, changes:Dynamic):OcamlBytesAccessDecision {
		final value:Dynamic = copy(decision, changes);
		final changed:OcamlBytesAccessDecision = cast value;
		final id = OcamlBytesAccessContract.idFor(changed);
		Reflect.setField(value, "id", id);
		final identified:OcamlBytesAccessDecision = cast value;
		Reflect.setField(value, "runtimeRequirementIds", OcamlBytesAccessContract.runtimeRequirementIdsFor(identified));
		Reflect.setField(value, "runtimeUseOccurrences", OcamlBytesAccessContract.runtimeUseOccurrencesFor(identified));
		return cast value;
	}

	static function expectThrows(code:String, operation:Void->Void):Void {
		expectedFailureIndex += 1;
		var message:Null<String> = null;
		try {
			operation();
		} catch (error:Dynamic) {
			message = Std.string(error);
		}
		if (message == null || message.indexOf(code) < 0)
			Context.error('Expected failure $expectedFailureIndex containing "$code", received ${message == null ? "no failure" : message}.',
				Context.currentPos());
	}
}
