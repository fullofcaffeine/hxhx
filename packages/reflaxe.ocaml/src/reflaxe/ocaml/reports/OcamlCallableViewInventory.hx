package reflaxe.ocaml.reports;

import reflaxe.ocaml.lowered.OcamlCallableViewContract;
import reflaxe.ocaml.lowered.OcamlCallableViewContract.OcamlCallableViewLocalDecision;
import reflaxe.ocaml.lowered.OcamlCallableViewEvidence.CallableViewUnsafeOperation;
import reflaxe.ocaml.lowered.OcamlLocalConversionModel.OcamlLocalRepresentationReference;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;
import reflaxe.ocaml.reports.OcamlCallableViewReport;
import reflaxe.ocaml.reports.OcamlCallableViewReport.CallableViewLocalReport;
import reflaxe.ocaml.reports.OcamlCallableViewReport.CallableViewLayoutReport;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation.OcamlCallableViewDescriptor;
import reflaxe.ocaml.reports.OcamlGenericCallReport;
import reflaxe.ocaml.reports.OcamlReportJson;
import reflaxe.ocaml.lowered.OcamlCallableComparison.OcamlCallableComparisonDecision;
import reflaxe.ocaml.reports.OcamlCallableComparisonReport.CallableComparisonReport;

/** An independently selected local; its origin must be a declared parameter or an initializer. */
typedef CallableViewRequiredLocal = {
	final binding:OcamlFunctionPlanBinding;
	final reference:OcamlLocalRepresentationReference;
};

/** A real function parameter receives its view from one exact declared argument slot. */
typedef CallableViewParameterReport = {
	final binding:OcamlFunctionPlanBinding;
	final reference:OcamlLocalRepresentationReference;
	final boundaryId:String;
	final calleeId:String;
	final index:Int;
	final layout:CallableViewLayoutReport;
};

/** A projection of an independently validated callable definition, never an invented parameter list. */
typedef CallableViewParameterOwner = {
	final id:String;
	final calleeId:String;
	final binding:OcamlFunctionPlanBinding;
	final arguments:Array<Null<OcamlCallableViewDescriptor>>;
};

/** Every callback write publishes the exact low-level operations selected by its typed plan. */
typedef CallableViewReportEntry = {
	final decision:CallableViewLocalReport;
	final unsafeOperations:Array<CallableViewUnsafeOperation>;
	final runtimeUses:Array<OcamlRuntimeUseOccurrence>;
};

/** Equality records include the native operations of both ordered operands. */
typedef CallableComparisonReportEntry = {
	final decision:CallableComparisonReport;
	final unsafeOperations:Array<CallableViewUnsafeOperation>;
	final runtimeUses:Array<OcamlRuntimeUseOccurrence>;
};

/** Deterministic inventory; an omitted conversion cannot disappear with its evidence unnoticed. */
typedef CallableViewInventoryReport = {
	final model:String;
	final revision:String;
	final requiredLocals:Array<CallableViewRequiredLocal>;
	final parameters:Array<CallableViewParameterReport>;
	final entries:Array<CallableViewReportEntry>;
	final comparisons:Array<CallableComparisonReportEntry>;
};

final MODEL = "typed-ocaml-callback-local-views-v3";

