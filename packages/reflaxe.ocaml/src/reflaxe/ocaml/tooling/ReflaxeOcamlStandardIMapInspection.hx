package reflaxe.ocaml.tooling;

import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapCallContract;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapCallTarget;
import reflaxe.ocaml.tooling.InspectionReport.InspectionCall;

/**
	Validates the standard-Map subset recorded in an OCaml lowering report.

	The report uses strings so it can be read without a live compiler request.
	This helper converts that data to the canonical pure target contract, then
	checks the call-specific source identity and result classification. Keeping
	this outside the general inspection module prevents a second copy of the
	Map carrier, method, and adapter rules from drifting.
**/
class ReflaxeOcamlStandardIMapInspection {
	/**
		Rejects a standard-library Map report that no longer describes the exact
		typed carrier, operation, adapter, and runtime dependencies selected by
		the compiler.
	**/
	public static function validate(call:InspectionCall):Void {
		final target = call.standardIMapTarget;
		if (target == null)
			throw 'Standard IMap call "${call.id}" has no sealed target.';
		if (call.receiver != null || call.arguments.length != 0 || call.result != null)
			throw 'Standard IMap call "${call.id}" must not duplicate its target as ordinary call crossings.';

		final sealedTarget:OcamlStandardIMapCallTarget = cast target;
		OcamlStandardIMapCallContract.require(sealedTarget);
		final expectedField = OcamlStandardIMapCallContract.sourceFieldName(sealedTarget.operation);
		final effectOnly = target.resultSemanticTypeId == "Void";
		if (call.sourceModuleId != "haxe.Constraints"
			|| call.sourceTypeName != "IMap"
			|| call.sourceFieldName != expectedField
			|| call.calleeId != 'haxe.Constraints|haxe.IMap::$expectedField'
			|| call.proofId != OcamlStandardIMapCallContract.PROOF_ID
			|| call.proofId != target.proofId
			|| call.proofClaim.length == 0
			|| call.proofClaim != target.proofClaim
			|| (effectOnly && call.resultKind != "effect-only-void")
			|| (!effectOnly && call.resultKind != "value")
			|| call.profileEligibility.length != 2
			|| call.profileEligibility[0] != "metal"
			|| call.profileEligibility[1] != "portable") {
			throw 'Standard IMap call "${call.id}" disagrees with its source declaration, proof, result, or profile inventory.';
		}
	}

	/** Returns the exact runtime feature and root selected by one capability. */
	public static function runtimeImplementation(capability:String):{feature:String, root:String} {
		return switch (capability) {
			case "haxe-map": {feature: "haxe-map-v1", root: "HxMap"};
			case "haxe-iterator": {feature: "haxe-iterator-v1", root: "HxIterator"};
			case "haxe-array": {feature: "haxe-array-v1", root: "HxArray"};
			case "haxe-string-text": {feature: "haxe-string-text-v1", root: "HxString"};
			case "haxe-dynamic-text": {feature: "haxe-dynamic-text-v1", root: "HxDynamic"};
			case _: throw 'Unsupported standard IMap runtime capability "$capability".';
		}
	}
}
