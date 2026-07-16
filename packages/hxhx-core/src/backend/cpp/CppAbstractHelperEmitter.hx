package backend.cpp;

/**
	Emits callable helpers for direct-carrier abstracts after shared binding.

	This module owns the synthetic receiver ABI. It does not inspect `@:op`, rank
	candidates, infer mutation, or reinterpret inline operator bodies.
**/
class CppAbstractHelperEmitter {
	/** Emit one non-inline instance method with its erased receiver made explicit. **/
	public static function renderInstanceHelper(fn:HxFunctionDecl, owner:HxClassDecl, classLookup:CppClassLookup):Array<String> {
		final representation = CppAbstractRepresentation.forPrimitiveClass(owner, classLookup);
		if (representation == null)
			return [];
		final returnType = @:privateAccess CppTargetCore.cppMethodSignatureReturnType(fn, owner, classLookup);
		final scope = @:privateAccess CppTargetCore.renderScope(owner, classLookup, returnType);
		scope.erasedAbstractThisName = CppAbstractRepresentation.ERASED_THIS_NAME;
		@:privateAccess CppTargetCore.prepareFunctionScope(scope, fn);
		scope.localTypes.set(CppAbstractRepresentation.ERASED_THIS_NAME, representation.getCarrierCppType());
		scope.localTypeHints.set(CppAbstractRepresentation.ERASED_THIS_NAME, HxClassDecl.getName(owner));
		scope.localNames.set(CppAbstractRepresentation.ERASED_THIS_NAME, CppAbstractRepresentation.ERASED_THIS_NAME);
		scope.localNameCounts.set(CppAbstractRepresentation.ERASED_THIS_NAME, 1);
		final parameters = [representation.helperReceiverParameter()];
		final sourceParameters = @:privateAccess CppTargetCore.renderFunctionArgs(HxFunctionDecl.getArgs(fn), scope);
		if (sourceParameters.length > 0)
			parameters.push(sourceParameters);
		final helperName = @:privateAccess CppTargetCore.sanitizeIdentifier(HxFunctionDecl.getName(fn));
		final out = [
			"  static " + returnType + " " + helperName + "(" + parameters.join(", ") + ") {"
		];
		for (line in @:privateAccess CppTargetCore.renderHelperFunctionBody(HxFunctionDecl.getBody(fn), "    ", scope))
			out.push(line);
		out.push("  }");
		return out;
	}

	/** Render an already resolved primitive-abstract method against its direct carrier. **/
	public static function renderMethodCall(receiver:HxExpr, method:String, args:Array<HxExpr>, ?scope:CppRenderScope):Null<String> {
		final intLikeFloat = method == "toFloat" ? @:privateAccess CppTargetCore.primitiveIntLikeAbstractMethodCallExpr(receiver, method, scope) : null;
		if (intLikeFloat != null)
			return intLikeFloat;
		var cls = @:privateAccess CppTargetCore.primitiveBackedAbstractClassForExpr(receiver, scope);
		if (cls == null)
			cls = @:privateAccess CppTargetCore.primitiveBackedAbstractClassForReceiverMethod(receiver, method, scope);
		if (cls == null)
			return @:privateAccess CppTargetCore.primitiveIntLikeAbstractMethodCallExpr(receiver, method, scope);
		final ownerName = @:privateAccess CppTargetCore.sanitizeTypePath(HxClassDecl.getName(cls));
		final fn = @:privateAccess CppTargetCore.classMethodDecl(ownerName, method, false, scope);
		if (fn == null)
			return null;
		final underlying = @:privateAccess CppTargetCore.primitiveAbstractUnderlyingCppType(cls);
		if (underlying == null || underlying.length == 0)
			return null;
		if (! @:privateAccess CppTargetCore.hasFunctionMetadata(fn, "inline")) {
			final representation = CppAbstractRepresentation.forPrimitiveClass(cls, @:privateAccess CppTargetCore.lookupForScope(scope));
			if (representation == null)
				return null;
			final renderedReceiver = @:privateAccess CppTargetCore.valueExprForExpectedType(receiver, representation.getCarrierCppType(), scope);
			final parameterTypes = @:privateAccess CppTargetCore.inferredFunctionArgCppTypes(fn, cls, scope.classByName, scope.allClasses);
			final renderedArguments = @:privateAccess CppTargetCore.renderFunctionCallArgs(HxFunctionDecl.getArgs(fn), args, scope, parameterTypes);
			final helperName = @:privateAccess CppTargetCore.sanitizeIdentifier(method);
			return representation.instanceHelperCall(helperName, renderedReceiver, renderedArguments);
		}
		if (args.length != 0)
			return null;
		return @:privateAccess CppTargetCore.primitiveBackedAbstractMethodBodyExpr(receiver, fn, scope);
	}
}
