package backend.ocaml;

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
	return "(" + bindings.join("") + "HxBootArray.of_list [" + values.join("; ") + "])";
}
