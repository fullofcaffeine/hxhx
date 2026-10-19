package backend.ocaml;

/**
	Restore an array parameter's native reference view from an erased argument.
	The exact projected call owns both types. Obj.obj changes only the OCaml
	view: aliases, null, element storage, and the stringifier remain unchanged.
	Haxe does not check this implicit Dynamic conversion when entering a call,
	so even an unused non-array argument must pass through. Array operations
	own runtime storage checks; this boundary never reads a record or its slots.
 */
function callArgument(argument:Null<TypedBackendCallArgument>, value:String):Null<String> {
	if (argument == null || argument.expectedType == null || !argument.type.isDynamic())
		return null;
	final expected = TyAliasExpansion.revealNonNullable(argument.expectedType);
	final identity = expected.getNominalIdentity();
	if (identity == null || identity.getCanonicalName() != "Array" || expected.getTypeArguments().length != 1)
		return null;
	return "(Obj.obj (" + value + ") : _ HxBootArray.t)";
}

/** Limit indexed lowering to the runtime array carrier and an exact integer index. */
function supportsAccess(occurrence:TypedBackendArrayAccess):Bool {
	final type = TyAliasExpansion.revealNonNullable(occurrence.receiverType);
	final identity = type.getNominalIdentity();
	return ((identity != null && identity.getCanonicalName() == "Array")
		|| type.isDynamic())
		&& occurrence.indexType.getSemanticKey() == "primitive:Int";
}

/**
	Preserve the exact element conversion on the allocated array itself.
	Erased aliases keep the same object and observe later writes. The callback
	reads the existing typed carrier; it neither copies nor converts stored slots.
 */
function retainStringifier(type:TyType, rendered:String, names:Stage3OcamlLocalNames):String {
	final concrete = TyAliasExpansion.revealNonNullable(type);
	final identity = concrete.getNominalIdentity();
	if (identity == null || identity.getCanonicalName() != "Array" || concrete.getTypeArguments().length != 1 || names == null)
		throw "OCaml array allocation requires its exact element type and local names";
	final element = names.internalName("__hx_array_string_element");
	// The runtime supplies this array's erased slot. Exact element facts restore
	// its carrier even when a producer uses the dynamic callback ABI.
	return "HxArray.with_element_stringifier ("
		+ rendered
		+ ") (fun "
		+ element
		+ " -> "
		+ Stage3OcamlStringConversion.convert(concrete.getTypeArguments()[0], "(Obj.magic " + element + ")", names)
		+ ")";
}

/**
	Execute indexed reads and writes from their exact typed operands.
	Bind receiver and index once. Compound updates read the old element before
	the right operand runs, then store once and return the assigned value.
 */
function access(occurrence:TypedBackendArrayAccess, emit:HxExpr->String, names:Stage3OcamlLocalNames):Null<String> {
	final type = TyAliasExpansion.revealNonNullable(occurrence.receiverType);
	if (!supportsAccess(occurrence))
		return null;
	if (names == null)
		throw "OCaml indexed access requires its exact local naming owner";
	final array = names.internalName("__hx_indexed_array");
	final index = names.internalName("__hx_indexed_index");
	final prefix = "(let " + array + " = (" + emit(occurrence.receiver) + ") in let " + index + " = (" + emit(occurrence.index) + ") in ";
	final receiver = "(Obj.magic " + array + ")";
	return switch occurrence.kind {
		case Read:
			prefix + "HxBootArray.get " + receiver + " " + index + ")";
		case Write:
			final value = names.internalName("__hx_indexed_value");
			final dynamicSlot = type.isDynamic() || (type.getTypeArguments().length == 1 && type.getTypeArguments()[0].isDynamic());
			final stored = dynamicSlot ? "(Obj.magic (" + Stage3OcamlObjects.store(occurrence.valueType, value) + "))" : value;
			prefix
			+ "let "
			+ value
			+ " = ("
			+ emit(occurrence.value)
			+ ") in ignore (HxBootArray.set "
			+ receiver
			+ " "
			+ index
			+ " "
			+ stored
			+ "); "
			+ value
			+ ")";
		case Compound(op):
			if (occurrence.resultType.getSemanticKey() != "primitive:Int" || occurrence.valueType.getSemanticKey() != "primitive:Int")
				throw "OCaml indexed compound update requires a supported exact numeric operation";
			final operation = switch op {
				case "+=": "HxInt.add";
				case "-=": "HxInt.sub";
				case "*=": "HxInt.mul";
				case _: throw "unsupported OCaml indexed compound operation: " + op;
			};
			final old = names.internalName("__hx_indexed_old");
			final right = names.internalName("__hx_indexed_right");
			final result = names.internalName("__hx_indexed_result");
			prefix
			+ "let "
			+ old
			+ " = HxBootArray.get "
			+ receiver
			+ " "
			+ index
			+ " in let "
			+ right
			+ " = ("
			+ emit(occurrence.value)
			+ ") in let "
			+ result
			+ " = "
			+ operation
			+ " "
			+ old
			+ " "
			+ right
			+ " in HxBootArray.set "
			+ receiver
			+ " "
			+ index
			+ " "
			+ result
			+ ")";
	};
}

/**
	Allocate array literals after evaluating their elements in source order.
	Dynamic slots retain Boolean boxes; concrete slots retain their native value.
	The runtime container erases its element type, so the conversion must happen
	while the exact typed child occurrences are still available.
 */
function literal(occurrence:TypedBackendAggregateOccurrence, emit:HxExpr->String, names:Stage3OcamlLocalNames):String {
	switch occurrence.getExpression() {
		case EArrayDecl(_):
		case _:
			throw "OCaml array allocation requires a typed array literal";
	}
	final arguments = occurrence.getType().getTypeArguments();
	if (arguments.length != 1)
		throw "OCaml array allocation requires its element type";
	final children = occurrence.getChildren();
	final types = occurrence.getChildTypes();
	final bindings = new Array<String>();
	final values = new Array<String>();
	for (index in 0...children.length) {
		final name = names.internalName("__hx_array_element_" + index);
		final value = emit(children[index]);
		final stored = arguments[0].isDynamic() ? Stage3OcamlObjects.store(types[index], value) : value;
		bindings.push("let " + name + " = (" + stored + ") in ");
		// HxArray's polymorphic container also carries the target null sentinel.
		// The typed element contract above owns each value before that erasure.
		values.push("(Obj.magic " + name + ")");
	}
	return "("
		+ bindings.join("")
		+ retainStringifier(occurrence.getType(), "HxBootArray.of_list [" + values.join("; ") + "]", names)
		+ ")";
}
