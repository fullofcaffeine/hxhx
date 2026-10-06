package backend.cpp;

import backend.cpp.CppManagedSourceCall.CppManagedSourceCallInput;

/** The standard generic binders, not parameter display names, identify the narrowing contract. */
private function parameter(slot:Int):TyTypeParameterId {
	return TyTypeParameterId.method(new TyNominalTypeId("Std"), true, "downcast", 0, slot, slot == 0 ? "T" : "S");
}

/** Admit only the exact standard declaration; ordinary same-named methods remain authored calls. */
function owns(declaration:TyDeclarationInfo):Bool {
	final source = TyType.typeParameter(parameter(0));
	final result = TyType.typeParameter(parameter(1));
	final target = TyType.nominal(new TyNominalTypeId("Class"), [result]);
	return declaration != null
		&& declaration.getModulePath() == "Std"
		&& declaration.getOwner().getCanonicalName() == "Std"
		&& declaration.getIdentity().getCanonicalKey() == "Std#static:downcast(required:"
			+ source.getSemanticKey()
			+ ",required:"
			+ target.getSemanticKey()
			+ ")->"
			+ result.getSemanticKey()
			+ "#0";
}

/** Revalidate mutable signature facts and the source/target bound before native selection. */
function requireDeclaration(declaration:TyDeclarationInfo):Void {
	if (!owns(declaration))
		throw "managed downcast requires the exact Std declaration";
	final signature = declaration.getSignature();
	final parameters = declaration.getTypeParameterIds();
	final source = TyType.typeParameter(parameter(0));
	final result = TyType.typeParameter(parameter(1));
	final target = TyType.nominal(new TyNominalTypeId("Class"), [result]);
	if (!declaration.getIsStatic()
		|| declaration.getIsDynamic()
		|| parameters.length != 2
		|| !parameters[0].equals(parameter(0))
		|| !parameters[1].equals(parameter(1))
		|| signature.getName() != "downcast"
		|| signature.getArgs().length != 2
		|| signature.getArgs()[0].getSemanticKey() != source.getSemanticKey()
		|| signature.getArgs()[1].getSemanticKey() != target.getSemanticKey()
		|| signature.getReturnType().getSemanticKey() != result.getSemanticKey()
		|| signature.getArgOptional().length != 2
		|| signature.getArgRest().length != 2)
		throw "managed downcast requires its exact generic signature";
	for (slot in 0...2)
		if (signature.getArgOptional()[slot] || signature.getArgRest()[slot])
			throw "managed downcast requires two required operands";
	final bounds = declaration.getResolvedTypeParameterConstraints();
	final sourceBounds = bounds.get(parameter(0).getCanonicalKey());
	final resultBounds = bounds.get(parameter(1).getCanonicalKey());
	if (sourceBounds == null
		|| sourceBounds.length != 1
		|| !sourceBounds[0].isAnonymous()
		|| sourceBounds[0].getAnonymousFields().length != 0
		|| resultBounds == null
		|| resultBounds.length != 1
		|| resultBounds[0].getSemanticKey() != source.getSemanticKey())
		throw "managed downcast requires its resolved source and target bounds";
}

/**
	The checked declaration returns S from Class<S>. Recover that precise type
	from the owned operand, never from a rendered marker or an erased native ABI.
	Shared typing already enforces S:T; native matching decides whether this
	particular value belongs to S. A failed match returns null in reference storage.
 */
function resultType(declaration:TyDeclarationInfo, arguments:Array<HxExpr>, valueType:HxExpr->TyType, classes:CppManagedClassStorage):TyType {
	requireDeclaration(declaration);
	if (arguments.length != 2 || classes == null)
		throw "managed downcast requires two owned operands and class descriptors";
	CppManagedClosureAbi.assertComplete(valueType(arguments[0]));
	var target = valueType(arguments[1]);
	if (!classes.isClassValue(target))
		throw "managed downcast requires an exact Class operand";
	while (target.getNullableInner() != null)
		target = target.getNullableInner();
	return target.getTypeArguments()[0];
}

/** Keep both operands rooted in source order, then publish the original allocation or null. */
function render(declaration:TyDeclarationInfo, input:CppManagedSourceCallInput, indent:String):Array<String> {
	resultType(declaration, input.arguments, input.valueType, input.classes);
	final prefix = "hxhx_downcast_" + input.prefix + (input.destination == null ? "discarded" : input.destination) + "_";
	final roots = [for (slot in 0...2) prefix + "value" + slot];
	final lines = [indent + "{"];
	for (slot in 0...2) {
		lines.push(indent + "  hxhx::managed::Root<hxhx::managed::Value> " + roots[slot] + "(" + input.heap + ");");
		for (line in input.renderValue(input.arguments[slot], roots[slot], indent + "  "))
			lines.push(line);
	}
	final matches = "hxhx_runtime_is_of_type(" + roots[0] + ".get(), " + roots[1] + ".get())";
	lines.push(indent
		+ "  "
		+ (input.destination == null ? "(void)" + matches : input.destination
			+ ".set("
			+ matches
			+ " ? "
			+ roots[0]
			+ ".get() : hxhx::managed::Value{});")
		+ (input.destination == null ? ";" : ""));
	lines.push(indent + "}");
	return lines;
}
