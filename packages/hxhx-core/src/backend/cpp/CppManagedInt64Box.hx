package backend.cpp;

import backend.cpp.CppManagedSourceCall.CppManagedSourceCallInput;

/** The private provider boundary exposes checked storage operations, never public method-name replacements. */
private function signature(name:String):Null<{args:Array<String>, result:String}> {
	return switch name {
		case "box": {args: ["primitive:Int", "primitive:Int"], result: "dynamic"};
		case "high" | "low": {args: ["dynamic"], result: "primitive:Int"};
		case "isValue": {args: ["dynamic"], result: "primitive:Bool"};
		case _: null;
	};
}

/** Bind only a complete selected declaration; project-authored bodies keep their ordinary execution. */
function owns(declaration:TyDeclarationInfo):Bool {
	if (declaration == null
		|| declaration.getModulePath() != "haxe.Int64"
		|| declaration.getOwner().getCanonicalName() != "haxe.Int64.NativeInt64")
		return false;
	final name = declaration.getSignature().getName();
	final selected = signature(name);
	return selected != null
		&& declaration.getIdentity().getCanonicalKey() == "haxe.Int64.NativeInt64#static:"
			+ name
			+ "("
			+ [for (argument in selected.args) "required:" + argument].join(",")
				+ ")->"
				+ selected.result
				+ "#0";
}

/** Mutable signature arrays must still describe the exact bodyless primitive at every consumption. */
function requireDeclaration(declaration:TyDeclarationInfo):Void {
	if (!owns(declaration) || declaration.getHasBody())
		throw "managed Int64 storage requires its exact bodyless provider declaration";
	final actual = declaration.getSignature();
	final selected = signature(actual.getName());
	if (!declaration.getIsStatic()
		|| declaration.getIsDynamic()
		|| declaration.getTypeParameters().length != 0
		|| actual.getArgs().length != selected.args.length
		|| actual.getArgOptional().length != selected.args.length
		|| actual.getArgRest().length != selected.args.length
		|| actual.getReturnType().getSemanticKey() != selected.result)
		throw "managed Int64 storage requires its exact primitive signature";
	for (index in 0...selected.args.length)
		if (actual.getArgs()[index].getSemanticKey() != selected.args[index]
			|| actual.getArgOptional()[index]
			|| actual.getArgRest()[index])
			throw "managed Int64 storage requires its exact required operands";
}

/** Keep operands rooted and ordered, including allocation, discarded results and nested calls. */
function render(declaration:TyDeclarationInfo, input:CppManagedSourceCallInput, indent:String):Array<String> {
	requireDeclaration(declaration);
	final actual = declaration.getSignature();
	if (input.arguments.length != actual.getArgs().length)
		throw "managed Int64 storage requires its complete evaluated operands";
	final prefix = "hxhx_int64_" + input.prefix + (input.destination == null ? "discarded" : input.destination) + "_";
	final roots = [for (index in 0...input.arguments.length) prefix + index];
	final lines = [indent + "{"];
	for (index in 0...input.arguments.length) {
		CppManagedClosureAbi.assertComplete(input.valueType(input.arguments[index]));
		if (!input.acceptsStoredTransfer(input.arguments[index], actual.getArgs()[index]))
			throw "managed Int64 storage requires checked operand transfer";
		lines.push(indent + "  hxhx::managed::Root<hxhx::managed::Value> " + roots[index] + "(" + input.heap + ");");
		for (line in input.renderValue(input.arguments[index], roots[index], indent + "  "))
			lines.push(line);
	}
	final first = roots[0] + ".get()";
	final call = switch actual.getName() {
		case "box": "hxhx::managed::boxInt64(" + input.heap + ", " + first + ".asInteger(), " + roots[1] + ".get().asInteger())";
		case "high": "hxhx::managed::Value::integer(hxhx::managed::int64High(" + first + "))";
		case "low": "hxhx::managed::Value::integer(hxhx::managed::int64Low(" + first + "))";
		case "isValue": "hxhx::managed::Value::boolean(hxhx::managed::isInt64Value(" + first + "))";
		case _: throw "unselected Int64 storage operation";
	};
	lines.push(indent + "  " + (input.destination == null ? "(void)" + call : input.destination + ".set(" + call + ")") + ";");
	lines.push(indent + "}");
	return lines;
}
