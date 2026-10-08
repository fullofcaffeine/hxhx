package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
import reflaxe.ocaml.lowered.OcamlCallableOriginKind;
import reflaxe.ocaml.lowered.OcamlCallableViewRepresentation.OcamlCallableViewDescriptor;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueConversion;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueShape;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;

/** Distinguishes helper occurrences for local writes and function returns. */
enum abstract OcamlCallableValueRole(String) to String {
	final LocalWrite = "callback-write";
	final ReturnValue = "callback-return";
}

/**
	One native callback conversion after its source owner validates the occurrence.

	Local-write and return contracts own storage and declaration evidence. This
	value contains only their common syntax and runtime requirements. A null origin
	preserves an existing view; it never creates a new identity for a call result.
	This operation alone cannot authorize a producer or change a calling convention.
**/
typedef OcamlCallableValueOperation = {
	final id:String;
	final role:OcamlCallableValueRole;
	final source:OcamlLoweredSourceSpan;
	final binding:OcamlFunctionPlanBinding;
	final origin:Null<OcamlCallableOriginKind>;
	final inputLayout:OcamlCallableViewDescriptor;
	final outputLayout:OcamlCallableViewDescriptor;
	final conversion:OcamlGenericValueConversion;
};

/** Reject incompatible layouts before syntax or runtime inventory consumes the operation. */
function requireOperation(operation:OcamlCallableValueOperation):Void {
	reflaxe.ocaml.lowered.OcamlCallableViewRepresentation.validate(operation.inputLayout);
	reflaxe.ocaml.lowered.OcamlCallableViewRepresentation.validate(operation.outputLayout);
	final expected = reflaxe.ocaml.lowered.OcamlGenericCallConversion.crossing(operation.inputLayout.shape, operation.outputLayout.shape);
	final binding = operation.binding;
	if (expected == null || Std.string(expected) != Std.string(operation.conversion))
		throw "reflaxe.ocaml [ocaml-callable-value:incompatible-layouts]: callback conversion does not match its input and output";
	if (operation.id.length == 0
		|| binding.functionId.length == 0
		|| binding.programRevision.length == 0
		|| binding.bodyRevision.length == 0
		|| binding.pipelineRevision.length == 0
		|| operation.source.file.length == 0
		|| operation.source.min < 0
		|| operation.source.max < operation.source.min)
		throw "reflaxe.ocaml [ocaml-callable-value:missing-occurrence]: callback conversion lost its source or function binding";
	switch (operation.role) {
		case LocalWrite, ReturnValue:
		case _:
			throw "reflaxe.ocaml [ocaml-callable-value:unknown-role]: callback conversion has no supported source owner";
	}
	if (operation.origin != null) {
		if (!isScalarArrow(operation.inputLayout.shape))
			throw "reflaxe.ocaml [ocaml-callable-value:unproved-producer]: raw callback has an unproved invocation layout";
		switch (operation.origin) {
			case StaticDeclaration(id) if (id.length == 0):
				throw "reflaxe.ocaml [ocaml-callable-value:missing-declaration]: static origin lost its declaration identity";
			case _:
		}
	}
}

/** Raw arrows with callback parameters or results require a separate invocation-boundary proof. */
function isScalarArrow(shape:OcamlGenericValueShape):Bool {
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
#end