/** Build from independently retained local selections and source-bound conversion decisions. */
function build(required:Array<CallableViewRequiredLocal>, decisions:Array<OcamlCallableViewLocalDecision>, ?parameters:Array<CallableViewParameterReport>,
		?comparisons:Array<OcamlCallableComparisonDecision>):CallableViewInventoryReport {
	final locals:Array<CallableViewRequiredLocal> = required.map(local -> {binding: readBinding(local.binding), reference: readReference(local.reference)});
	locals.sort((a, b) -> Reflect.compare(localKey(a), localKey(b)));
	final selectedParameters = (parameters ?? []).map(parameter -> readParameter(parameter));
	selectedParameters.sort((a, b) -> Reflect.compare(parameterKey(a), parameterKey(b)));
	final entries:Array<CallableViewReportEntry> = decisions.map(decision -> {
		decision: localToReport(decision),
		unsafeOperations: reflaxe.ocaml.lowered.OcamlCallableViewEvidence.unsafeOperations(decision),
		runtimeUses: reflaxe.ocaml.lowered.OcamlCallableViewRuntime.occurrences(decision)
	});
	entries.sort((a, b) -> Reflect.compare(a.decision.id, b.decision.id));
	final compared:Array<CallableComparisonReportEntry> = (comparisons ?? []).map(comparison -> {
		final left = reflaxe.ocaml.lowered.OcamlCallableComparison.operation(comparison, true);
		final right = reflaxe.ocaml.lowered.OcamlCallableComparison.operation(comparison, false);
		return {
			decision: OcamlCallableComparisonReport.toReport(comparison),
			unsafeOperations: reflaxe.ocaml.lowered.OcamlCallableViewEvidence.valueUnsafeOperations(left)
				.concat(reflaxe.ocaml.lowered.OcamlCallableViewEvidence.valueUnsafeOperations(right)),
			runtimeUses: reflaxe.ocaml.lowered.OcamlCallableViewRuntime.valueOccurrences(left)
				.concat(reflaxe.ocaml.lowered.OcamlCallableViewRuntime.valueOccurrences(right))};
	});
	compared.sort((a, b) -> Reflect.compare(a.decision.id, b.decision.id));
	final report:CallableViewInventoryReport = {
		model: MODEL,
		revision: digest({
			requiredLocals: locals,
			parameters: selectedParameters,
			entries: entries,
			comparisons: compared
		}),
		requiredLocals: locals,
		parameters: selectedParameters,
		entries: entries,
		comparisons: compared
	};
	validateCoverage(locals, decisions, selectedParameters, comparisons ?? []);
	return report;
}

/** Decode once, rebuild canonical evidence, and reject missing or altered facts. */
function fromReport(value:Dynamic):CallableViewInventoryReport {
	requireFields(value, ["model", "revision", "requiredLocals", "parameters", "entries", "comparisons"]);
	if (text(Reflect.field(value, "model")) != MODEL)
		throw "Unsupported callback inventory model.";
	final locals:Array<CallableViewRequiredLocal> = [
		for (local in sequence(Reflect.field(value, "requiredLocals"))) {
			requireFields(local, ["binding", "reference"]);
			{binding: readBinding(Reflect.field(local, "binding")), reference: readReference(Reflect.field(local, "reference"))};
		}
	];
	final decisions = [
		for (entry in sequence(Reflect.field(value, "entries"))) {
			requireFields(entry, ["decision", "unsafeOperations", "runtimeUses"]);
			localFromReport(Reflect.field(entry, "decision"));
		}
	];
	final parameters = sequence(Reflect.field(value, "parameters")).map(readParameter);
	final comparisons = [
		for (entry in sequence(Reflect.field(value, "comparisons"))) {
			requireFields(entry, ["decision", "unsafeOperations", "runtimeUses"]);
			OcamlCallableComparisonReport.fromReport(Reflect.field(entry, "decision"));
		}
	];
	final expected = build(locals, decisions, parameters, comparisons);
	if (encode(value) != encode(expected))
		throw "Callback inventory differs from its selected decisions, runtime uses, or unsafe-operation evidence.";
	return expected;
}

/** Share one typed occurrence decoder with the inspector and runtime requirement checks. */
function decisions(report:CallableViewInventoryReport):Array<OcamlCallableViewLocalDecision> {
	return report.entries.map(entry -> localFromReport(entry.decision));
}

/** Decode detached comparisons for independent storage, call and runtime joins. */
function comparisonDecisions(report:CallableViewInventoryReport):Array<OcamlCallableComparisonDecision> {
	return report.comparisons.map(entry -> OcamlCallableComparisonReport.fromReport(entry.decision));
}

/** Require every declared callback slot exactly once, with its own body and representation. */
function requireParameterCoverage(report:CallableViewInventoryReport, owners:Array<CallableViewParameterOwner>):Void {
	final byId:Map<String, CallableViewParameterOwner> = [];
	for (owner in owners) {
		if (byId.exists(owner.id))
			throw "Callback parameter inventory received duplicate callable owners.";
		byId.set(owner.id, owner);
	}
	final seen:Map<String, Bool> = [];
	for (parameter in report.parameters) {
		final owner = byId.get(parameter.boundaryId);
		if (owner == null
			|| owner.calleeId != parameter.calleeId
			|| encode(owner.binding) != encode(parameter.binding)
			|| parameter.index >= owner.arguments.length)
			throw "Callback parameter does not match its declared callable owner.";
		final layout = owner.arguments[parameter.index];
		if (layout == null || encode(layoutToReport(layout)) != encode(parameter.layout))
			throw "Callback parameter does not match its declared argument layout.";
		final slot = parameterKey(parameter);
		if (seen.exists(slot))
			throw "Callback parameter inventory contains a duplicate declared argument.";
		seen.set(slot, true);
	}
	for (owner in owners)
		for (index in 0...owner.arguments.length)
			if (owner.arguments[index] != null && !seen.exists(encode({binding: owner.binding, boundaryId: owner.id, index: index})))
				throw "Declared callback argument is missing its selected parameter storage.";
}

