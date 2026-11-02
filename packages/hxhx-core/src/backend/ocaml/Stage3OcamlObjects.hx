package backend.ocaml;

/** Store object fields as Dynamic carriers so Boolean identity survives aliased access. */
function store(type:TyType, value:String):String {
	if (type.isUnknown())
		throw "OCaml object storage requires an exact value type";
	final carrier = type.getSemanticKey() == "primitive:Bool" ? OcamlDynamicOperatorLowering.OcamlDynamicArgumentCarrier.ExactBool : type.isDynamic() ? OcamlDynamicOperatorLowering.OcamlDynamicArgumentCarrier.DynamicValue : OcamlDynamicOperatorLowering.OcamlDynamicArgumentCarrier.ConcreteValue;
	return OcamlDynamicOperatorLowering.callArgument("Dynamic", carrier, value);
}

/** Restore a concrete read only after the typed access establishes its result type. */
function read(type:TyType, value:String):String {
	if (type.isUnknown())
		throw "OCaml object read requires an exact result type";
	return type.getSemanticKey() == "primitive:Bool" ? "HxRuntime.unbox_bool_or_obj (" + value + ")" : type.isDynamic() ? value : "(Obj.magic ("
		+ value
		+ "))";
}

/** Preserve left-to-right effects before comparing object or function identity. */
function equality(equal:Bool, left:String, right:String, names:Stage3OcamlLocalNames):String {
	final leftName = names.internalName("__hx_object_left");
	final rightName = names.internalName("__hx_object_right");
	return "(let " + leftName + " = (" + left + ") in let " + rightName + " = (" + right + ") in (Obj.repr " + leftName + ") " + (equal ? "==" : "!=")
		+ " (Obj.repr " + rightName + "))";
}

/**
	The representation a structure field stores a value in. Structure fields
	are erased `Obj.t` slots, so a nullable value entering a Float field keeps
	the nullable Float carrier (null stays null; a present Int becomes a boxed
	Float), as upstream stores null without throwing. The record's field type
	may not mark an optional field, so this does not depend on that marker.
 */
function storageDestination(actual:Null<TyType>, field:Null<TyType>):Null<TyType> {
	if (actual == null || field == null || Stage3OcamlNullablePrimitive.innerPrimitive(actual) == null)
		return field;
	return Stage3OcamlNumericWidening.isFloatDestination(field) ? TyType.nullable(field) : field;
}

/** Allocate once and initialize written fields in order through existing runtime primitives. */
function literal(occurrence:TypedBackendAggregateOccurrence, emit:HxExpr->String, names:Stage3OcamlLocalNames, quote:String->String):String {
	final fields = switch occurrence.getExpression() {
		case EAnon(fields, _): fields;
		case _: throw "object allocation requires an anonymous aggregate";
	};
	final values = occurrence.getChildren();
	final types = occurrence.getChildTypes();
	final object = names.internalName("__hx_object");
	// A Float field stores its value as a Float, also from an Int value
	// (`final p:{x:Float} = {x: 1}`). See `storageDestination` for nullable values.
	final structure = TyAliasExpansion.revealNonNullable(occurrence.getType());
	final structureFields = structure.isAnonymous() ? structure.getAnonymousFields() : [];
	function stored(index:Int):String {
		var expected:Null<TyType> = null;
		for (field in structureFields)
			if (field.name == fields[index])
				expected = storageDestination(types[index], TypedBackendObjectAccess.fieldDestination(field));
		final rendered = emit(values[index]);
		return Stage3OcamlNumericWidening.convertsToFloat(types[index],
			expected) ? store(expected, Stage3OcamlNumericWidening.toFloatDestination(types[index], expected, rendered)) : store(types[index], rendered);
	}
	final writes = [
		for (index in 0...fields.length)
			"HxAnon.set (Obj.repr "
			+ object
			+ ") "
			+ quote(fields[index])
			+ " ("
			+ stored(index)
			+ "); "];
	return "(let " + object + " = HxAnon.create () in " + writes.join("") + object + ")";
}

/** Reads and assignments share the same carrier; assignment returns its original typed value. */
function access(occurrence:TypedBackendObjectAccess, emit:HxExpr->String, names:Stage3OcamlLocalNames, quote:String->String):String {
	return switch occurrence.kind {
		case Read:
			final stored = "HxAnon.get (Obj.repr (" + emit(occurrence.receiver) + ")) " + quote(occurrence.field);
			// This owned access reads the runtime's Obj.t field storage. An open
			// field type keeps that carrier intact; only a concrete result permits
			// unboxing. This does not admit an arbitrary Unknown expression or store.
			occurrence.resultType.isUnknown() ? "(" + stored + ")" : read(occurrence.resultType, stored);
		case Write:
			if (occurrence.value == null || occurrence.valueType == null)
				throw "object assignment lost its typed operand";
			final object = names.internalName("__hx_object");
			final value = names.internalName("__hx_field_value");
			// A Float field converts an Int or Null<Int> value, and the assignment
			// then yields the stored Float.
			final destination = storageDestination(occurrence.valueType, occurrence.placeType);
			final converts = Stage3OcamlNumericWidening.convertsToFloat(occurrence.valueType, destination);
			final rendered = emit(occurrence.value);
			"(let "
			+ object
			+ " = ("
			+ emit(occurrence.receiver)
			+ ") in let "
			+ value
			+ " = ("
			+ (converts ? Stage3OcamlNumericWidening.toFloatDestination(occurrence.valueType, destination, rendered) : rendered)
			+ ") in HxAnon.set (Obj.repr "
			+ object
			+ ") "
			+ quote(occurrence.field)
			+ " ("
			+ store(converts ? destination : occurrence.valueType, value)
			+ "); "
			+ value
			+ ")";
		case Compound(op):
			throw "OCaml structural field compound assignment requires typed lowering: " + op;
	};
}
