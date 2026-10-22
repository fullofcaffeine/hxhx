package backend.ocaml;

/** Require the real runtime array declaration before selecting native array storage. */
private function arrayElement(type:TyType):TyType {
	final concrete = TyAliasExpansion.revealNonNullable(type);
	final identity = concrete.getNominalIdentity();
	final arguments = concrete.getTypeArguments();
	if (identity == null || identity.getCanonicalName() != "Array" || arguments.length != 1)
		throw "OCaml collection control requires an exact Array element type";
	return arguments[0];
}

/** Reject unsupported iterable carriers before the ordinary statement renderer can assume an array. */
function validate(expression:HxExpr, lookup:HxExpr->TypedBackendCollectionControl):Void {
	TypedBackendSourceWalk.expression(expression, value -> {
		switch value {
			case ELoweredControl(For(KeyValue(_, _)), _, _, _):
				throw "OCaml key/value iteration requires its selected protocol lowering";
			case ELoweredControl(For(_), _, [iterable, _], _):
				switch lookup(value).operation {
					case Iterate(type, range):
						if (range) {
							if (!iterable.match(ERange(_, _)))
								throw "OCaml iteration lost its selected range";
						} else {
							arrayElement(type);
						}
					case _: throw "OCaml iteration requires its exact typed operation";
				}
			case ELoweredControl(ArrayAppend, "", [_, _], _):
				switch lookup(value).operation {
					case Append(type, element):
						if (arrayElement(type).getSemanticKey() != element.getSemanticKey()) throw "OCaml append lost its selected element conversion";
					case _: throw "OCaml append requires its exact typed operation";
				}
			case _:
		}
	});
}

/** Adapt method control after validating the original tree and its collection representations. */
function statement(expression:HxExpr, projection:TypedBackendFunctionProjection):HxStmt {
	if (projection == null)
		throw "OCaml method control requires its exact function projection";
	projection.requireExpression(expression);
	validate(expression, projection.requireCollectionControl);
	return TypedControlStatements.methodStatement(expression, projection.requireRootControlIdentity(), null,
		value -> validate(value, projection.requireCollectionControl));
}

/** Append once after evaluating the array and value in source order, preserving Dynamic boxes. */
function append(occurrence:TypedBackendCollectionControl, emit:HxExpr->String, names:Stage3OcamlLocalNames):String {
	if (names == null)
		throw "OCaml append requires its local naming owner";
	switch occurrence.operation {
		case Append(type, element):
			if (arrayElement(type).getSemanticKey() != element.getSemanticKey())
				throw "OCaml append lost its selected element conversion";
		case _:
			throw "OCaml append requires its exact typed operation";
	}
	final children = switch occurrence.expression {
		case ELoweredControl(ArrayAppend, "", values, _) if (values.length == 2): values;
		case _: throw "OCaml append has an invalid operation layout";
	};
	final array = names.internalName("__hx_append_array");
	final value = names.internalName("__hx_append_value");
	// HxArray erases its native element type. The shared lowerer has already
	// converted the yield to that element type, including existing Dynamic boxes.
	return "(let " + array + " = (" + emit(children[0]) + ") in let " + value + " = (" + emit(children[1]) + ") in ignore (HxBootArray.push (Obj.magic "
		+ array + ") (Obj.magic " + value + ")))";
}
