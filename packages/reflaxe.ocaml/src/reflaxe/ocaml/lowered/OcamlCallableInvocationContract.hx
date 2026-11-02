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

/**
	Reproduce the computed-callee identity from its source and complete final-body binding.

	A local callee also contributes its stable lexical local identity. Haxe can
	copy one source block into a function body more than once. For example, the
	pattern matcher emits a `switch` case body once for each decision path that
	reaches it, and it gives the locals declared in each copy fresh variables:

	```haxe
	switch e {
		case Pair(op, This, value) if (allowThis): op;
		case Pair(op, left, right):
			function wrap(text:String):String return "(" + text + ")";
			wrap(op); // emitted twice, once per copy of `wrap`
	}
	```

	Both copies of `wrap(op)` have the same source span, but each calls its own
	local. Without the local identity, the two invocations would share one call
	identity and the plan would reject them as conflicting.
**/
function calleeId(value:OcamlCallableInvocationPlan, binding:OcamlFunctionPlanBinding):String {
	requireInvocation(value);
	final form = switch (value.input) {
		case ExistingView(reference): "local-function-value\n" + reference.localId;
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

#if (macro || reflaxe_runtime || eval)
/**
	Whether one fresh typed callee is the exact producer this invocation selected.

	`stableLocalId` maps a Haxe host local to its stable lexical identity in the
	current function body. It is required to tell two copies of one source call
	apart (see `calleeId`); without it, only the callee form is checked.
**/
function matchesCallee(value:OcamlCallableInvocationPlan, callee:haxe.macro.Type.TypedExpr, ?stableLocalId:(hostLocalId:Int) -> Null<String>):Bool {
	final actual = OcamlLoweredOrigin.sourceSpan(callee.pos);
	if (actual.file != value.source.file || actual.min != value.source.min || actual.max != value.source.max)
		return false;
	return switch [value.input, callee.expr] {
		case [ExistingView(reference), TLocal(local)]: stableLocalId == null || stableLocalId(local.id) == reference.localId;
		case [CallResult(_), TCall(_, _)]: true;
		case _: false;
	};
}
#end
