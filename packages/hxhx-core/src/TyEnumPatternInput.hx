/**
	Supply enum evidence for an omitted switch input before payload locals are typed.

	Only visible constructors of one exact, non-generic enum supply a complete
	context here. Generic enums still need inference variables for their arguments;
	their declaration binders must never become a caller's inferred arguments.
	Written input types and payload validation remain with the ordinary switch typer.
 */
function resolve(patterns:Array<HxSwitchPattern>, context:TyperContext, position:HxPos):Null<TyType> {
	if (patterns == null || context.getIndex() == null)
		return null;
	var selected:Null<TyType> = null;

	function accept(type:Null<TyType>):Void {
		if (type == null || type.hasUnknownComponent() || type.getTypeArguments().length != 0)
			return;
		final identity = type.getNominalIdentity();
		final owner = identity == null ? null : context.getIndex().getByFullName(identity.getCanonicalName());
		if (owner == null || !owner.getIsEnum())
			return;
		if (selected != null && selected.getSemanticKey() != type.getSemanticKey())
			throw new TyperError(context.getFilePath(), position, "switch patterns require different enum input types");
		selected = type;
	}

	function constructor(name:String, payload:Bool):Void {
		final dot = name.lastIndexOf(".");
		if (dot >= 0) {
			final owner = context.resolveType(name.substr(0, dot));
			if (owner == null || !owner.getIsEnum())
				return;
			final member = name.substr(dot + 1);
			if (payload) {
				final signature = owner.staticMethod(member);
				final declaration = signature == null ? null : owner.declarationForSignature(signature);
				if (declaration != null && declaration.getIsEnumConstructor())
					accept(signature.getReturnType());
			} else {
				final field = owner.fieldInfo(member);
				if (field != null && field.getIsStatic())
					accept(field.getType());
			}
		} else if (payload) {
			final local = context.moduleEnumConstructorMethod(name);
			final method = local == null ? context.importedStaticMethod(name) : local;
			if (method == null || !method.getProvider().getIsEnum())
				return;
			for (signature in method.getCandidates()) {
				final declaration = method.getProvider().declarationForSignature(signature);
				if (declaration != null && declaration.getIsEnumConstructor())
					accept(signature.getReturnType());
			}
		} else {
			final local = context.moduleEnumConstructorField(name);
			final field = local == null ? context.importedStaticField(name) : local;
			if (field != null)
				accept(field.getType());
		}
	}

	function visit(pattern:HxSwitchPattern):Void {
		switch (pattern) {
			case PEnumValue(name):
				constructor(name, false);
			case PEnumExtract(name, _):
				constructor(name, true);
			case POr(alternatives):
				for (alternative in alternatives)
					visit(alternative);
			case PCapture(_, inner) | PLengthGuard(inner, _, _) | PStartsWithGuard(inner, _, _) | PIntEqualsGuard(inner, _, _) |
				PIntCompareGuard(inner, _, _, _) | PParsedIntSwitchGuard(inner, _, _, _) | PUnsupportedGuard(inner):
				visit(inner);
			case _:
				// Nested payload patterns describe the payload, not the switch input.
		}
	}
	for (pattern in patterns)
		visit(pattern);
	return selected;
}
