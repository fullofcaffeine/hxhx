package backend.ocaml;

/**
	Select the native result carrier of a block function that returns a reference.

	Why
	- A block function returns through an exception whose payload is `Obj.t`.
	  Scalars name their OCaml type when the payload is read back. Reference
	  values (arrays, program class instances, anonymous structures and function
	  values) need the same read-back, or emission stops.

	What
	- Returns the OCaml type the emitter renders for such a result, which may be
	  `_` when the reference has no closed OCaml type. Returns null for any other
	  result, so unsupported carriers still stop emission.

	How
	- The payload holds the returned value itself, so reading it back keeps the
	  value's identity and representation. Abstracts, Float and nullable scalars
	  are not references here: their storage differs from their declared type.
 */
function select(type:TyType, classes:Null<Stage3OcamlClassStorage>, renderType:TyType->String):Null<String> {
	if (type == null || type.hasUnknownComponent() || type.isNullable())
		return null;
	final revealed = TyAliasExpansion.reveal(type);
	final identity = revealed.getNominalIdentity();
	final isArray = identity != null && identity.getCanonicalName() == "Array";
	if (!isArray && (classes == null || !classes.usesIdentity(revealed)))
		return null;
	if (revealed.isFunction())
		return functionCarrier(revealed, renderType);
	return renderType(revealed);
}

/**
	A function value is read back at its arrow type, so a later call applies it
	with the right arity. An open `_` result would make every application look
	like an extra argument to OCaml.
 */
private function functionCarrier(type:TyType, renderType:TyType->String):Null<String> {
	final rendered = renderType(type);
	if (rendered != "_")
		return rendered;
	final parameters = type.getFunctionParameters();
	final parts = new Array<String>();
	for (parameter in parameters) {
		if (parameter.isOptional || parameter.isRest || Stage3OcamlNullablePrimitive.innerPrimitive(parameter.type) != null)
			return null;
		parts.push(renderType(parameter.type));
	}
	if (parts.length == 0)
		parts.push("unit");
	final result = type.getFunctionReturn();
	if (Stage3OcamlNullablePrimitive.innerPrimitive(result) != null)
		return null;
	parts.push(renderType(result));
	return "(" + parts.join(" -> ") + ")";
}
