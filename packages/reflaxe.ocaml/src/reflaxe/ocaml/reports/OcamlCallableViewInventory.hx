package reflaxe.ocaml.reports;

import reflaxe.ocaml.lowered.OcamlCallableViewContract;
import reflaxe.ocaml.lowered.OcamlCallableViewContract.OcamlCallableViewLocalDecision;
import reflaxe.ocaml.lowered.OcamlCallableViewEvidence.CallableViewUnsafeOperation;
import reflaxe.ocaml.lowered.OcamlLocalConversionModel.OcamlLocalRepresentationReference;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;
import reflaxe.ocaml.reports.OcamlCallableViewReport;
import reflaxe.ocaml.reports.OcamlCallableViewReport.CallableViewLocalReport;
import reflaxe.ocaml.reports.OcamlGenericCallReport;
import reflaxe.ocaml.reports.OcamlReportJson;

/** An independently selected local; its presence requires a corresponding initializer report. */
typedef CallableViewRequiredLocal = {
	final binding:OcamlFunctionPlanBinding;
	final reference:OcamlLocalRepresentationReference;
};

/** Every callback write publishes the exact low-level operations selected by its typed plan. */
typedef CallableViewReportEntry = {
	final decision:CallableViewLocalReport;
	final unsafeOperations:Array<CallableViewUnsafeOperation>;
	final runtimeUses:Array<OcamlRuntimeUseOccurrence>;
};

/** Deterministic inventory; an omitted conversion cannot disappear with its evidence unnoticed. */
typedef CallableViewInventoryReport = {
	final model:String;
	final revision:String;
	final requiredLocals:Array<CallableViewRequiredLocal>;
	final entries:Array<CallableViewReportEntry>;
};

final MODEL = "typed-ocaml-callback-local-views-v1";

/** Build from independently retained local selections and source-bound conversion decisions. */
function build(required:Array<CallableViewRequiredLocal>, decisions:Array<OcamlCallableViewLocalDecision>):CallableViewInventoryReport {
	final locals:Array<CallableViewRequiredLocal> = required.map(local -> {binding: readBinding(local.binding), reference: readReference(local.reference)});
	locals.sort((a, b) -> Reflect.compare(localKey(a), localKey(b)));
	final entries:Array<CallableViewReportEntry> = decisions.map(decision -> {
		decision: localToReport(decision),
		unsafeOperations: reflaxe.ocaml.lowered.OcamlCallableViewEvidence.unsafeOperations(decision),
		runtimeUses: reflaxe.ocaml.lowered.OcamlCallableViewRuntime.occurrences(decision)
	});
	entries.sort((a, b) -> Reflect.compare(a.decision.id, b.decision.id));
	final report:CallableViewInventoryReport = {
		model: MODEL,
		revision: digest({requiredLocals: locals, entries: entries}),
		requiredLocals: locals,
		entries: entries
	};
	validateCoverage(locals, decisions);
	return report;
}

/** Decode once, rebuild canonical evidence, and reject missing or altered facts. */
function fromReport(value:Dynamic):CallableViewInventoryReport {
	requireFields(value, ["model", "revision", "requiredLocals", "entries"]);
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
	final expected = build(locals, decisions);
	if (encode(value) != encode(expected))
		throw "Callback inventory differs from its selected decisions, runtime uses, or unsafe-operation evidence.";
	return expected;
}

/** Share one typed occurrence decoder with the inspector and runtime requirement checks. */
function decisions(report:CallableViewInventoryReport):Array<OcamlCallableViewLocalDecision> {
	return report.entries.map(entry -> localFromReport(entry.decision));
}

private function localKey(local:CallableViewRequiredLocal):String {
	return encode({binding: local.binding, localId: local.reference.localId});
}

private function validateCoverage(locals:Array<CallableViewRequiredLocal>, conversions:Array<OcamlCallableViewLocalDecision>):Void {
	final required:Map<String, CallableViewRequiredLocal> = [];
	for (local in locals) {
		final key = localKey(local);
		if (required.exists(key))
			throw "Callback inventory contains a duplicate selected local.";
		required.set(key, local);
	}
	final seen:Map<String, Bool> = [];
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
		throw "A selected callback local is missing its initializer conversion.";
}
