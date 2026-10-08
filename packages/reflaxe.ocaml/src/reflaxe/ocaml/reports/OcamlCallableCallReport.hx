package reflaxe.ocaml.reports;

import reflaxe.ocaml.lowered.OcamlCallableArgumentPlan;
import reflaxe.ocaml.lowered.OcamlCallableReturnContract;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.reports.OcamlCallableViewReport;
import reflaxe.ocaml.reports.OcamlGenericCallReport;
import reflaxe.ocaml.reports.OcamlReportJson.encode;
import reflaxe.ocaml.lowered.OcamlCallableViewEvidence.CallableViewUnsafeOperation;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;
import reflaxe.ocaml.lowered.OcamlCallableInvocationContract;

/** The computed callee retains the source local or call result that supplied its invocation. */
typedef CallableCalleeReport = {
	final source:OcamlLoweredSourceSpan;
	final input:CallableViewInputReport;
	final layout:CallableViewLayoutReport;
};

/** Keep source evidence alongside the recursive signature in the ordinary call report. */
function calleeToReport(value:OcamlCallableInvocationPlan):CallableCalleeReport {
	final selected = reflaxe.ocaml.lowered.OcamlCallableInvocationContract.copy(value);
	return {source: selected.source, input: inputToReport(selected.input), layout: layoutToReport(selected.layout)};
}

/** A type alone cannot prove that the computed source already carries a callback view. */
function calleeFromReport(value:Dynamic):OcamlCallableInvocationPlan {
	requireFields(value, ["source", "input", "layout"]);
	final layout = layoutFromReport(Reflect.field(value, "layout"));
	final selected:OcamlCallableInvocationPlan = {
		source: readSource(Reflect.field(value, "source")),
		layout: layout,
		input: inputFromReport(Reflect.field(value, "input"), layout)
	};
	requireInvocation(selected);
	return selected;
}

/** A declaration reference still needs a join to the independently reported final callable body. */
typedef CallableInvocationReport = {
	final calleeId:String;
	final layout:CallableViewLayoutReport;
	final programRevision:String;
	final pipelineRevision:String;
};

/** The exact body that owns a callback return, separate from any called producer. */
typedef CallableReturnBoundaryReport = {
	> CallableInvocationReport,
	final functionId:String;
	final bodyRevision:String;
};

/** Explicit return producers prevent a parameter or call result from becoming a fresh identity. */
typedef CallableReturnInputReport = {
	final kind:String;
	final calleeId:Null<String>;
	final parameterIndex:Null<Int>;
	final callId:Null<String>;
	final callBoundary:Null<CallableInvocationReport>;
	final localView:Null<CallableViewInputReport>;
};

/** A return occurrence preserves its source, declared result, producer, and directional conversion. */
typedef CallableReturnReport = {
	final id:String;
	final revision:String;
	final binding:OcamlFunctionPlanBinding;
	final ordinal:Int;
	final source:OcamlLoweredSourceSpan;
	final boundary:CallableReturnBoundaryReport;
	final input:CallableReturnInputReport;
	final adapter:CallableViewAdapterReport;
	final unsafeOperations:Array<CallableViewUnsafeOperation>;
	final runtimeUses:Array<OcamlRuntimeUseOccurrence>;
};

/** Preparation belongs to one call argument; it does not replace the declared parameter carrier. */
typedef CallableArgumentReport = {
	final id:String;
	final binding:OcamlFunctionPlanBinding;
	final source:OcamlLoweredSourceSpan;
	final input:CallableViewInputReport;
	final adapter:CallableViewAdapterReport;
	final unsafeOperations:Array<CallableViewUnsafeOperation>;
	final runtimeUses:Array<OcamlRuntimeUseOccurrence>;
};

