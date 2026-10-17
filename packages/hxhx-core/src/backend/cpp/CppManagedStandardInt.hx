package backend.cpp;

import backend.cpp.CppManagedSourceCall.CppManagedSourceCallInput;

/** Identify the standard integer conversion through its selected declaration, independently of call spelling. */
function owns(declaration:TyDeclarationInfo):Bool {
	return declaration != null
		&& declaration.getModulePath() == "Std"
		&& declaration.getOwner().getCanonicalName() == "Std"
		&& declaration.getIdentity().getCanonicalKey() == "Std#static:int(required:primitive:Float)->primitive:Int#0";
}

/** Authored replacements retain their bodies; mutable signature facts must still match the standard API. */
function requireDeclaration(declaration:TyDeclarationInfo):Void {
	if (!owns(declaration) || declaration.getHasBody())
		throw "managed standard integer requires the exact bodyless Std declaration";
	final signature = declaration.getSignature();
	if (!declaration.getIsStatic()
		|| declaration.getIsDynamic()
		|| declaration.getTypeParameters().length != 0
		|| signature.getName() != "int"
		|| signature.getArgs().length != 1
		|| signature.getArgs()[0].getSemanticKey() != "primitive:Float"
		|| signature.getArgOptional().length != 1
		|| signature.getArgOptional()[0]
		|| signature.getArgRest().length != 1
		|| signature.getArgRest()[0]
		|| signature.getReturnType().getSemanticKey() != "primitive:Int")
		throw "managed standard integer requires one required Float input and an Int result";
}

/**
	Truncate finite numeric values toward zero without changing the source storage.
	Only this standard operation admits numeric Dynamic inputs and the observed
	hxcpp null/Boolean conversions. Other objects require separate coercion rules.
	Bounds reject unspecified numeric inputs before narrowing, including NaN and
	infinities. General numeric transfers, casts and Float boxing retain their owners.
 */
function render(declaration:TyDeclarationInfo, input:CppManagedSourceCallInput, indent:String):Array<String> {
	requireDeclaration(declaration);
	if (input.arguments.length != 1)
		throw "managed standard integer requires one evaluated operand";
	final expression = input.arguments[0];
	var type = input.valueType(expression);
	CppManagedClosureAbi.assertComplete(type);
	if (input.casts != null && type.getNominalIdentity() != null)
		type = input.casts.representationType(type);
	while (type.getNullableInner() != null)
		type = type.getNullableInner();
	if (!type.isDynamic()
		&& !type.isNullLiteral()
		&& type.getSemanticKey() != "primitive:Int"
		&& type.getSemanticKey() != "primitive:Float")
		throw "managed standard integer requires numeric or Dynamic input storage";
	// An inner conversion writes into the outer operand root. Include that
	// destination in its names so the inner scope cannot shadow its own output.
	final prefix = "hxhx_std_int_" + input.prefix + (input.destination == null ? "discarded" : input.destination) + "_";
	final value = prefix + "value";
	final result = prefix + "result";
	final number = prefix + "number";
	final read = value + ".get()";
	final lines = [
		indent + "{",
		indent + "  hxhx::managed::Root<hxhx::managed::Value> " + value + "(" + input.heap + ");"
	];
	for (line in input.renderValue(expression, value, indent + "  "))
		lines.push(line);
	for (line in ["std::int32_t " + result + ";",
		"switch (" + read + ".kind()) {",
		"case hxhx::managed::ValueKind::Integer: "
		+ result
		+ " = "
		+ read
		+ ".asInteger(); break;",
		"case hxhx::managed::ValueKind::Null: " + result + " = 0; break;",
		"case hxhx::managed::ValueKind::Boolean: "
		+ result
		+ " = "
		+ read
		+ ".asBoolean() ? 1 : 0; break;",
		"case hxhx::managed::ValueKind::Float: {",
		"  const double " + number + " = " + read + ".asFloat();",
		"  if (!(" + number + " >= -2147483648.0 && " + number + " <= 2147483647.0))",
		'    throw std::runtime_error("unsupported Std.int value outside the finite Int32 range");',
		"  " + result + " = static_cast<std::int32_t>(" + number + ");",
		"  break;",
		"}",
		'default: throw std::runtime_error("unsupported Std.int runtime value");',
		"}",
		(input.destination == null ? "(void)" + result : input.destination
			+ ".set(hxhx::managed::Value::integer("
			+ result
			+ "))") + ";"
	])
		lines.push(indent + "  " + line);
	lines.push(indent + "}");
	return lines;
}
