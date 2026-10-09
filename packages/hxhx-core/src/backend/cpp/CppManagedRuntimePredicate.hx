package backend.cpp;

import backend.cpp.CppManagedSourceCall.CppManagedSourceCallInput;

/** Bind the selected standard predicate; source spelling never selects this operation. */
function owns(declaration:TyDeclarationInfo):Bool {
	return declaration != null
		&& declaration.getModulePath() == "Std"
		&& declaration.getOwner().getCanonicalName() == "Std"
		&& declaration.getIdentity().getCanonicalKey() == "Std#static:isOfType(required:dynamic,required:dynamic)->primitive:Bool#0";
}

/** Recheck mutable signature facts whenever the native binding is consumed. */
function requireDeclaration(declaration:TyDeclarationInfo):Void {
	if (!owns(declaration))
		throw "managed runtime predicate requires the exact Std declaration";
	final signature = declaration.getSignature();
	if (!declaration.getIsStatic()
		|| declaration.getIsDynamic()
		|| declaration.getTypeParameters().length != 0
		|| signature.getName() != "isOfType"
		|| signature.getArgs().length != 2
		|| signature.getArgOptional().length != 2
		|| signature.getArgRest().length != 2
		|| signature.getReturnType().getSemanticKey() != "primitive:Bool")
		throw "managed runtime predicate requires the exact standard signature";
	for (index in 0...2)
		if (!signature.getArgs()[index].isDynamic() || signature.getArgOptional()[index] || signature.getArgRest()[index])
			throw "managed runtime predicate requires two required Dynamic arguments";
}

/** Root both operands in source order even when the caller discards the result. */
function render(declaration:TyDeclarationInfo, input:CppManagedSourceCallInput, indent:String):Array<String> {
	requireDeclaration(declaration);
	if (input.arguments.length != 2)
		throw "managed runtime predicate requires two evaluated operands";
	final roots = [for (index in 0...2) "hxhx_predicate_" + input.prefix + "value" + index];
	final lines = [indent + "{"];
	for (index in 0...2) {
		CppManagedClosureAbi.assertComplete(input.valueType(input.arguments[index]));
		lines.push(indent + "  hxhx::managed::Root<hxhx::managed::Value> " + roots[index] + "(" + input.heap + ");");
		for (line in input.renderValue(input.arguments[index], roots[index], indent + "  "))
			lines.push(line);
	}
	final call = "hxhx_runtime_is_of_type(" + roots[0] + ".get(), " + roots[1] + ".get())";
	lines.push(indent
		+ "  "
		+ (input.destination == null ? "(void)" + call : input.destination + ".set(hxhx::managed::Value::boolean(" + call + "))")
		+ ";");
	lines.push(indent + "}");
	return lines;
}
