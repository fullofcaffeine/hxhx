package reflaxe.ocaml.reports;

import reflaxe.ocaml.lowered.OcamlCallableComparison;
import reflaxe.ocaml.lowered.OcamlCallableComparison.OcamlCallableComparisonDecision;
import reflaxe.ocaml.lowered.OcamlCallableComparison.OcamlCallableComparisonOperand;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.reports.OcamlCallableViewReport;
import reflaxe.ocaml.reports.OcamlCallableViewReport.CallableViewInputReport;
import reflaxe.ocaml.reports.OcamlCallableViewReport.CallableViewLayoutReport;
import reflaxe.ocaml.reports.OcamlGenericCallReport;

/** One comparison operand keeps its own source and the producer's validated calling convention. */
typedef CallableComparisonOperandReport = {
	final source:OcamlLoweredSourceSpan;
	final input:CallableViewInputReport;
	final layout:CallableViewLayoutReport;
};

/** Plain report fields preserve ordered operands, source identity, and equality versus inequality. */
typedef CallableComparisonReport = {
	final id:String;
	final revision:String;
	final binding:OcamlFunctionPlanBinding;
	final source:OcamlLoweredSourceSpan;
	final notEqual:Bool;
	final left:CallableComparisonOperandReport;
	final right:CallableComparisonOperandReport;
};

/** Export a detached and validated final-body decision. */
function toReport(decision:OcamlCallableComparisonDecision):CallableComparisonReport {
	final selected = reflaxe.ocaml.lowered.OcamlCallableComparison.copy(decision);
	return {
		id: selected.id,
		revision: selected.revision,
		binding: selected.binding,
		source: selected.source,
		notEqual: selected.notEqual,
		left: operandToReport(selected.left),
		right: operandToReport(selected.right)
	};
}

/** Reject changed operators, operand order, producer evidence and final-body ownership at the JSON boundary. */
function fromReport(value:Dynamic):OcamlCallableComparisonDecision {
	requireFields(value, ["id", "revision", "binding", "source", "notEqual", "left", "right"]);
	final notEqual:Dynamic = Reflect.field(value, "notEqual");
	if (!Std.isOfType(notEqual, Bool))
		throw "Callback comparison requires a Boolean equality operator.";
	final decision:OcamlCallableComparisonDecision = {
		id: text(Reflect.field(value, "id")),
		revision: text(Reflect.field(value, "revision")),
		binding: readBinding(Reflect.field(value, "binding")),
		source: readSource(Reflect.field(value, "source")),
		notEqual: notEqual,
		left: operandFromReport(Reflect.field(value, "left")),
		right: operandFromReport(Reflect.field(value, "right"))
	};
	requireDecision(decision);
	return decision;
}

private function operandToReport(operand:OcamlCallableComparisonOperand):CallableComparisonOperandReport {
	return {source: operand.source, input: inputToReport(operand.input), layout: layoutToReport(operand.layout)};
}

private function operandFromReport(value:Dynamic):OcamlCallableComparisonOperand {
	requireFields(value, ["source", "input", "layout"]);
	final layout = layoutFromReport(Reflect.field(value, "layout"));
	return {source: readSource(Reflect.field(value, "source")), input: inputFromReport(Reflect.field(value, "input"), layout), layout: layout};
}
