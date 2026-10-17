package reflaxe.ocaml.tooling;

import reflaxe.ocaml.reports.OcamlCallableViewInventory;
import reflaxe.ocaml.reports.OcamlCallableViewInventory.CallableViewInventoryReport;
import reflaxe.ocaml.reports.OcamlReportJson.encode;
import reflaxe.ocaml.lowered.OcamlCallableViewContract;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation.OcamlCallableViewDescriptor;
import reflaxe.ocaml.lowered.OcamlLocalConversionModel.OcamlLocalRepresentationReference;
import reflaxe.ocaml.tooling.InspectionReport.InspectionRepresentationDecision;
import reflaxe.ocaml.tooling.InspectionReport.InspectionCall;
import reflaxe.ocaml.tooling.InspectionReport.InspectionCallableBoundary;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.reports.OcamlCallableViewReport.layoutFromReport;
import reflaxe.ocaml.reports.OcamlCallableCallReport.argumentFromReport;
import reflaxe.ocaml.tooling.ReflaxeOcamlCallableCallInspection.binding;

/** Counts describe every validated callback operation, including conversions outside local initializers. */
function operationCounts(report:CallableViewInventoryReport, calls:Array<InspectionCall>, boundaries:Array<InspectionCallableBoundary>) {
	var arguments = 0;
	var returns = 0;
	var invocations = 0;
	var unsafeOperations = Lambda.fold(report.entries, (entry, count) -> count + entry.unsafeOperations.length, 0)
		+ Lambda.fold(report.comparisons, (entry, count) -> count + entry.unsafeOperations.length, 0);
	var runtimeUses = Lambda.fold(report.entries, (entry, count) -> count + entry.runtimeUses.length, 0)
		+ Lambda.fold(report.comparisons, (entry, count) -> count + entry.runtimeUses.length, 0);
	for (call in calls) {
		if (call.callbackInvocation != null)
			invocations++;
		for (argument in call.arguments)
			if (argument.callbackArgument != null) {
				arguments++;
				unsafeOperations += argument.callbackArgument.unsafeOperations.length;
				runtimeUses += argument.callbackArgument.runtimeUses.length;
			}
	}
	for (boundary in boundaries)
		if (boundary.callbackReturns != null)
			for (returned in boundary.callbackReturns) {
				returns++;
				unsafeOperations += returned.unsafeOperations.length;
				runtimeUses += returned.runtimeUses.length;
			}
	return {
		arguments: arguments,
		returns: returns,
		invocations: invocations,
		unsafeOperations: unsafeOperations,
		runtimeUses: runtimeUses
	};
}

