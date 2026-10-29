package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
import haxe.crypto.Sha256;
import reflaxe.ocaml.lowered.OcamlCallableOriginKind;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation.OcamlCallableViewDescriptor;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation.describe;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation.validate;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.crossing;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlCallableValueOperation;
import reflaxe.ocaml.lowered.OcamlLocalConversionModel.OcamlLocalRepresentationReference;

/**
	The exact recursive invocation layout of a selected declaration.

	The declaration catalog must resolve this reference before syntax consumes it.
	The matching final body must also export this layout. A descriptor alone does
	not prove that an arbitrary raw function already accepts or returns views.
**/
typedef OcamlCallableInvocationReference = {
	final calleeId:String;
	final layout:OcamlCallableViewDescriptor;
	final programRevision:String;
	final pipelineRevision:String;
};

/** The containing method must bind its declaration to this exact final function body. */
typedef OcamlCallableReturnBoundary = {
	> OcamlCallableInvocationReference,
	final functionId:String;
	final bodyRevision:String;
};

/** The source of a returned callback, without a synthetic local storage identity. */
enum OcamlCallableReturnInput {
	Producer(kind:OcamlCallableOriginKind, layout:OcamlCallableViewDescriptor);
	Parameter(index:Int);
	LocalView(reference:OcamlLocalRepresentationReference, layout:OcamlCallableViewDescriptor);
	CallResult(callId:String, boundary:OcamlCallableInvocationReference);
}

/** Inputs selected from one final typed return expression and its containing declaration. */
typedef OcamlCallableReturnSelection = {
	final binding:OcamlFunctionPlanBinding;
	final boundary:OcamlCallableReturnBoundary;
	final ordinal:Int;
	final source:OcamlLoweredSourceSpan;
	final input:OcamlCallableReturnInput;
};

/** An immutable return selection whose fingerprint binds its occurrence, producer and declaration. */
typedef OcamlCallableReturnDecision = {
	> OcamlCallableReturnSelection,
	final id:String;
	final revision:String;
};

/** Seal selected facts; callers still own final typed-source and declaration-catalog validation. */
function seal(selection:OcamlCallableReturnSelection):OcamlCallableReturnDecision {
	final detached = copySelection(selection);
	final id = occurrenceId(detached);
	final decision:OcamlCallableReturnDecision = {
		binding: detached.binding,
		boundary: detached.boundary,
		ordinal: detached.ordinal,
		source: detached.source,
		input: detached.input,
		id: id,
		revision: fingerprint(id, detached)
	};
	requireDecision(decision);
	return decision;
}

/** Preserve the sealed revision while detaching mutable arrays from registry clients. */
function copy(decision:OcamlCallableReturnDecision):OcamlCallableReturnDecision {
	requireDecision(decision);
	return seal(decision);
}

/** Reject stale bodies, source occurrences, parameter slots, result layouts and producer changes. */
function requireDecision(decision:OcamlCallableReturnDecision):Void {
	if (decision.ordinal < 0 || decision.id != occurrenceId(decision) || decision.revision != fingerprint(decision.id, decision))
		throw "reflaxe.ocaml [ocaml-callable-return:stale-decision]: callback return no longer matches its sealed occurrence";
	requireOperation(uncheckedOperation(decision));
}

/** Syntax cannot use a valid return decision from another final function body. */
function requireBinding(decision:OcamlCallableReturnDecision, binding:OcamlFunctionPlanBinding):Void {
	requireDecision(decision);
	if (decision.binding.functionId != binding.functionId
		|| decision.binding.programRevision != binding.programRevision
		|| decision.binding.bodyRevision != binding.bodyRevision
		|| decision.binding.pipelineRevision != binding.pipelineRevision)
		throw "reflaxe.ocaml [ocaml-callable-return:foreign-binding]: callback return belongs to another sealed function";
}

/** Share the existing native adapter without treating a return as a local assignment. */
function operation(decision:OcamlCallableReturnDecision):OcamlCallableValueOperation {
	requireDecision(decision);
	return uncheckedOperation(copySelection(decision), decision.id);
}

private function requireBoundary(boundary:OcamlCallableInvocationReference, binding:OcamlFunctionPlanBinding):Void {
	validate(boundary.layout);
	if (boundary.calleeId.length == 0
		|| boundary.programRevision != binding.programRevision
		|| boundary.pipelineRevision != binding.pipelineRevision)
		throw "reflaxe.ocaml [ocaml-callable-return:foreign-boundary]: callback declaration belongs to another program or pipeline";
}

private function resultLayout(boundary:OcamlCallableInvocationReference):OcamlCallableViewDescriptor {
	return switch (boundary.layout.shape) {
		case FunctionValue(_, result): describe(result);
		case _: throw "reflaxe.ocaml [ocaml-callable-return:missing-result]: callback declaration has no function result";
	};
}

