package backend.cpp;

import backend.cpp.CppManagedSourceCall.CppManagedSourceCallInput;

/**
	Bind the standard Sys output API to a byte-writing primitive. The program must
	supply the real selected declaration; missing source methods are never rebound
	by call spelling. Revalidate on use because signature arrays are mutable.
	Shared call selection owns source visibility; this binding checks native transport.
 */
function requireDeclaration(declaration:TyDeclarationInfo):Void {
	if (declaration == null || declaration.getModulePath() != "Sys" || declaration.getOwner().getCanonicalName() != "Sys")
		throw "managed output requires the exact Sys declaration";
	final signature = declaration.getSignature();
	if ((signature.getName() != "print" && signature.getName() != "println")
		|| !declaration.getIsStatic()
		|| declaration.getIsDynamic()
		|| declaration.getTypeParameters().length != 0
		|| signature.getArgs().length != 1
		|| !signature.getArgs()[0].isDynamic()
		|| signature.getArgOptional().length != 1
		|| signature.getArgOptional()[0]
		|| signature.getArgRest().length != 1
		|| signature.getArgRest()[0]
		|| signature.getReturnType().getSemanticKey() != "primitive:Void")
		throw "managed output requires the exact Sys output signature";
}

/**
	Evaluate one rooted operand before writing any bytes. Haxe owns formatting;
	the native primitive only writes an exact byte span. Other value types require
	their own formatting contract before this compiler can emit these calls.
 */
function render(declaration:TyDeclarationInfo, input:CppManagedSourceCallInput, indent:String):Array<String> {
	requireDeclaration(declaration);
	if (input.arguments.length != 1 || input.destination != null)
		throw "managed output requires one argument and no result";
	final expression = input.arguments[0];
	final value = "hxhx_output_" + input.prefix + "value";
	final read = value + ".get()";
	final formatted = CppManagedStringConversion.render(input.valueType(expression), read, "hxhx_output_bytes");
	final lines = [
		"{",
		"  hxhx::managed::Root<hxhx::managed::Value> " + value + "(" + input.heap + ");"
	];
	for (line in input.renderValue(expression, value, "  "))
		lines.push(line);
	for (line in formatted)
		lines.push("  " + line);
	if (declaration.getSignature().getName() == "println")
		lines.push("  hxhx_output_bytes.push_back('\\n');");
	lines.push("  hxhx::managed::writeStdout(hxhx_output_bytes);");
	lines.push("}");
	return [for (line in lines) indent + line];
}
