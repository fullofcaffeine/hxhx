package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation.OcamlCallableViewDescriptor;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation.describe;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation.validate;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueConversion;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.crossing;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalConversionRole;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalRepresentationReference;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;

/**
	One exact local write between two already-selected callback views.

	This record does not wrap raw functions or prove that a producer is non-null.
	The enclosing function plan must first select view storage for both locals.
	The record then fixes the directional adapter for one initializer or assignment.
**/
typedef OcamlCallableViewLocalDecision = {
	final id:String;
	final revision:String;
	final role:OcamlLocalConversionRole;
	final source:OcamlLoweredSourceSpan;
	final input:OcamlLocalRepresentationReference;
	final output:OcamlLocalRepresentationReference;
	final inputLayout:OcamlCallableViewDescriptor;
	final outputLayout:OcamlCallableViewDescriptor;
	final conversion:OcamlGenericValueConversion;
	final binding:OcamlFunctionPlanBinding;
};

/**
	Selects an adapter from the program's registered layouts, before syntax starts.

	The caller supplies lexical identities and the exact source occurrence from
	the final typed body. Field, Dynamic, nullable, raw-arrow and foreign storage
	require their own producer and boundary plans and cannot enter through this API.
**/
function seal(registry:OcamlRepresentationRegistry, binding:OcamlFunctionPlanBinding, role:OcamlLocalConversionRole, source:OcamlLoweredSourceSpan,
		input:OcamlLocalRepresentationReference, output:OcamlLocalRepresentationReference):OcamlCallableViewLocalDecision {
	final inputLayout = registry.requireCallableView(input.representationId, input.representationRevision, binding.programRevision);
	final outputLayout = registry.requireCallableView(output.representationId, output.representationRevision, binding.programRevision);
	final conversion = crossing(inputLayout.shape, outputLayout.shape);
	if (conversion == null)
		throw "reflaxe.ocaml [ocaml-callable-local:incompatible-views]: callback signatures have no proved conversion";
	final id = OcamlLocalRepresentationPlan.occurrenceId(binding, output.localId, role, source);
	final decision:OcamlCallableViewLocalDecision = {
		id: id,
		revision: fingerprint(id, binding, role, source, input, output, inputLayout, outputLayout, conversion),
		role: role,
		source: {file: source.file, min: source.min, max: source.max},
		input: copyReference(input),
		output: copyReference(output),
		inputLayout: inputLayout,
		outputLayout: outputLayout,
		conversion: conversion,
		binding: copyBinding(binding)
	};
	requireRegistry(decision, registry, binding);
	return decision;
}

/** Reject changed signatures, adapter direction, source identity, or local references. */
function requireDecision(decision:OcamlCallableViewLocalDecision):Void {
	validate(decision.inputLayout);
	validate(decision.outputLayout);
	requireReference(decision.input, decision.inputLayout);
	requireReference(decision.output, decision.outputLayout);
	final binding = decision.binding;
	if (binding.functionId.length == 0
		|| binding.programRevision.length == 0
		|| binding.bodyRevision.length == 0
		|| binding.pipelineRevision.length == 0
		|| decision.source.file.length == 0
		|| decision.source.min < 0
		|| decision.source.max < decision.source.min
		|| (decision.role != Initializer && decision.role != Assignment))
		throw "reflaxe.ocaml [ocaml-callable-local:invalid-occurrence]: callback write needs its exact function, local, role and source";
	final expected = crossing(decision.inputLayout.shape, decision.outputLayout.shape);
	if (expected == null
		|| Std.string(expected) != Std.string(decision.conversion)
		|| decision.id != OcamlLocalRepresentationPlan.occurrenceId(binding, decision.output.localId, decision.role, decision.source)
		|| decision.revision != fingerprint(decision.id, binding, decision.role, decision.source, decision.input, decision.output, decision.inputLayout,
			decision.outputLayout, decision.conversion))
		throw "reflaxe.ocaml [ocaml-callable-local:stale-conversion]: callback write no longer matches its sealed source and layouts";
}