/** Check offline callback evidence against the report's registered program storage. */
function inspect(value:Dynamic, representations:Array<InspectionRepresentationDecision>, pipeline:String, calls:Array<InspectionCall>,
		boundaries:Array<InspectionCallableBoundary>):CallableViewInventoryReport {
	final report = fromReport(value);
	final byId:Map<String, InspectionRepresentationDecision> = [];
	for (representation in representations)
		byId.set(representation.id, representation);
	final used:Map<String, Bool> = [];
	final declarations:Map<String, InspectionCallableBoundary> = [];
	for (boundary in boundaries)
		declarations.set(boundary.calleeId, boundary);
	function requireCarrier(layout:OcamlCallableViewDescriptor, program:String):InspectionRepresentationDecision {
		final selected = byId.get("representation:" + layout.semanticTypeId + ":internal-value");
		if (selected == null
			|| selected.programRevision != program
			|| selected.semanticTypeId != layout.semanticTypeId
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
		return selected;
	}
	function requireStorage(reference:OcamlLocalRepresentationReference, layout:OcamlCallableViewDescriptor, owner:OcamlFunctionPlanBinding):Void {
		final selected = requireCarrier(layout, owner.programRevision);
		if (selected.id != reference.representationId
			|| selected.revision != reference.representationRevision
			|| selected.semanticTypeId != reference.semanticTypeId
			|| selected.domain != reference.domain
			|| !Lambda.exists(report.requiredLocals, local -> encode(local.binding) == encode(owner)
				&& encode(local.reference) == encode(reference)))
			throw "Callback source does not match selected storage in its final function body.";
	}
	function requireInput(input:OcamlCallableViewInput, layout:OcamlCallableViewDescriptor, owner:OcamlFunctionPlanBinding):Void {
		if (owner.pipelineRevision != pipeline)
			throw "Callback source belongs to another target pipeline revision.";
		switch (input) {
			case ExistingView(reference):
				requireStorage(reference, layout, owner);
			case DeclaredOrigin(declaration):
				if (declaration.programRevision != owner.programRevision || declaration.pipelineRevision != owner.pipelineRevision)
					throw "Callback producer belongs to another program or pipeline.";
				ReflaxeOcamlCallableCallInspection.requireDeclaration(declaration, declarations);
			case CallResult(source):
				final matches = calls.filter(call -> encode(binding(call)) == encode(owner)
					&& call.sourceFile == source.file
					&& call.sourceMin == source.min
					&& call.sourceMax == source.max);
				final result = matches.length == 1 ? matches[0].result : null;
				if (result == null || result.callableView == null || layoutFromReport(result.callableView).revision != layout.revision)
					throw "Callback source has no unique matching call result in its final body.";
			case RawOrigin(StaticDeclaration(id)):
				ReflaxeOcamlCallableCallInspection.requireDeclaration({
					calleeId: id,
					layout: layout,
					programRevision: owner.programRevision,
					pipelineRevision: owner.pipelineRevision
				}, declarations);
			case RawOrigin(FreshLiteral):
		}
	}
	requireParameterCoverage(report, boundaries.map(boundary -> {
		id: boundary.id,
		calleeId: boundary.calleeId,
		binding: binding(boundary),
		arguments: boundary.arguments.map(value -> value.callableView == null ? null : layoutFromReport(value.callableView))
	}));
	for (parameter in report.parameters)
		requireStorage(parameter.reference, layoutFromReport(parameter.layout), parameter.binding);
	for (decision in decisions(report)) {
		if (decision.binding.pipelineRevision != pipeline)
			throw "Callback occurrence belongs to another target pipeline revision.";
		requireStorage(decision.output, decision.outputLayout, decision.binding);
		requireInput(decision.input, decision.inputLayout, decision.binding);
	}
	for (comparison in comparisonDecisions(report)) {
		if (comparison.binding.pipelineRevision != pipeline)
			throw "Callback comparison belongs to another target pipeline revision.";
		for (operand in [comparison.left, comparison.right])
			requireInput(operand.input, operand.layout, comparison.binding);
	}
	for (call in calls) {
		if (call.callbackInvocation != null) {
			final invoked = reflaxe.ocaml.reports.OcamlCallableCallReport.calleeFromReport(call.callbackInvocation);
			requireInput(invoked.input, invoked.layout, binding(call));
		}
		for (argument in call.arguments)
			if (argument.callbackArgument != null) {
				final prepared = argumentFromReport(argument.callbackArgument);
				requireInput(prepared.input, prepared.operation.inputLayout, prepared.operation.binding);
				requireCarrier(prepared.operation.outputLayout, call.programRevision);
			}
		if (call.result != null && call.result.callableView != null)
			requireCarrier(layoutFromReport(call.result.callableView), call.programRevision);
	}
	for (boundary in boundaries) {
		if (boundary.result != null && boundary.result.callableView != null)
			requireCarrier(layoutFromReport(boundary.result.callableView), boundary.programRevision);
		if (boundary.callbackReturns != null)
			for (entry in boundary.callbackReturns) {
				final returned = reflaxe.ocaml.reports.OcamlCallableCallReport.returnFromReport(entry);
				switch (returned.input) {
					case LocalView(reference, layout):
						requireInput(ExistingView(reference), layout, returned.binding);
					case _:
				}
			}
	}
	for (representation in representations)
		if (representation.boxingPolicy == "callable-identity-view" && !used.exists(representation.id))
			throw "A registered callback layout has no source-bound occurrence evidence.";
	return report;
}

/** Recompute the helpers from typed conversions and require exact report ownership. */
function validateRuntime(report:CallableViewInventoryReport, requirements:Map<String, Dynamic>, calls:Array<InspectionCall>,
		boundaries:Array<InspectionCallableBoundary>):Array<String> {
	final ids:Array<String> = [];
	final operations = decisions(report).map(reflaxe.ocaml.lowered.OcamlCallableViewContract.operation);
	for (comparison in comparisonDecisions(report)) {
		operations.push(reflaxe.ocaml.lowered.OcamlCallableComparison.operation(comparison, true));
		operations.push(reflaxe.ocaml.lowered.OcamlCallableComparison.operation(comparison, false));
	}
	for (call in calls)
		for (argument in call.arguments)
			if (argument.callbackArgument != null)
				operations.push(argumentFromReport(argument.callbackArgument).operation);
	for (boundary in boundaries)
		if (boundary.callbackReturns != null)
			for (returned in boundary.callbackReturns)
				operations.push(reflaxe.ocaml.lowered.OcamlCallableReturnContract.operation(reflaxe.ocaml.reports.OcamlCallableCallReport.returnFromReport(returned)));
	for (decision in operations) {
		for (expected in reflaxe.ocaml.lowered.OcamlCallableViewRuntime.valueRequirements(decision)) {
			final recorded = requirements.get(expected.id);
			if (recorded == null || encode(recorded) != encode(expected))
				throw 'Callback occurrence "${decision.id}" has missing or changed runtime evidence "${expected.id}".';
			ids.push(expected.id);
		}
	}
	return ids;
}
