package reflaxe.ocaml.tooling;

import reflaxe.ocaml.reports.OcamlCallableViewInventory;
import reflaxe.ocaml.reports.OcamlCallableViewInventory.CallableViewInventoryReport;
import reflaxe.ocaml.reports.OcamlReportJson.encode;
import reflaxe.ocaml.lowered.OcamlCallableViewContract;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation.OcamlCallableViewDescriptor;
import reflaxe.ocaml.lowered.OcamlLocalConversionModel.OcamlLocalRepresentationReference;
import reflaxe.ocaml.tooling.InspectionReport.InspectionRepresentationDecision;

/** Check offline callback evidence against the report's registered program storage. */
function inspect(value:Dynamic, representations:Array<InspectionRepresentationDecision>, pipeline:String):CallableViewInventoryReport {
	final report = fromReport(value);
	final byId:Map<String, InspectionRepresentationDecision> = [];
	for (representation in representations)
		byId.set(representation.id, representation);
	final used:Map<String, Bool> = [];
	function requireStorage(reference:OcamlLocalRepresentationReference, layout:OcamlCallableViewDescriptor, program:String):Void {
		final selected = byId.get(reference.representationId);
		if (selected == null
			|| selected.revision != reference.representationRevision
			|| selected.programRevision != program
			|| selected.semanticTypeId != reference.semanticTypeId
			|| selected.semanticTypeId != layout.semanticTypeId
			|| selected.domain != reference.domain
			|| selected.domain != "internal-value"
			|| selected.carrierTypeId != layout.carrierTypeId
			|| selected.boxingPolicy != "callable-identity-view"
			|| selected.nullPolicy != "non-null"
			|| selected.identityPolicy != "reference-identity"
			|| selected.aliasingPolicy != "shared-reference-aliases"
			|| selected.storageMutationPolicy != "immutable-binding"
			|| selected.valueMutationPolicy != "immutable-value"
			|| selected.implicitDefaultPolicy != "not-admitted"
			|| selected.proofId != "ocaml-callable-identity-view-v1:" + layout.revision
			|| selected.profileEligibility.join(",") != "metal,portable")
			throw "Callback occurrence does not match its registered immutable local view.";
		used.set(selected.id, true);
	}
	for (decision in decisions(report)) {
		if (decision.binding.pipelineRevision != pipeline)
			throw "Callback occurrence belongs to another target pipeline revision.";
		requireStorage(decision.output, decision.outputLayout, decision.binding.programRevision);
		switch (decision.input) {
			case ExistingView(reference):
				requireStorage(reference, decision.inputLayout, decision.binding.programRevision);
			case RawOrigin(_):
		}
	}
	for (representation in representations)
		if (representation.boxingPolicy == "callable-identity-view" && !used.exists(representation.id))
			throw "A registered callback layout has no source-bound occurrence evidence.";
	return report;
}

/** Recompute the helpers from typed conversions and require exact report ownership. */
function validateRuntime(report:CallableViewInventoryReport, requirements:Map<String, Dynamic>):Array<String> {
	final ids:Array<String> = [];
	for (decision in decisions(report)) {
		for (expected in reflaxe.ocaml.lowered.OcamlCallableViewRuntime.requirements(decision)) {
			final recorded = requirements.get(expected.id);
			if (recorded == null || encode(recorded) != encode(expected))
				throw 'Callback occurrence "${decision.id}" has missing or changed runtime evidence "${expected.id}".';
			ids.push(expected.id);
		}
	}
	return ids;
}
