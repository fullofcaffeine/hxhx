package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
import haxe.crypto.Sha256;
import reflaxe.ocaml.ast.OcamlCallableViewSyntax.carrier;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.OcamlGenericValueShape;
import reflaxe.ocaml.lowered.OcamlGenericCallConversion.shapeId;

/** A closed callback signature and its native view layout, without request-local type objects. */
typedef OcamlCallableViewDescriptor = {
	final shape:OcamlGenericValueShape;
	final semanticTypeId:String;
	final carrierTypeId:String;
	final revision:String;
};

/**
	Describes non-null callback views whose invocation types are fully known.

	Each function argument or result recursively uses the same view representation.
	Scalars keep their existing native carriers. The descriptor does not prove a
	producer, a storage occurrence, nullability, or a foreign calling convention.
	Those choices remain with program and function plans before syntax emission.
**/
final MODEL_REVISION = "ocaml-callable-identity-view-v1";

/** Copy the signature before publishing a stable layout identity. */
function describe(shape:OcamlGenericValueShape):OcamlCallableViewDescriptor {
	switch (shape) {
		case FunctionValue(_, _):
		case _:
			throw "reflaxe.ocaml [ocaml-callable-view:invalid-shape]: expected a closed function signature";
	}
	// Building the type checks every nested argument and result before selection.
	valueType(shape, false);
	final detached = copyShape(shape);
	final semanticTypeId = shapeId(detached);
	final carrierTypeId = 'callable-view<$semanticTypeId>';
	return {
		shape: detached,
		semanticTypeId: semanticTypeId,
		carrierTypeId: carrierTypeId,
		revision: "sha256:" + Sha256.encode([MODEL_REVISION, semanticTypeId, carrierTypeId].join("\n"))
	};
}

/** Reject a changed signature or layout before using a detached descriptor. */
function validate(descriptor:OcamlCallableViewDescriptor):Void {
	final expected = describe(descriptor.shape);
	if (descriptor.semanticTypeId != expected.semanticTypeId
		|| descriptor.carrierTypeId != expected.carrierTypeId
		|| descriptor.revision != expected.revision)
		throw "reflaxe.ocaml [ocaml-callable-view:stale-descriptor]: callback signature or layout changed";
}

/** Materialize structured native types only after the program registry resolves this descriptor. */
function typeExpr(descriptor:OcamlCallableViewDescriptor):OcamlTypeExpr {
	validate(descriptor);
	return valueType(descriptor.shape, false);
}

private function valueType(shape:OcamlGenericValueShape, allowVoid:Bool):OcamlTypeExpr {
	return switch (shape) {
		case Integer: TIdent("int");
		case Boolean: TIdent("bool");
		case Text(_): TIdent("string");
		case DynamicValue, NullableInteger, NullableBoolean: TIdent("Obj.t");
		case EffectOnly if (allowVoid): TIdent("unit");
		case FunctionValue(arguments, result):
			var invocation = valueType(result, true);
			if (arguments.length == 0)
				invocation = TArrow(TIdent("unit"), invocation);
			else {
				var index = arguments.length;
				while (index-- > 0)
					invocation = TArrow(valueType(arguments[index], false), invocation);
			}
			carrier(invocation, TIdent("Obj.t"));
		case _: throw "reflaxe.ocaml [ocaml-callable-view:unproved-carrier]: callback leaf needs its own representation proof";
	};
}

/** Argument lists in the signature belong to the descriptor, never to its caller. */
private function copyShape(shape:OcamlGenericValueShape):OcamlGenericValueShape {
	return switch (shape) {
		case FunctionValue(arguments, result): FunctionValue(arguments.map(copyShape), copyShape(result));
		case _: shape;
	};
}
#end
