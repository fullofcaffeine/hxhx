package backend.cpp;

import haxe.ds.StringMap;

/**
	Visit callback uses inside lowered statement bodies without flattening scopes.
	The existing C++ expression analysis owns representation inference. This module
	supplies its lexical bindings and expected result types. Successful discoveries
	about captured arguments survive a child scope; temporary local facts do not.
**/
function control(kind:HxLoweredControlKind, children:Array<HxExpr>, scope:CppRenderScope, candidates:StringMap<Bool>, resultType:String):Void {
	switch kind {
		case Try(catches):
			visit(children[0], scope, candidates, resultType);
			for (index in 0...catches.length) {
				final name = catches[index].getName();
				bindings([name], [projectedType(name, scope)], scope, candidates, nested -> visit(children[index + 1], scope, nested, resultType));
			}
		case FunctionBody | Scope:
			CppLocalScope.inferOverrides(scope, () -> entries(children, scope, candidates.copy(), resultType));
		case Initializer(hasValue):
			CppLocalScope.inferOverrides(scope, () -> entries(children, scope, candidates.copy(), resultType, hasValue));
		case Return:
			for (child in children)
				visit(child, scope, candidates, resultType);
		case Branch | While(_):
			visit(children[0], scope, candidates, "bool");
			for (index in 1...children.length)
				visit(children[index], scope, candidates, resultType);
		case For(binding):
			visit(children[0], scope, candidates, "");
			final types = switch binding {
				case Value(_): [@:privateAccess CppTargetCore.iterableElementType(children[0], scope)];
				case KeyValue(_, _): @:privateAccess CppTargetCore.keyValueLoopTypes(children[0], scope);
			};
			bindings(HxForBinding.names(binding), types, scope, candidates, nested -> visit(children[1], scope, nested, resultType));
		case Switch(patterns):
			visit(children[0], scope, candidates, "");
			for (index in 0...patterns.length) {
				final names = new Array<String>();
				patternNames(patterns[index], names);
				// Exact projected locals own extracted types; pattern text cannot supply them.
				final types = [for (name in names) projectedType(name, scope)];
				bindings(names, types, scope, candidates, nested -> visit(children[index + 1], scope, nested, resultType));
			}
		case Throw | ArrayAppend | MapInsert:
			for (child in children)
				visit(child, scope, candidates, "");
		case Break | Continue:
	}
}

/** Parameter annotations and the selected function contract define the nested return context. */
function lambda(names:Array<String>, body:HxExpr, signature:Null<HxLambdaSignature>, scope:CppRenderScope, candidates:StringMap<Bool>,
		expectedType:String):Void {
	final parameters = signature == null ? [] : signature.getParameters();
	final expectedArguments = CppTypeModel.cppFunctionArgTypesFromCppType(expectedType);
	final types = [
		for (index in 0...names.length) {
			final hint = index < parameters.length ? parameters[index].typeHint : null;
			if (index < expectedArguments.length) expectedArguments[index]; else if (hint != null && hint.length > 0)
				parameters[index].isOptional ? CppTypeModel.cppNullableTypeHint(hint, scope) : hintType(hint, scope); else projectedType(names[index], scope);
		}
	];
	final returnHint = signature == null ? null : signature.getReturnTypeHint();
	final resultType = returnHint != null
		&& returnHint.length > 0 ? hintType(returnHint, scope) : CppTypeModel.cppFunctionReturnTypeFromCppType(expectedType);
	CppLocalScope.inferOverrides(scope, () -> bindings(names, types, scope, candidates, nested -> visit(body, scope, nested, resultType)));
}

/** Declarations take effect in order, including declarations with no callback use. */
function entries(values:Array<HxExpr>, scope:CppRenderScope, candidates:StringMap<Bool>, resultType:String, finalValue:Bool = false):Void {
	final ordered = new Array<HxExpr>();
	for (value in values)
		switch value {
			case EVars(declarations):
				for (declaration in declarations)
					ordered.push(declaration);
			case _:
				ordered.push(value);
		}
	function next(start:Int, active:StringMap<Bool>):Void {
		for (index in start...ordered.length)
			switch ordered[index] {
				case EVariableDeclaration(name, hint, initializer, _, _, _):
					final type = @:privateAccess CppTargetCore.inferredLocalTypeForArgInference(hint, initializer, scope);
					if (initializer != null)
						visit(initializer, scope, active, type);
					bindings([name], [type], scope, active, nested -> {
						scope.localTypeHints.set(name, hint);
						next(index + 1, nested);
					});
					return;
				case ELoweredControl(_, _, _, _):
					visit(ordered[index], scope, active, resultType);
				case _:
					visit(ordered[index], scope, active, finalValue && index == ordered.length - 1 ? resultType : "");
			}
	}
	next(0, candidates);
}

private function visit(value:HxExpr, scope:CppRenderScope, candidates:StringMap<Bool>, expectedType:String):Void
	@:privateAccess CppTargetCore.collectCallableArgTypeOverridesFromExpr(value, scope, candidates, expectedType);

private function hintType(hint:String, scope:CppRenderScope):String
	return @:privateAccess CppTargetCore.cppTypeHint(hint, scope);

/** Consume the typed binding selected before C++ symbol allocation. */
private function projectedType(name:String, scope:CppRenderScope):String {
	final local = CppExecutableScope.findLocal(scope, name);
	return local == null ? "" : hintType(local.getBinding().getType().getDisplay(), scope);
}

/** Shadowed argument overrides must not become facts about the new binding. */
private function bindings(names:Array<String>, types:Array<String>, scope:CppRenderScope, candidates:StringMap<Bool>, body:StringMap<Bool>->Void):Void {
	final nested = candidates.copy();
	for (name in names)
		nested.remove(name);
	function enter(index:Int):Void {
		if (index == names.length) {
			body(nested);
			return;
		}
		final name = names[index];
		CppLocalScope.withBinding(scope, name, types[index], () -> {
			scope.localTypes.set(name, types[index]);
			scope.localTypeHints.remove(name);
			scope.argTypeOverrides.remove(name);
			scope.localTypeOverrides.remove(name);
			enter(index + 1);
		});
	}
	enter(0);
}

/** Collect lexical binders only; shared typing remains responsible for pattern validity and types. */
private function patternNames(pattern:HxSwitchPattern, names:Array<String>):Void {
	function add(name:String):Void {
		if (name != "_" && names.indexOf(name) < 0)
			names.push(name);
	}
	switch pattern {
		case PBind(name):
			add(name);
		case PCapture(name, inner):
			add(name);
			patternNames(inner, names);
		case PEnumExtract(_, children) | PObject(_, children) | PArray(children) | POr(children):
			for (child in children)
				patternNames(child, names);
		case PExtractor(_, inner) | PLengthGuard(inner, _, _) | PStartsWithGuard(inner, _, _) | PIntEqualsGuard(inner, _, _) |
			PIntCompareGuard(inner, _, _, _) | PParsedIntSwitchGuard(inner, _, _, _) | PUnsupportedGuard(inner):
			patternNames(inner, names);
		case PNull | PWildcard | PBool(_) | PString(_) | PInt(_) | PEnumValue(_):
	}
}