private function localKey(local:CallableViewRequiredLocal):String {
	return encode({binding: local.binding, localId: local.reference.localId});
}

private function parameterKey(parameter:CallableViewParameterReport):String {
	return encode({binding: parameter.binding, boundaryId: parameter.boundaryId, index: parameter.index});
}

/** Validate the JSON boundary immediately; the owning report also joins the named callable slot. */
private function readParameter(value:Dynamic):CallableViewParameterReport {
	requireFields(value, ["binding", "reference", "boundaryId", "calleeId", "index", "layout"]);
	final index:Dynamic = Reflect.field(value, "index");
	if (!Std.isOfType(index, Int) || index < 0)
		throw "Callback parameter requires a nonnegative argument index.";
	final parameter:CallableViewParameterReport = {
		binding: readBinding(Reflect.field(value, "binding")),
		reference: readReference(Reflect.field(value, "reference")),
		boundaryId: text(Reflect.field(value, "boundaryId")),
		calleeId: text(Reflect.field(value, "calleeId")),
		index: index,
		layout: layoutToReport(layoutFromReport(Reflect.field(value, "layout")))
	};
	if (parameter.boundaryId.length == 0
		|| parameter.calleeId.length == 0
		|| parameter.binding.functionId.length == 0
		|| parameter.binding.programRevision.length == 0
		|| parameter.binding.bodyRevision.length == 0
		|| parameter.binding.pipelineRevision.length == 0
		|| parameter.reference.domain != InternalValue)
		throw "Callback parameter lost its declared owner or immutable storage.";
	requireReference(parameter.reference, layoutFromReport(parameter.layout));
	return parameter;
}

private function validateCoverage(locals:Array<CallableViewRequiredLocal>, conversions:Array<OcamlCallableViewLocalDecision>,
		parameters:Array<CallableViewParameterReport>, comparisons:Array<OcamlCallableComparisonDecision>):Void {
	final required:Map<String, CallableViewRequiredLocal> = [];
	for (local in locals) {
		final key = localKey(local);
		if (required.exists(key))
			throw "Callback inventory contains a duplicate selected local.";
		required.set(key, local);
	}
	final seen:Map<String, Bool> = [];
	final slots:Map<String, Bool> = [];
	for (parameter in parameters) {
		final key = localKey({binding: parameter.binding, reference: parameter.reference});
		final local = required.get(key);
		final slot = parameterKey(parameter);
		if (local == null || seen.exists(key) || slots.exists(slot) || encode(local.reference) != encode(parameter.reference))
			throw "Callback parameter does not have exactly one matching selected local and declared slot.";
		seen.set(key, true);
		slots.set(slot, true);
	}
	for (conversion in conversions) {
		requireDecision(conversion);
		final key = localKey({binding: conversion.binding, reference: conversion.output});
		final local = required.get(key);
		if (local == null
			|| seen.exists(key)
			|| conversion.role != Initializer
			|| encode(local.reference) != encode(conversion.output))
			throw "Callback initializer does not have exactly one matching selected local.";
		seen.set(key, true);
		for (reference in localReferences(conversion)) {
			final selected = required.get(localKey({binding: conversion.binding, reference: reference}));
			if (selected == null || encode(selected.reference) != encode(reference))
				throw "Callback conversion refers to storage outside the selected local inventory.";
		}
	}
	if (Lambda.count(seen) != locals.length)
		throw "A selected callback local is missing its initializer conversion or declared parameter.";
	final comparisonIds:Map<String, Bool> = [];
	for (comparison in comparisons) {
		reflaxe.ocaml.lowered.OcamlCallableComparison.requireDecision(comparison);
		if (comparisonIds.exists(comparison.id))
			throw "Callback inventory contains a duplicate comparison occurrence.";
		comparisonIds.set(comparison.id, true);
		for (operand in [comparison.left, comparison.right]) {
			switch (operand.input) {
				case ExistingView(reference):
					final selected = required.get(localKey({binding: comparison.binding, reference: reference}));
					if (selected == null || encode(selected.reference) != encode(reference))
						throw "Callback comparison refers to storage outside the selected local inventory.";
				case _:
			}
		}
	}
}
