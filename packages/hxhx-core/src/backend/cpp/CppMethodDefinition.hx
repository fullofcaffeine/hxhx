package backend.cpp;

/** One prepared ordinary method, with defaults confined to its member declaration. */
typedef CppMethodDefinitionInput = {
	final ownerName:String;
	final classParameters:Array<String>;
	final methodParameters:Array<String>;
	final name:String;
	final isStatic:Bool;
	final returnType:String;
	final declarationArguments:String;
	final definitionArguments:String;
	final body:Array<String>;
}

/**
	Separate member visibility from executable bodies without parsing generated C++.
	All class layouts must precede these definitions, allowing methods in different
	classes to call each other. Shared typing and the caller still own signatures,
	local bindings, defaults, and body behavior.
 */
function render(input:CppMethodDefinitionInput):{declaration:Array<String>, definition:Array<String>} {
	final declaration = new Array<String>();
	if (input.methodParameters.length != 0)
		declaration.push("  " + templateLine(input.methodParameters));
	declaration.push("  " + (input.isStatic ? "static " : "") + input.returnType + " " + input.name + "(" + input.declarationArguments + ");");
	final definition = new Array<String>();
	if (input.classParameters.length != 0)
		definition.push(templateLine(input.classParameters));
	if (input.methodParameters.length != 0)
		definition.push(templateLine(input.methodParameters));
	final owner = input.ownerName + (input.classParameters.length == 0 ? "" : "<" + input.classParameters.join(", ") + ">");
	definition.push("inline " + input.returnType + " " + owner + "::" + input.name + "(" + input.definitionArguments + ") {");
	for (line in input.body)
		definition.push(line);
	definition.push("}");
	return {declaration: declaration, definition: definition};
}

private function templateLine(parameters:Array<String>):String
	return "template<" + [for (parameter in parameters) "typename " + parameter].join(", ") + ">";
