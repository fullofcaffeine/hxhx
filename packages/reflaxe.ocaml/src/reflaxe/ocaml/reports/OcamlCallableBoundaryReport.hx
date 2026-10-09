package reflaxe.ocaml.reports;

#if (macro || reflaxe_runtime)
import reflaxe.ocaml.lowered.OcamlCallPlan;
import reflaxe.ocaml.lowered.OcamlCallableReturnContract;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation.OcamlCallableViewDescriptor;
import reflaxe.ocaml.lowered.OcamlFunctionResultBoundary.OcamlFunctionResultBoundaryPlan;
import reflaxe.ocaml.reports.OcamlCallableCallReport.returnToReport;
import reflaxe.ocaml.reports.OcamlCallableCallReport.argumentToReport;
import reflaxe.ocaml.reports.OcamlCallableViewReport.layoutToReport;

/** Project a call carrier without losing the descriptor that proves a recursive callback layout. */
function valueToReport(value:OcamlCallValuePlan) {
	if (value.callableView != null)
		reflaxe.ocaml.lowered.OcamlCallableDeclarationCarrier.requireValue(value);
	return {
		index: value.index,
		parameterOptional: value.parameterOptional,
		inputSemanticTypeId: value.inputSemanticTypeId,
		inputCarrierTypeId: value.inputCarrierTypeId,
		inputRepresentationId: value.inputRepresentationId,
		outputSemanticTypeId: value.outputSemanticTypeId,
		outputCarrierTypeId: value.outputCarrierTypeId,
		outputRepresentationId: value.outputRepresentationId,
		conversion: value.conversion,
		proofId: value.proofId,
		proofClaim: value.proofClaim,
		nullableEnumCarrier: value.nullableEnumCarrier,
		callableView: value.callableView == null ? null : layoutToReport(value.callableView),
		callbackArgument: value.callbackArgument == null ? null : argumentToReport(value.callbackArgument)
	};
}

/** Export only detached, validated values from the exact final callable boundary. */
function boundaryToReport(value:OcamlCallableBoundaryPlan) {
	OcamlCallPlan.requireCallableBoundary(value);
	return {
		id: value.id,
		calleeId: value.calleeId,
		sourceModuleId: value.sourceModuleId,
		sourceTypeName: value.sourceTypeName,
		sourceFieldName: value.sourceFieldName,
		kind: value.kind,
		receiver: value.receiver == null ? null : valueToReport(value.receiver),
		arguments: value.arguments.map(valueToReport),
		resultKind: value.resultKind,
		result: value.result == null ? null : valueToReport(value.result),
		profileEligibility: value.profileEligibility,
		reason: value.reason,
		proofId: value.proofId,
		proofClaim: value.proofClaim,
		functionId: value.functionId,
		programRevision: value.programRevision,
		bodyRevision: value.bodyRevision,
		pipelineRevision: value.pipelineRevision,
		callbackReturnCount: value.callbackReturnCount,
		callbackReturns: value.callbackReturns == null ? null : value.callbackReturns.map(returnToReport)
	};
}

/** Result-only records share the exact same projected carrier as their callable owner. */
function resultToReport(value:OcamlFunctionResultBoundaryPlan) {
	return {
		id: value.id,
		source: value.source,
		callableBoundaryId: value.callableBoundaryId,
		sourceModuleId: value.sourceModuleId,
		sourceTypeName: value.sourceTypeName,
		sourceFieldName: value.sourceFieldName,
		resultKind: value.resultKind,
		result: value.result == null ? null : valueToReport(value.result),
		anonymousStructure: value.anonymousStructure,
		nullableEnum: value.nullableEnum,
		profileEligibility: value.profileEligibility,
		reason: value.reason,
		proofId: value.proofId,
		proofClaim: value.proofClaim,
		functionId: value.functionId,
		programRevision: value.programRevision,
		bodyRevision: value.bodyRevision,
		pipelineRevision: value.pipelineRevision
	};
}
#end
