/**
	Selects runtime class values from the same declaration context as ordinary typing.

	A lexical value shadows a class literal, but cannot change the static target of
	`is`. Source spelling is used only to query the declaration index; the result
	carries the selected canonical identity into all later compiler stages.
**/
class TypedRuntimeTypeResolver {
	static function path(expression:HxExpr):Null<String> {
		return switch (expression) {
			case EIdent(name) | EEnumValue(name): name;
			case EField(owner, name):
				final parent = path(owner);
				parent == null ? null : parent + "." + name;
			case _: null;
		};
	}

	static function hasMember(owner:Null<TyNominalInfo>, name:String):Bool
		return owner != null
			&& (owner.hasField(name) || owner.propertyInfo(name) != null || owner.staticMethod(name) != null || owner.instanceMethod(name) != null);

	/**
		Keep same-module enum values in ordinary value lookup. The declaration index
		stores nullary constructors as fields and constructors with arguments as
		methods. Either form prevents a same-spelled imported class fallback.
	**/
	static function hasModuleEnumValue(context:TyperContext, name:String):Bool {
		final index = context.getIndex();
		if (index != null)
			for (owner in index.getDeclaredByModulePath(context.getModulePath()))
				if (owner.getIsEnum() && hasMember(owner, name))
					return true;
		return false;
	}

	/** Returns no class fallback when ordinary value lookup already owns the name. */
	public static function resolve(expression:HxExpr, environment:TyFunctionEnv, context:TyperContext,
			namespace:TypedRuntimeTypeNamespace):Null<TypedRuntimeTypeTarget> {
		final name = path(expression);
		if (name == null)
			return null;
		if (namespace == ValueExpression) {
			final parts = name.split(".");
			if (environment.resolveSymbol(parts[0]) != null)
				return null;
			if (parts.length == 1) {
				if (hasMember(context.currentClass(), name)
					|| context.importedStaticField(name) != null
					|| context.importedStaticMethod(name) != null
					|| hasModuleEnumValue(context, name))
					return null;
			} else {
				final member = parts.pop();
				if (hasMember(context.resolveType(parts.join(".")), member))
					return null;
			}
		}
		final selected = context.resolveType(name);
		// Core names are language-defined. A resolved package or secondary type
		// with the same short spelling remains nominal; ordinary values won above.
		final canonical = selected == null ? name : selected.getIdentity().getCanonicalName();
		switch (canonical) {
			case "Array":
				return new TypedRuntimeTypeTarget(ArrayCore, name);
			case "String":
				return new TypedRuntimeTypeTarget(StringCore, name);
			case _:
		}
		if (selected == null)
			return null;
		if (!Std.isOfType(selected, TyClassInfo) || selected.getIsEnum()) {
			if (namespace == TypeOperand)
				throw "unsupported runtime type target: " + selected.getFullName();
			return null;
		}
		return new TypedRuntimeTypeTarget(Nominal(selected.getIdentity()), name);
	}
}