/** Export a validated reference without exposing mutable shape arrays. */
function invocationToReport(value:OcamlCallableInvocationReference):CallableInvocationReport {
	if (value.calleeId.length == 0 || value.programRevision.length == 0 || value.pipelineRevision.length == 0)
		throw "Callback declaration reference has an empty identity.";
	return {
		calleeId: value.calleeId,
		layout: layoutToReport(value.layout),
		programRevision: value.programRevision,
		pipelineRevision: value.pipelineRevision
	};
}

/** Dynamic is confined to this JSON boundary; callers receive only validated typed references. */
function invocationFromReport(value:Dynamic):OcamlCallableInvocationReference {
	requireFields(value, ["calleeId", "layout", "programRevision", "pipelineRevision"]);
	return {
		calleeId: text(Reflect.field(value, "calleeId")),
		layout: layoutFromReport(Reflect.field(value, "layout")),
		programRevision: text(Reflect.field(value, "programRevision")),
		pipelineRevision: text(Reflect.field(value, "pipelineRevision"))
	};
}

/** Retain the producer and preparation step before the ordinary call consumes the prepared value. */
function argumentToReport(value:OcamlCallableArgumentPlan):CallableArgumentReport {
	final selected = reflaxe.ocaml.lowered.OcamlCallableArgumentPlan.copy(value);
	final operation = selected.operation;
	return {
		id: operation.id,
		binding: operation.binding,
		source: operation.source,
		input: inputToReport(selected.input),
		adapter: adapterToReport(operation.inputLayout, operation.outputLayout, operation.conversion),
		unsafeOperations: reflaxe.ocaml.lowered.OcamlCallableViewEvidence.valueUnsafeOperations(operation),
		runtimeUses: reflaxe.ocaml.lowered.OcamlCallableViewRuntime.valueOccurrences(operation)
	};
}

/** Decode preparation independently; the enclosing call must then validate the exact argument slot. */
function argumentFromReport(value:Dynamic):OcamlCallableArgumentPlan {
	requireFields(value, ["id", "binding", "source", "input", "adapter", "unsafeOperations", "runtimeUses"]);
	final adapter = adapterFromReport(Reflect.field(value, "adapter"));
	final input = inputFromReport(Reflect.field(value, "input"), adapter.input);
	final selected:OcamlCallableArgumentPlan = {
		input: input,
		operation: {
			id: text(Reflect.field(value, "id")),
			role: ArgumentValue,
			binding: readBinding(Reflect.field(value, "binding")),
			source: readSource(Reflect.field(value, "source")),
			inputLayout: adapter.input,
			outputLayout: adapter.output,
			conversion: adapter.conversion,
			origin: switch (input) {
				case RawOrigin(kind): kind;
				case DeclaredOrigin(declaration): StaticDeclaration(declaration.calleeId);
				case _: null;
			},
			invocation: switch (input) {
				case DeclaredOrigin(declaration): declaration;
				case _: null;
			}
		}
	};
	requireArgument(selected);
	if (encode(argumentToReport(selected)) != encode(value))
		throw "Callback argument report has missing or changed native operation evidence.";
	return selected;
}

