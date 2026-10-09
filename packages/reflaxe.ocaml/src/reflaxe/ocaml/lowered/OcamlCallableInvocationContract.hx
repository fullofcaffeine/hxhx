package reflaxe.ocaml.lowered;

import reflaxe.ocaml.lowered.OcamlCallableViewContract;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;

/** A computed invocation retains the exact existing view, not merely a compatible function type. */
typedef OcamlCallableInvocationPlan = {
	final source:OcamlLoweredSourceSpan;
	final input:OcamlCallableViewInput;
	final layout:OcamlCallableViewDescriptor;
};

/** Only represented locals and selected call results can expose an already prepared invocation. */
function requireInvocation(value:OcamlCallableInvocationPlan):Void {
	validate(value.layout);
	if (value.source.file.length == 0 || value.source.min < 0 || value.source.max < value.source.min)
		throw "Callback invocation has an invalid source occurrence.";
	switch (value.input) {
		case ExistingView(reference):
			requireReference(reference, value.layout);
		case CallResult(source):
			if (source.file != value.source.file || source.min != value.source.min || source.max != value.source.max)
				throw "Callback invocation lost its exact producing call.";
		case _:
			throw "Callback invocation requires an existing local or call-result view.";
	}
}

/** Detach recursive shapes and references before retaining them in an immutable call plan. */
function copy(value:OcamlCallableInvocationPlan):OcamlCallableInvocationPlan {
	requireInvocation(value);
	return {
		source: {file: value.source.file, min: value.source.min, max: value.source.max},
		input: copyInput(value.input),
		layout: describe(value.layout.shape)
	};
}

/** Bind the callee producer and source to the enclosing call revision. */
function fingerprint(value:OcamlCallableInvocationPlan):String {
	requireInvocation(value);
	return [
		value.source.file,
		Std.string(value.source.min),
		Std.string(value.source.max),
		inputKey(value.input),
		value.layout.revision
	].join("\n");
}

/** Reproduce the computed-callee identity from its source and complete final-body binding. */
function calleeId(value:OcamlCallableInvocationPlan, binding:OcamlFunctionPlanBinding):String {
	requireInvocation(value);
	final form = switch (value.input) {
		case ExistingView(_): "local-function-value";
		case CallResult(_): "call-result";
		case _: throw "Callback invocation has no computed callee identity.";
	};
	return "function-value:" + haxe.crypto.Sha256.encode([
		binding.functionId,
		binding.programRevision,
		binding.bodyRevision,
		binding.pipelineRevision,
		form,
		value.source.file + ":" + value.source.min + ":" + value.source.max,
		value.layout.semanticTypeId
	].join("|")).substr(0, 32);
}
