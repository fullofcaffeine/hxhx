package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
import haxe.crypto.Sha256;
import reflaxe.ocaml.lowered.OcamlCallableOriginKind;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation.OcamlCallableViewDescriptor;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation.describe;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation.validate;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueConversion;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueShape;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.crossing;
import reflaxe.ocaml.lowered.OcamlLocalConversionModel.OcamlLocalConversionRole;
import reflaxe.ocaml.lowered.OcamlLocalConversionModel.OcamlLocalRepresentationReference;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlLocalConversionIdentity.occurrenceId;

/** A write either preserves an existing view's token or creates the producer's selected identity. */
enum OcamlCallableViewInput {
	ExistingView(reference:OcamlLocalRepresentationReference);
	RawOrigin(kind:OcamlCallableOriginKind);
}

/** One source-bound callback write, including origin construction before signature adaptation. */
typedef OcamlCallableViewLocalDecision = {
	final id:String;
	final revision:String;
	final role:OcamlLocalConversionRole;
	final source:OcamlLoweredSourceSpan;
	final input:OcamlCallableViewInput;
	final output:OcamlLocalRepresentationReference;
	final inputLayout:OcamlCallableViewDescriptor;
	final outputLayout:OcamlCallableViewDescriptor;
	final conversion:OcamlGenericValueConversion;
	final binding:OcamlFunctionPlanBinding;
};

/** Bind an already selected pair of layouts without granting registry or producer authority. */
function sealWithLayouts(binding:OcamlFunctionPlanBinding, role:OcamlLocalConversionRole, source:OcamlLoweredSourceSpan, input:OcamlCallableViewInput,
		inputLayout:OcamlCallableViewDescriptor, output:OcamlLocalRepresentationReference,
		outputLayout:OcamlCallableViewDescriptor):OcamlCallableViewLocalDecision {
	final conversion:OcamlGenericValueConversion = crossing(inputLayout.shape,
		outputLayout.shape) ?? throw "reflaxe.ocaml [ocaml-callable-local:incompatible-views]: callback signatures have no proved conversion";
	final id = occurrenceId(binding, output.localId, role, source);
	final decision:OcamlCallableViewLocalDecision = {
		id: id,
		revision: fingerprint(id, binding, role, source, input, output, inputLayout, outputLayout, conversion),
		role: role,
		source: {file: source.file, min: source.min, max: source.max},
		input: copyInput(input),
		output: copyReference(output),
		inputLayout: inputLayout,
		outputLayout: outputLayout,
		conversion: conversion,
		binding: copyBinding(binding)
	};
	requireDecision(decision);
	return decision;
}

/** Reject changed signatures, adapter direction, source identity, or local references. */
function requireDecision(decision:OcamlCallableViewLocalDecision):Void {
	validate(decision.inputLayout);
	validate(decision.outputLayout);
	switch (decision.input) {
		case ExistingView(reference):
			requireReference(reference, decision.inputLayout);
		case RawOrigin(kind):
			if (!isScalarArrow(decision.inputLayout.shape))
				throw "reflaxe.ocaml [ocaml-callable-local:unproved-producer]: raw callback has an unproved invocation layout";
			switch (kind) {
				case StaticDeclaration(calleeId) if (calleeId.length == 0):
					throw "reflaxe.ocaml [ocaml-callable-local:missing-declaration]: static origin lost its declaration identity";
				case _:
			}
	}
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
		|| decision.id != occurrenceId(binding, decision.output.localId, decision.role, decision.source)
		|| decision.revision != fingerprint(decision.id, binding, decision.role, decision.source, decision.input, decision.output, decision.inputLayout,
			decision.outputLayout, decision.conversion))
		throw "reflaxe.ocaml [ocaml-callable-local:stale-conversion]: callback write no longer matches its sealed source and layouts";
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
		input: copyInput(decision.input),
		output: copyReference(decision.output),
		inputLayout: describe(decision.inputLayout.shape),
		outputLayout: describe(decision.outputLayout.shape),
		conversion: copyConversion(decision.conversion),
		binding: copyBinding(decision.binding)
	};
}

/** Enumerate only real local storage references; a producer is not a synthetic input local. */
function localReferences(decision:OcamlCallableViewLocalDecision):Array<OcamlLocalRepresentationReference> {
	return switch (decision.input) {
		case ExistingView(reference): [copyReference(reference), copyReference(decision.output)];
		case RawOrigin(_): [copyReference(decision.output)];
	};
}

private function copyInput(input:OcamlCallableViewInput):OcamlCallableViewInput {
	return switch (input) {
		case ExistingView(reference): ExistingView(copyReference(reference));
		case RawOrigin(kind): RawOrigin(kind);
	};
}

private function isScalarArrow(shape:OcamlGenericValueShape):Bool {
	function scalar(value:OcamlGenericValueShape):Bool {
		return switch (value) {
			case Integer, Boolean, Text(_), NullableInteger, NullableBoolean, DynamicValue: true;
			case _: false;
		};
	}
	return switch (shape) {
		case FunctionValue(arguments, result): Lambda.foreach(arguments, scalar) && (result == EffectOnly || scalar(result));
		case _: false;
	};
}

private function requireReference(reference:OcamlLocalRepresentationReference, layout:OcamlCallableViewDescriptor):Void {
	// The lexical-local-v1 wire schema is a lowercase SHA-256 identity, never a host TVar number.
	if (!~/^lexical-local-v1:[0-9a-f]{64}$/.match(reference.localId)
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
		input:OcamlCallableViewInput, output:OcamlLocalRepresentationReference, inputLayout:OcamlCallableViewDescriptor,
		outputLayout:OcamlCallableViewDescriptor, conversion:OcamlGenericValueConversion):String {
	return "sha256:" + Sha256.encode([
		"ocaml-callable-local-conversion-v2",
		id,
		binding.functionId,
		binding.programRevision,
		binding.bodyRevision,
		binding.pipelineRevision,
		role,
		source.file,
		Std.string(source.min),
		Std.string(source.max),
		switch (input) {
			case ExistingView(reference):
				"existing-view\n" + referenceKey(reference);
			case RawOrigin(kind):
				"raw-origin\n" + Std.string(kind);
		},
		referenceKey(output),
		inputLayout.revision,
		outputLayout.revision,
		Std.string(conversion)
	].join("\n"));
}
#end
