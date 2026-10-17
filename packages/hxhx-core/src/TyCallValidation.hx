import TyCallAlignment.TyCallAlignmentFailure;
import TyCallAlignment.TyCallAlignmentResult;
import TyCallAlignment.TyCallOperandKind;
import TyAssignmentCompatibility.TyAssignmentNullPolicy;

/**
	Check source operands against a callable before target emission.

	The result preserves omissions and source indices without inserting target values.
	It is a candidate alignment, not a sealed typed call: inference, conversions,
	invocation facts, and alias-use evidence still need publication in the call binding.
	Unsupported assignment and container relationships fail explicitly.
 */
function validate(signature:TyCallableSignature, types:Array<TyType>, kinds:Array<TyCallOperandKind>, nullPolicy:TyAssignmentNullPolicy):TyCallAlignmentResult {
	if (types.length != kinds.length)
		throw "call validation requires one type and kind for each source operand";
	final parameters = signature.getParameters();
	return TyCallAlignment.align(parameters, kinds,
		(source, parameter,
				spread) -> spread ? TyAssignmentCompatibility.classifyRestSpread(parameters[parameter].type,
				types[source]) : TyAssignmentCompatibility.classify(parameters[parameter].type, types[source], nullPolicy));
}

/** Render the selected failure without rerunning compatibility or optional selection. */
function describeFailure(failure:TyCallAlignmentFailure, signature:TyCallableSignature, types:Array<TyType>, kinds:Array<TyCallOperandKind>):String {
	final parameters = signature.getParameters();
	function expectedDisplay(source:Int, parameter:Int):String {
		final element = parameters[parameter].type.getCanonicalDisplay();
		return kinds[source] == Spread && parameters[parameter].isRest ? "haxe.Rest<" + element + ">" : element;
	}
	return switch (failure) {
		case MissingRequired(parameter):
			"Not enough arguments: missing " + (parameters[parameter].name == null ? "parameter " + parameter : parameters[parameter].name);
		case TooManyArguments(_): "Too many arguments";
		case IncompatibleArgument(source, parameter):
			types[source].getCanonicalDisplay() + " should be " + expectedDisplay(source, parameter);
		case UnprovedArgument(source, parameter):
			"Call argument compatibility is not yet supported: " + types[source].getCanonicalDisplay() + " to " + expectedDisplay(source, parameter);
		case UnexpectedSpread(_, _): "Spread requires a rest parameter";
		case MixedRestSpread(_): "Spread cannot be mixed with other rest arguments";
		case UnsupportedRestPosition(_): "Call validation requires the rest parameter to be last";
	};
}