private function uncheckedOperation(selection:OcamlCallableReturnSelection, ?id:String):OcamlCallableValueOperation {
	requireBoundary(selection.boundary, selection.binding);
	if (selection.boundary.functionId != selection.binding.functionId || selection.boundary.bodyRevision != selection.binding.bodyRevision)
		throw "reflaxe.ocaml [ocaml-callable-return:foreign-definition]: returned value does not belong to this final declaration body";
	final output = resultLayout(selection.boundary);
	var origin:Null<OcamlCallableOriginKind> = null;
	final input = switch (selection.input) {
		case Producer(kind, layout):
			origin = kind;
			validate(layout);
			layout;
		case Parameter(index):
			switch (selection.boundary.layout.shape) {
				case FunctionValue(arguments, _) if (index >= 0 && index < arguments.length): describe(arguments[index]);
				case _: throw "reflaxe.ocaml [ocaml-callable-return:missing-parameter]: returned callback has no matching parameter slot";
			}
		case LocalView(reference, layout):
			validate(layout);
			OcamlCallableViewContract.requireReference(reference, layout);
			layout;
		case CallResult(callId, boundary):
			if (callId.length == 0)
				throw "reflaxe.ocaml [ocaml-callable-return:missing-call]: returned callback has no selected call occurrence";
			requireBoundary(boundary, selection.binding);
			resultLayout(boundary);
	};
	final conversion = crossing(input.shape,
		output.shape) ?? throw "reflaxe.ocaml [ocaml-callable-return:incompatible-result]: returned callback has no proved conversion to the declared result";
	return {
		id: id ?? occurrenceId(selection),
		role: ReturnValue,
		source: selection.source,
		binding: selection.binding,
		origin: origin,
		inputLayout: input,
		outputLayout: output,
		conversion: conversion
	};
}

private function copyBoundary(boundary:OcamlCallableInvocationReference):OcamlCallableInvocationReference {
	validate(boundary.layout);
	return {
		calleeId: boundary.calleeId,
		layout: describe(boundary.layout.shape),
		programRevision: boundary.programRevision,
		pipelineRevision: boundary.pipelineRevision
	};
}

private function copySelection(selection:OcamlCallableReturnSelection):OcamlCallableReturnSelection {
	validate(selection.boundary.layout);
	return {
		binding: {
			functionId: selection.binding.functionId,
			programRevision: selection.binding.programRevision,
			bodyRevision: selection.binding.bodyRevision,
			pipelineRevision: selection.binding.pipelineRevision
		},
		boundary: {
			calleeId: selection.boundary.calleeId,
			layout: describe(selection.boundary.layout.shape),
			programRevision: selection.boundary.programRevision,
			pipelineRevision: selection.boundary.pipelineRevision,
			functionId: selection.boundary.functionId,
			bodyRevision: selection.boundary.bodyRevision
		},
		ordinal: selection.ordinal,
		source: {file: selection.source.file, min: selection.source.min, max: selection.source.max},
		input: switch (selection.input) {
			case Producer(kind, layout):
				validate(layout);
				Producer(kind, describe(layout.shape));
			case Parameter(index): Parameter(index);
			case LocalView(reference, layout):
				validate(layout);
				LocalView({
					localId: reference.localId,
					representationId: reference.representationId,
					representationRevision: reference.representationRevision,
					semanticTypeId: reference.semanticTypeId,
					domain: reference.domain
				}, describe(layout.shape));
			case CallResult(id, boundary): CallResult(id, copyBoundary(boundary));
		}
	};
}

private function occurrenceId(selection:OcamlCallableReturnSelection):String {
	return "callable-return:" + Sha256.encode([selection.binding.functionId, Std.string(selection.ordinal)].join("\n"));
}

private function boundaryKey(boundary:OcamlCallableInvocationReference):String {
	validate(boundary.layout);
	return [
		boundary.calleeId,
		boundary.layout.revision,
		boundary.programRevision,
		boundary.pipelineRevision
	].join("\n");
}

private function fingerprint(id:String, selection:OcamlCallableReturnSelection):String {
	return "sha256:" + Sha256.encode([
		"ocaml-callable-return-v2",
		id,
		selection.binding.functionId,
		selection.binding.programRevision,
		selection.binding.bodyRevision,
		selection.binding.pipelineRevision,
		boundaryKey(selection.boundary),
		selection.boundary.functionId,
		selection.boundary.bodyRevision,
		Std.string(selection.ordinal),
		selection.source.file,
		Std.string(selection.source.min),
		Std.string(selection.source.max),
		switch (selection.input) {
			case Producer(kind, layout):
				validate(layout);
				"producer\n" + Std.string(kind) + "\n" + layout.revision;
			case Parameter(index):
				"parameter\n" + index;
			case LocalView(reference, layout):
				validate(layout);
				"local-view\n"
				+ OcamlCallableViewContract.inputKey(ExistingView(reference))
				+ "\n"
				+ layout.revision;
			case CallResult(callId, boundary):
				"call-result\n" + callId + "\n" + boundaryKey(boundary);
		}
	].join("\n"));
}
#end