/** Export a detached return decision after checking its binding and fingerprint. */
function returnToReport(value:OcamlCallableReturnDecision):CallableReturnReport {
	final selected = reflaxe.ocaml.lowered.OcamlCallableReturnContract.copy(value);
	final boundary = selected.boundary;
	final converted = operation(selected);
	return {
		id: selected.id,
		revision: selected.revision,
		binding: selected.binding,
		ordinal: selected.ordinal,
		source: selected.source,
		boundary: {
			calleeId: boundary.calleeId,
			layout: layoutToReport(boundary.layout),
			programRevision: boundary.programRevision,
			pipelineRevision: boundary.pipelineRevision,
			functionId: boundary.functionId,
			bodyRevision: boundary.bodyRevision
		},
		input: {
			kind: switch (selected.input) {
				case Producer(FreshLiteral, _): "fresh-literal";
				case Producer(StaticDeclaration(_), _): "static-declaration";
				case Parameter(_): "parameter";
				case LocalView(_, _): "local-view";
				case CallResult(_, _): "call-result";
			},
			calleeId: switch (selected.input) {
				case Producer(StaticDeclaration(id), _): id;
				case _: null;
			},
			parameterIndex: switch (selected.input) {
				case Parameter(index): index;
				case _: null;
			},
			callId: switch (selected.input) {
				case CallResult(id, _): id;
				case _: null;
			},
			callBoundary: switch (selected.input) {
				case CallResult(_, declared): invocationToReport(declared);
				case _: null;
			},
			localView: switch (selected.input) {
				case LocalView(reference, _): inputToReport(ExistingView(reference));
				case _: null;
			}
		},
		adapter: adapterToReport(converted.inputLayout, converted.outputLayout, converted.conversion),
		unsafeOperations: reflaxe.ocaml.lowered.OcamlCallableViewEvidence.valueUnsafeOperations(converted),
		runtimeUses: reflaxe.ocaml.lowered.OcamlCallableViewRuntime.valueOccurrences(converted)
	};
}

/** Reject stale fingerprints and contradictory tagged fields before joining the containing declaration. */
function returnFromReport(value:Dynamic):OcamlCallableReturnDecision {
	requireFields(value, [
		"id",
		"revision",
		"binding",
		"ordinal",
		"source",
		"boundary",
		"input",
		"adapter",
		"unsafeOperations",
		"runtimeUses"
	]);
	final adapter = adapterFromReport(Reflect.field(value, "adapter"));
	final boundary:Dynamic = Reflect.field(value, "boundary");
	requireFields(boundary, [
		"calleeId",
		"layout",
		"programRevision",
		"pipelineRevision",
		"functionId",
		"bodyRevision"
	]);
	final input:Dynamic = Reflect.field(value, "input");
	requireFields(input, ["kind", "calleeId", "parameterIndex", "callId", "callBoundary", "localView"]);
	final selected:OcamlCallableReturnDecision = {
		id: text(Reflect.field(value, "id")),
		revision: text(Reflect.field(value, "revision")),
		binding: readBinding(Reflect.field(value, "binding")),
		source: readSource(Reflect.field(value, "source")),
		ordinal: integer(Reflect.field(value, "ordinal")),
		boundary: {
			calleeId: text(Reflect.field(boundary, "calleeId")),
			layout: layoutFromReport(Reflect.field(boundary, "layout")),
			programRevision: text(Reflect.field(boundary, "programRevision")),
			pipelineRevision: text(Reflect.field(boundary, "pipelineRevision")),
			functionId: text(Reflect.field(boundary, "functionId")),
			bodyRevision: text(Reflect.field(boundary, "bodyRevision"))
		},
		input: switch (text(Reflect.field(input, "kind"))) {
			case "fresh-literal": Producer(FreshLiteral, adapter.input);
			case "static-declaration": Producer(StaticDeclaration(text(Reflect.field(input, "calleeId"))), adapter.input);
			case "parameter": Parameter(integer(Reflect.field(input, "parameterIndex")));
			case "local-view":
				switch (inputFromReport(Reflect.field(input, "localView"), adapter.input)) {
					case ExistingView(reference): LocalView(reference, adapter.input);
					case _: throw "Returned local callback requires lexical storage evidence.";
				}
			case "call-result": CallResult(text(Reflect.field(input, "callId")), invocationFromReport(Reflect.field(input, "callBoundary")));
			case _: throw "Callback return report has an unsupported producer.";
		}
	};
	requireDecision(selected);
	// Reprojection also rejects unused tagged fields and an adapter that is valid
	// in isolation but differs from this return's actual parameter or result.
	if (encode(returnToReport(selected)) != encode(value))
		throw "Callback return report disagrees with its selected producer or conversion.";
	return selected;
}

private function integer(value:Dynamic):Int {
	if (!Std.isOfType(value, Int))
		throw "Callback call report requires an integer occurrence index.";
	return value;
}
