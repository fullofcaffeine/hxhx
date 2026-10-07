import HxTypeSyntax.HxTypeSyntaxParameter;

/** Preserve declaration discovery order while suppressing repeated type paths. */
private class SignatureDependencyPaths {
	final seen = new haxe.ds.StringMap<Bool>();
	final ordered = new Array<String>();

	public function new() {}

	public function add(path:String):Void {
		if (!seen.exists(path)) {
			seen.set(path, true);
			ordered.push(path);
		}
	}

	public function values():Array<String>
		return ordered.copy();
}

/** Collect declaration dependencies before any method signature is published. */
function declared(module:HxModuleDecl):Array<String> {
	final paths = new SignatureDependencyPaths();
	function add(path:String, bound:Array<String>):Void {
		if (path.length > 0 && bound.indexOf(path) < 0)
			paths.add(path);
	}
	function visitType(type:Null<TyType>, bound:Array<String>):Void {
		if (type == null)
			return;
		if (type.isUnresolved())
			add(type.getUnresolvedPath(), bound);
		visitType(type.getNullableInner(), bound);
		for (argument in type.getTypeArguments())
			visitType(argument, bound);
		for (argument in type.getFunctionArguments())
			visitType(argument, bound);
		visitType(type.getFunctionReturn(), bound);
		for (field in type.getAnonymousFieldTypes())
			visitType(field, bound);
	}
	function hint(text:String, bound:Array<String>):Void
		visitType(TyType.fromHintText(text), bound);
	for (declaration in HxModuleDecl.getClasses(module)) {
		final parameters = new Array<String>();
		for (entry in HxClassDecl.getMetadata(declaration))
			if (StringTools.startsWith(entry, "__hxhx_type_params="))
				for (name in entry.substr("__hxhx_type_params=".length).split(","))
					parameters.push(StringTools.trim(name));
		hint(HxClassDecl.getExtendsPath(declaration), parameters);
		for (path in HxClassDecl.getImplementsPaths(declaration).concat(HxClassDecl.getInterfaceExtendsPaths(declaration)))
			hint(path, parameters);
		for (entry in HxClassDecl.getMetadata(declaration))
			for (prefix in ["__hxhx_abstract_underlying=", "__hxhx_abstract_from=", "__hxhx_abstract_to="])
				if (StringTools.startsWith(entry, prefix))
					hint(entry.substr(prefix.length), parameters);
		for (field in HxClassDecl.getFields(declaration))
			hint(HxFieldDecl.getTypeHint(field), parameters);
		for (method in HxClassDecl.getFunctions(declaration)) {
			final metadata = HxFunctionDecl.getMetadata(method);
			final bound = parameters.concat(HxFunctionTypeParamMetadata.typeParamNames(metadata));
			for (constraint in HxFunctionTypeParamMetadata.constraints(metadata))
				for (part in HxFunctionTypeParamMetadata.constraintHints(constraint))
					hint(part, bound);
			for (argument in HxFunctionDecl.getArgs(method))
				hint(HxFunctionArg.getTypeHint(argument), bound);
			hint(HxFunctionDecl.getReturnTypeHint(method), bound);
		}
	}
	for (alias in HxModuleDecl.getTypedefs(module)) {
		final bound = [for (parameter in alias.getParameters()) parameter.name];
		visitParameters(alias.getParameters(), bound, paths);
		visitSyntax(alias.getTarget(), bound, paths);
	}
	return paths.values();
}

/** Constraints use parameter scope. Defaults use module scope, including same-name declarations. */
private function visitParameters(parameters:Array<HxTypeSyntaxParameter>, bound:Array<String>, paths:SignatureDependencyPaths):Void {
	for (parameter in parameters) {
		for (constraint in parameter.constraints)
			visitSyntax(constraint, bound, paths);
		if (parameter.defaultType != null)
			visitSyntax(parameter.defaultType, [], paths);
	}
}

/** Walk parser-owned typedef structure without interpreting it as an object literal. */
private function visitSyntax(type:HxTypeSyntax, bound:Array<String>, paths:SignatureDependencyPaths):Void {
	switch (type.getKind()) {
		case TypePath(segments, arguments):
			final path = segments.join(".");
			if (bound.indexOf(path) < 0 && TyType.fromHintText(path).isUnresolved())
				paths.add(path);
			for (argument in arguments)
				visitSyntax(argument, bound, paths);
		case GroupedType(inner):
			visitSyntax(inner, bound, paths);
		case IntersectionType(members):
			for (member in members)
				visitSyntax(member, bound, paths);
		case ArrowType(argument, result):
			visitSyntax(argument, bound, paths);
			visitSyntax(result, bound, paths);
		case FunctionType(arguments, result):
			for (argument in arguments)
				visitSyntax(argument.type, bound, paths);
			visitSyntax(result, bound, paths);
		case AnonymousType(fields, extensions):
			for (extension in extensions)
				visitSyntax(extension, bound, paths);
			for (field in fields)
				switch (field.kind) {
					case Variable(type, _, _, _): visitSyntax(type, bound, paths);
					case Method(parameters, arguments, result):
						final methodBound = bound.concat([for (parameter in parameters) parameter.name]);
						visitParameters(parameters, methodBound, paths);
						for (argument in arguments)
							visitSyntax(argument.type, methodBound, paths);
						visitSyntax(result, methodBound, paths);
				}
	}
}