/** Revalidate both registry references before a native consumer can use the adapter. */
function requireRegistry(decision:OcamlCallableViewLocalDecision, registry:OcamlRepresentationRegistry, binding:OcamlFunctionPlanBinding):Void {
	requireBinding(decision, binding);
	for (reference in [decision.input, decision.output]) {
		final registered = registry.require(reference.representationId, binding.programRevision);
		final layout = registry.requireCallableView(reference.representationId, reference.representationRevision, binding.programRevision);
		final expected = reference == decision.input ? decision.inputLayout : decision.outputLayout;
		if (registered.semanticTypeId != reference.semanticTypeId
			|| registered.domain != reference.domain
			|| layout.revision != expected.revision)
			throw "reflaxe.ocaml [ocaml-callable-local:foreign-layout]: callback write refers to another registered layout or storage domain";
	}
}

/** A valid conversion from another body or pipeline is still unusable here. */
function requireBinding(decision:OcamlCallableViewLocalDecision, binding:OcamlFunctionPlanBinding):Void {
	requireDecision(decision);
	if (decision.binding.functionId != binding.functionId
		|| decision.binding.programRevision != binding.programRevision
		|| decision.binding.bodyRevision != binding.bodyRevision
		|| decision.binding.pipelineRevision != binding.pipelineRevision)
		throw "reflaxe.ocaml [ocaml-callable-local:foreign-binding]: callback conversion belongs to another sealed function";
}

/** Detach every mutable list before the enclosing local plan retains or returns a decision. */
function copy(decision:OcamlCallableViewLocalDecision):OcamlCallableViewLocalDecision {
	requireDecision(decision);
	return {
		id: decision.id,
		revision: decision.revision,
		role: decision.role,
		source: {file: decision.source.file, min: decision.source.min, max: decision.source.max},
		input: copyReference(decision.input),
		output: copyReference(decision.output),
		inputLayout: describe(decision.inputLayout.shape),
		outputLayout: describe(decision.outputLayout.shape),
		conversion: copyConversion(decision.conversion),
		binding: copyBinding(decision.binding)
	};
}

private function requireReference(reference:OcamlLocalRepresentationReference, layout:OcamlCallableViewDescriptor):Void {
	if (!reflaxe.lifecycle.LexicalLocalIdentityPlan.isReusableId(reference.localId)
		|| reference.representationId.length == 0
		|| !StringTools.startsWith(reference.representationRevision, "sha256:")
		|| reference.semanticTypeId != layout.semanticTypeId)
		throw "reflaxe.ocaml [ocaml-callable-local:invalid-reference]: callback conversion needs an exact lexical and representation identity";
	switch (reference.domain) {
		case InternalValue, MutableLocalStorage, CapturedLocalStorage:
		case _:
			throw "reflaxe.ocaml [ocaml-callable-local:unproved-domain]: callback conversion requires selected local storage";
	}
}

private function copyReference(reference:OcamlLocalRepresentationReference):OcamlLocalRepresentationReference {
	return {
		localId: reference.localId,
		representationId: reference.representationId,
		representationRevision: reference.representationRevision,
		semanticTypeId: reference.semanticTypeId,
		domain: reference.domain
	};
}

private function copyBinding(binding:OcamlFunctionPlanBinding):OcamlFunctionPlanBinding {
	return {
		functionId: binding.functionId,
		programRevision: binding.programRevision,
		bodyRevision: binding.bodyRevision,
		pipelineRevision: binding.pipelineRevision
	};
}

private function copyConversion(conversion:OcamlGenericValueConversion):OcamlGenericValueConversion {
	return switch (conversion) {
		case AdaptFunction(arguments, result): AdaptFunction(arguments.map(copyConversion), copyConversion(result));
		case _: conversion;
	};
}

private function referenceKey(reference:OcamlLocalRepresentationReference):String {
	return [
		reference.localId,
		reference.representationId,
		reference.representationRevision,
		reference.semanticTypeId,
		reference.domain
	].join("\n");
}

private function fingerprint(id:String, binding:OcamlFunctionPlanBinding, role:OcamlLocalConversionRole, source:OcamlLoweredSourceSpan,
		input:OcamlLocalRepresentationReference, output:OcamlLocalRepresentationReference, inputLayout:OcamlCallableViewDescriptor,
		outputLayout:OcamlCallableViewDescriptor, conversion:OcamlGenericValueConversion):String {
	return "sha256:" + Sha256.encode([
		"ocaml-callable-local-conversion-v1",
		id,
		binding.functionId,
		binding.programRevision,
		binding.bodyRevision,
		binding.pipelineRevision,
		role,
		source.file,
		Std.string(source.min),
		Std.string(source.max),
		referenceKey(input),
		referenceKey(output),
		inputLayout.revision,
		outputLayout.revision,
		Std.string(conversion)
	].join("\n"));
}
#end
