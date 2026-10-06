package backend.cpp;

import backend.cpp.CppManagedSourceCall.CppManagedSourceCallInput;

/** Select the real common standard declaration, independently of source call spelling. */
function owns(declaration:TyDeclarationInfo):Bool {
	return declaration != null
		&& declaration.getModulePath() == "Std"
		&& declaration.getOwner().getCanonicalName() == "Std"
		&& declaration.getIdentity().getCanonicalKey() == "Std#static:string(required:dynamic)->primitive:String#0";
}

/** Revalidate mutable signature arrays before admitting the runtime operation. */
function requireDeclaration(declaration:TyDeclarationInfo):Void {
	if (!owns(declaration))
		throw "managed standard string requires the exact Std declaration";
	final signature = declaration.getSignature();
	if (!declaration.getIsStatic()
		|| declaration.getIsDynamic()
		|| declaration.getTypeParameters().length != 0
		|| signature.getName() != "string"
		|| signature.getArgs().length != 1
		|| !signature.getArgs()[0].isDynamic()
		|| signature.getArgOptional().length != 1
		|| signature.getArgOptional()[0]
		|| signature.getArgRest().length != 1
		|| signature.getArgRest()[0]
		|| signature.getReturnType().getSemanticKey() != "primitive:String")
		throw "managed standard string requires one required Dynamic input and a String result";
}

/**
	Root the operand before conversion and publish its complete String afterward.
	Primitive alternatives reuse the exact formatter; erased values retain their
	runtime tags. Other tags reject explicitly until their formatting contract is
	implemented under haxe_ocaml-hcnk8, including the separate Float review gate.
	Aggregate formatting must use an owned runtime boundary before this grows.
 */
function render(declaration:TyDeclarationInfo, input:CppManagedSourceCallInput, indent:String):Array<String> {
	requireDeclaration(declaration);
	if (input.arguments.length != 1)
		throw "managed standard string requires one evaluated operand";
	final expression = input.arguments[0];
	final type = input.valueType(expression);
	CppManagedClosureAbi.assertComplete(type);
	// Any and other Dynamic-backed abstracts keep the runtime tag of their
	// value. Read that checked representation instead of formatting a nominal name.
	final represented = input.casts == null || type.getNominalIdentity() == null ? type : input.casts.representationType(type);
	final conversionType = represented.isDynamic() ? represented : type;
	final value = "hxhx_std_string_" + input.prefix + "value";
	final result = "hxhx_std_string_" + input.prefix + "bytes";
	final read = value + ".get()";
	final lines = [
		indent + "{",
		indent + "  hxhx::managed::Root<hxhx::managed::Value> " + value + "(" + input.heap + ");"
	];
	for (line in input.renderValue(expression, value, indent + "  "))
		lines.push(line);
	for (line in CppManagedStringConversion.render(conversionType, read, result))
		lines.push(indent + "  " + line);
	lines.push(indent
		+ "  "
		+ (input.destination == null ? "(void)" + result : input.destination + ".set(hxhx::managed::Value::string(" + result + "))")
		+ ";");
	lines.push(indent + "}");
	return lines;
}
