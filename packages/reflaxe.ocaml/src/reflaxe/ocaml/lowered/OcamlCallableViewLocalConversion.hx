package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type.TypedExpr;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation.OcamlCallableViewDescriptor;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation.describe;
import reflaxe.ocaml.lowered.OcamlLocalConversionModel.OcamlLocalConversionRole;
import reflaxe.ocaml.lowered.OcamlLocalConversionModel.OcamlLocalRepresentationReference;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlCallableViewContract;

/**
	Selects an adapter from the program's registered layouts, before syntax starts.

	The caller supplies lexical identities and the exact source occurrence from
	the final typed body. Field, Dynamic, nullable, raw-arrow and foreign storage
	require their own producer and boundary plans and cannot enter through this API.
**/
function seal(registry:OcamlRepresentationRegistry, binding:OcamlFunctionPlanBinding, role:OcamlLocalConversionRole, source:OcamlLoweredSourceSpan,
		input:OcamlLocalRepresentationReference, output:OcamlLocalRepresentationReference):OcamlCallableViewLocalDecision {
	final inputLayout = registry.requireCallableView(input.representationId, input.representationRevision, binding.programRevision);
	return sealInput(registry, binding, role, source, ExistingView(input), inputLayout, output);
}

/**
	Binds an actual typed producer to the local that will store its view.

	Only scalar argument/result arrows can enter directly. A higher-order native
	arrow does not already carry nested views and needs a separate declaration or
	literal invocation plan. Reject it here rather than falsely borrowing the
	recursive layout descriptor as proof of that calling convention.
**/
function sealProducer(registry:OcamlRepresentationRegistry, binding:OcamlFunctionPlanBinding, role:OcamlLocalConversionRole, expression:TypedExpr,
		output:OcamlLocalRepresentationReference):OcamlCallableViewLocalDecision {
	final kind = reflaxe.ocaml.lowered.OcamlCallableOrigin.classify(expression);
	final shape = reflaxe.ocaml.lowered.OcamlGenericCallConversion.callableShape(expression.t);
	if (kind == null || shape == null)
		throw "reflaxe.ocaml [ocaml-callable-local:unproved-producer]: raw callback needs an exact origin and scalar invocation layout";
	return sealInput(registry, binding, role, OcamlLoweredOrigin.sourceSpan(expression.pos), RawOrigin(kind), describe(shape), output);
}

private function sealInput(registry:OcamlRepresentationRegistry, binding:OcamlFunctionPlanBinding, role:OcamlLocalConversionRole,
		source:OcamlLoweredSourceSpan, input:OcamlCallableViewInput, inputLayout:OcamlCallableViewDescriptor,
		output:OcamlLocalRepresentationReference):OcamlCallableViewLocalDecision {
	final outputLayout = registry.requireCallableView(output.representationId, output.representationRevision, binding.programRevision);
	final decision = sealWithLayouts(binding, role, source, input, inputLayout, output, outputLayout);
	requireRegistry(decision, registry, binding);
	return decision;
}

/** Revalidate every actual local reference before a native consumer can use the adapter. */
function requireRegistry(decision:OcamlCallableViewLocalDecision, registry:OcamlRepresentationRegistry, binding:OcamlFunctionPlanBinding):Void {
	requireBinding(decision, binding);
	function requireRegistered(reference:OcamlLocalRepresentationReference, expected:OcamlCallableViewDescriptor):Void {
		final registered = registry.require(reference.representationId, binding.programRevision);
		final layout = registry.requireCallableView(reference.representationId, reference.representationRevision, binding.programRevision);
		if (registered.semanticTypeId != reference.semanticTypeId
			|| registered.domain != reference.domain
			|| layout.revision != expected.revision)
			throw "reflaxe.ocaml [ocaml-callable-local:foreign-layout]: callback write refers to another registered layout or storage domain";
	}
	switch (decision.input) {
		case ExistingView(reference):
			requireRegistered(reference, decision.inputLayout);
		case RawOrigin(_):
	}
	requireRegistered(decision.output, decision.outputLayout);
}
#end
