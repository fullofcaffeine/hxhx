package backend.ocaml;

/**
	Read existing runtime descriptors through exact standard Type declarations.
	Generated class instances already carry their descriptor in private HxAnon
	storage. These calls retain that value; they do not create a class from a name
	or admit first-class class literals. `Type.getClass` on an operand that is not
	statically a generated class goes to `HxReflect.value_class`, which answers
	`String` for strings, `Array` for arrays, the class of a class instance, and
	null for every other value.
 */
function render(input:{
	expression:HxExpr,
	lookup:HxExpr->Null<TypedExpr>,
	classes:Stage3OcamlClassStorage,
	emit:HxExpr->String
}):Null<String> {
	final call = TypedExactStaticCallSource.decode(input.expression);
	if (call == null || call.owner != "Type")
		return null;
	switch call.method {
		case "getClass" | "getClassName" | "getEnumName":
		case _:
			return null;
	}
	final fact = input.lookup == null ? null : input.lookup(input.expression);
	// A static extension call (`using Type; value.getClass()`) keeps its exact
	// declaration in the encoded call, but its callable-expression fact is
	// missing or holds only the callee, with the receiver inside it. The
	// typer already selected the bodiless standard declaration, and every
	// runtime function below accepts any `Obj.t`, so it needs no operand type.
	final extension = fact == null || fact.getTag() == Call && fact.getExpressions().length == 1;
	if (extension
		&& !call.hasBody
		&& call.arguments.length == 1
		&& call.declaration.indexOf("Type#static:" + call.method + "(") == 0) {
		final operand = "Obj.repr (" + input.emit(call.arguments[0]) + ")";
		return call.method == "getClass" ? "HxReflect.value_class (" + operand + ")" : "HxType." + call.method + " (" + operand + ")";
	}
	if (fact == null || fact.getTag() != Call || fact.getExpressions().length != 2 || call.arguments.length != 1)
		throw "OCaml type query requires its exact typed call";
	final declaration = fact.getExpressions()[0].getDeclaration();
	if (declaration == null
		|| declaration.getIdentity().getCanonicalKey() != call.declaration
		|| declaration.getOwner().getCanonicalName() != "Type"
		|| declaration.getModulePath() != "Type"
		|| !declaration.getIsStatic())
		throw "OCaml type query lost its selected standard declaration";
	// An authored provider owns its implementation, even when it replaces Type.
	if (declaration.getHasBody())
		return null;
	final signature = declaration.getSignature();
	if (signature.getArgs().length != 1 || signature.getName() != call.method || declaration.getIsDynamic())
		throw "OCaml type query has an unsupported provider signature";
	if (call.method == "getClass") {
		final result = signature.getReturnType();
		final nominal = result.getNominalIdentity();
		if (nominal == null
			|| nominal.getCanonicalName() != "Class"
			|| result.getTypeArguments().length != 1
			|| result.getTypeArguments()[0].getSemanticKey() != signature.getArgs()[0].getSemanticKey())
			throw "OCaml class query has an unsupported provider signature";
		// Any other operand, such as a Dynamic value, a string, or an array, is
		// classified by the runtime, which reads only layouts it knows.
		final operand = fact.getExpressions()[1].getType();
		if (!operand.isNullLiteral() && input.classes.nominalName(operand) == null)
			return "HxReflect.value_class ("
				+ Stage3OcamlValueConversion.dynamicValue(operand, input.emit(call.arguments[0]), "stage3 emitter: Type.getClass")
				+ ")";
	} else {
		final argument = signature.getArgs()[0];
		final nominal = argument.getNominalIdentity();
		final expected = call.method == "getClassName" ? "Class" : "Enum";
		if (nominal == null
			|| nominal.getCanonicalName() != expected
			|| argument.getTypeArguments().length != 1
			|| signature.getReturnType().getSemanticKey() != "primitive:String")
			throw "OCaml type-name query has an unsupported provider signature";
	}
	// Obj.repr preserves the existing carrier. The single operand executes once.
	return "HxType." + call.method + " (Obj.repr (" + input.emit(call.arguments[0]) + "))";
}
