package backend.ocaml;

/**
	Convert exact scalar types at native value boundaries. Callbacks and untyped
	values use the same Boolean box and checked Dynamic extraction. The operand
	runs once; unsupported representation changes remain explicit failures.
	Boolean boxing remains distinct from integers; this does not convert numbers.
	Nullable Int, Float, and Bool sources and destinations use the carrier that
	Stage3OcamlNullablePrimitive describes.
 */
function convert(actual:TyType, expected:TyType, value:String, names:Null<Stage3OcamlLocalNames>):String {
	if (actual.getSemanticKey() == expected.getSemanticKey())
		return value;
	final nullableDestination = Stage3OcamlNullablePrimitive.innerPrimitive(expected);
	if (nullableDestination != null)
		return Stage3OcamlNullablePrimitive.store(actual, nullableDestination, value);
	final nullableSource = Stage3OcamlNullablePrimitive.innerPrimitive(actual);
	if (nullableSource != null)
		return Stage3OcamlNullablePrimitive.load(nullableSource, expected, value);
	final source = actual.getSemanticKey();
	final destination = expected.getSemanticKey();
	if (expected.isDynamic())
		return switch source {
			case "primitive:Bool": "HxRuntime.box_bool (" + value + ")";
			case "primitive:Int" | "primitive:String": "Obj.repr (" + value + ")";
			case _: throw "unsupported OCaml value input carrier: " + source;
		};
	if (actual.isDynamic())
		return switch destination {
			case "primitive:Bool": "HxDynamic.booleanValue (" + value + ")";
			case "primitive:Int": checkedExtraction(value, "Int", "int", names);
			case "primitive:String": checkedExtraction(value, "String", "string", names);
			case _: throw "unsupported OCaml value result carrier: " + destination;
		};
	throw "unsupported OCaml value representation change: " + source + " to " + destination;
}

/** Evaluate once and reject a foreign category before interpreting native bits. */
private function checkedExtraction(value:String, category:String, carrier:String, names:Null<Stage3OcamlLocalNames>):String {
	if (names == null)
		throw "OCaml Dynamic extraction requires its local-name owner";
	final local = names.internalName("__hx_callback_result");
	final check = category == "Int" ? "Obj.is_int " + local + " && not (HxRuntime.is_null " + local + ")" : "not (Obj.is_int "
		+ local
		+ ") && Obj.tag "
		+ local
		+ " = Obj.string_tag";
	return "(let "
		+ local
		+ " = ("
		+ value
		+ ") in if "
		+ check
		+ " then (Obj.obj "
		+ local
		+ " : "
		+ carrier
		+ ") else HxRuntime.hx_throw_typed (Obj.repr \"Invalid Dynamic value; expected "
		+ category
		+ "\") [\"String\"; \"Dynamic\"])";
}

/** Checking can be bypassed without erasing the storage required by the destination. */
function untypedValue(facts:Null<TypedBackendCastOccurrence>, value:String, names:Null<Stage3OcamlLocalNames>):String {
	if (facts == null || !facts.getExpression().match(EUntyped(_)))
		throw "OCaml untyped value requires its exact typed occurrence";
	// An unconstrained unchecked result requests no destination representation.
	// Its producer keeps the original carrier, as in an unchecked condition.
	if (facts.getTargetType().isUnknown())
		return value;
	return convert(facts.getSourceType(), facts.getTargetType(), value, names);
}
