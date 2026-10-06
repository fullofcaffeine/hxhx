package backend.js;

/** Compiler-owned lexical name; source locals must not shadow the binding operation. */
function helperName():String
	return "__hx_bind_method";

/** Bind only exact value reads. Direct calls and dynamic-method writes keep their receiver syntax. */
function emitValue(expression:HxExpr, scope:JsEmitScope):Null<String> {
	final occurrence = scope == null || scope.methodUses == null ? null : scope.methodUses(expression);
	if (occurrence == null || occurrence.getUse() != ValueRead)
		return null;
	return switch (expression) {
		case EField(receiver, name): helperName()
			+ "("
			+ JsExprEmitter.emit(receiver, scope)
			+ ", "
			+ JsNameMangler.quoteString(name)
			+ ")";
		case _: throw "JavaScript method value lost its exact receiver selection";
	};
}

/** An initializer's method uses belong to its own projection, even inside a constructor. */
function initializerLookup(owner:TypedBackendClassProjection, field:HxFieldDecl):Null<HxExpr->Null<TypedBackendMethodOccurrence>> {
	for (initializer in owner.getFieldInitializers())
		if (initializer.getDeclaration() == field)
			return initializer.findMethodUse;
	return null;
}

/**
	ES5 binding needs native function identity and receiver-owned storage.
	Haxe selects exact method uses; this small target primitive caches native bound
	functions using the observable Haxe JavaScript metadata protocol. A cache dies
	with its receiver. No global table keeps abandoned receiver objects alive.
**/
function emitRuntime(writer:JsWriter):Void {
	writer.writeln("var __hx_next_method_id = 0;");
	writer.writeln("function " + helperName() + "(receiver, name) {");
	writer.pushIndent();
	writer.writeln("var method = receiver[name];");
	writer.writeln("if (method == null) return null;");
	writer.writeln("var cache = Object.prototype.hasOwnProperty.call(receiver, \"hx__closures__\") ? receiver.hx__closures__ : null;");
	writer.writeln("if (cache == null) cache = receiver.hx__closures__ = {};");
	writer.writeln("var key = method.__id__;");
	writer.writeln("if (key == null) key = method.__id__ = __hx_next_method_id++;");
	writer.writeln("if (!Object.prototype.hasOwnProperty.call(cache, key)) cache[key] = method.bind(receiver);");
	writer.writeln("return cache[key];");
	writer.popIndent();
	writer.writeln("}");
}
