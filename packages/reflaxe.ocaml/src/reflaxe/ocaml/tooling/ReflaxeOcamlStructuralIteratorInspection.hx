package reflaxe.ocaml.tooling;

import reflaxe.ocaml.lowered.OcamlStructuralIteratorCallModel.OcamlStructuralIteratorCallContract;
import reflaxe.ocaml.lowered.OcamlStructuralIteratorCallModel.OcamlStructuralIteratorCallTarget;
import reflaxe.ocaml.tooling.InspectionReport.InspectionCall;

/**
	Validates direct structural Iterator consumers in a saved lowering report.

	Inspection runs without the original compiler request. It therefore checks
	the plain report data against the same pure contract used during lowering,
	including the selected HxIterator function, receiver carrier, proof, and
	source identity.
**/
class ReflaxeOcamlStructuralIteratorInspection {
	/** Rejects a report entry that no longer represents its sealed Iterator call. */
	public static function validate(call:InspectionCall):Void {
		final target = call.structuralIteratorTarget;
		if (target == null)
			throw 'Structural Iterator call "${call.id}" has no sealed target.';
		if (call.receiver != null || call.arguments.length != 0 || call.result != null)
			throw 'Structural Iterator call "${call.id}" must not duplicate its target as ordinary call crossings.';

		final sealedTarget:OcamlStructuralIteratorCallTarget = cast target;
		OcamlStructuralIteratorCallContract.require(sealedTarget);
		final expectedField = OcamlStructuralIteratorCallContract.sourceFieldName(sealedTarget.operation);
		if (call.sourceModuleId != "haxe.Iterator"
			|| call.sourceTypeName != "Iterator"
			|| call.sourceFieldName != expectedField
			|| call.calleeId != 'haxe.Iterator|Iterator::$expectedField'
			|| call.resultKind != "value"
			|| call.proofId != OcamlStructuralIteratorCallContract.PROOF_ID
			|| call.proofId != target.proofId
			|| call.proofClaim.length == 0
			|| call.proofClaim != target.proofClaim
			|| call.functionId.length == 0
			|| call.programRevision.length == 0
			|| call.bodyRevision.length == 0
			|| call.pipelineRevision != "ocaml-function-plans-v88"
			|| call.profileEligibility.length != 2
			|| call.profileEligibility[0] != "metal"
			|| call.profileEligibility[1] != "portable") {
			throw 'Structural Iterator call "${call.id}" disagrees with its source identity, proof, result, revisions, or profile inventory.';
		}
	}
}
