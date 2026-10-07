package reflaxe.ocaml.tooling;

import reflaxe.ocaml.lowered.OcamlGenericInstanceCallContract.PROOF_CLAIM as genericCallProofClaim;
import reflaxe.ocaml.lowered.OcamlGenericInstanceCallContract.PROOF_ID as genericCallProofId;
import reflaxe.ocaml.lowered.OcamlGenericInstanceCallContract.fingerprint as genericCallFingerprint;
import reflaxe.ocaml.lowered.OcamlGenericInstanceCallContract.require as genericCallRequire;
import haxe.crypto.Sha256;
import reflaxe.ocaml.tooling.InspectionReport.InspectionCall;
import reflaxe.ocaml.tooling.InspectionReport.InspectionRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueShape;
import reflaxe.ocaml.reports.OcamlGenericCallReport.targetFromReport;

/** Validates decoded generic call reports against their exact receiver and caller identities. */
function validate(call:InspectionCall, representations:Map<String, InspectionRepresentationDecision>):Void {
	if (call.genericInstanceTarget == null)
		throw 'Generic call "${call.id}" has no decoded target.';
	final target = targetFromReport(call.genericInstanceTarget);
	genericCallRequire(target);
	final receiver = representations.get(target.receiverRepresentationId);
	if (receiver == null
		|| receiver.semanticTypeId != target.receiverTypeId
		|| receiver.boxingPolicy != "nullable-nominal-record-carrier"
		|| receiver.programRevision != call.programRevision)
		throw 'Generic call "${call.id}" has no matching direct-record receiver proof.';
	final expectedId = "call:" + Sha256.encode([
		call.functionId,
		call.programRevision,
		call.bodyRevision,
		call.pipelineRevision,
		'${call.sourceFile}:${call.sourceMin}:${call.sourceMax}',
		genericCallFingerprint(target)
	].join("|")).substr(0, 24);
	if (call.kind != "generic-instance-haxe-method"
		|| call.id != expectedId
		|| call.calleeId != '${target.moduleId}|${target.typeName}::${target.fieldName}'
		|| call.sourceModuleId != target.moduleId
		|| call.sourceTypeName != target.typeName
		|| call.sourceFieldName != target.fieldName
		|| call.receiver != null
		|| call.arguments.length != 0
		|| call.result != null
		|| call.resultMaterialization != null
		|| call.resultKind != (target.resultShape == EffectOnly ? "effect-only-void" : "value")
		|| call.dynamicFunctionTarget != null
		|| call.standardArrayTarget != null
		|| call.standardIMapTarget != null
		|| call.structuralIteratorTarget != null
		|| call.proofId != genericCallProofId
		|| call.proofClaim != genericCallProofClaim
		|| call.reason.length == 0
		|| call.functionId.length == 0
		|| call.programRevision.length == 0
		|| call.bodyRevision.length == 0
		|| call.pipelineRevision.length == 0
		|| call.sourceFile.length == 0
		|| call.profileEligibility.join(",") != "metal,portable")
		throw 'Generic call "${call.id}" has stale or conflicting method, result, proof, or caller facts.';
}
