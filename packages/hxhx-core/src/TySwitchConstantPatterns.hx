/**
	Type each constant in a switch pattern against the value it is matched with.

	Upstream Haxe 4.3.7 types a constant pattern as an expression whose expected type
	is the switch subject, or the part of the subject the pattern is nested in. So
	`case 1.5:` on an `Int` subject fails with `Float should be Int`, and `case [1.5]:`
	on an `Array<Int>` fails the same way. An Int constant still matches a Float
	subject, and a Dynamic or Any subject accepts every constant.

	Nested positions follow the subject's type: array items use the element type,
	structure fields use the field type of an anonymous subject, and enum payloads
	use the constructor's argument types. When hxhx does not know the nested type
	(an extractor result, a field of a class instance), the constant is not
	checked, so this never rejects a pattern upstream accepts.

	The message names the expected type as upstream prints it, for example
	`Float should be haxe.Int32` or `Float should be Null<Int>`.
**/
function check(subject:TyType, patterns:Array<HxSwitchPattern>, ctx:TyperContext, pos:HxPos):Void {
	if (patterns == null)
		return;
	for (pattern in patterns)
		visit(pattern, subject, ctx, pos);
}

private function visit(pattern:HxSwitchPattern, expected:Null<TyType>, ctx:TyperContext, pos:HxPos):Void {
	if (pattern == null)
		return;
	switch pattern {
		case PInt(value):
			// An Int constant also widens to Float first, as in `case 1:` on an abstract `from Float`.
			if (expected == null
				|| !known(expected)
				|| !TyValueCompatibility.accepts(ctx.getIndex(), expected, TyType.fromHintText("Float"), EFloat(value)))
				constant(expected, TyType.fromHintText("Int"), EInt(value), ctx, pos);
		case PFloat(text):
			constant(expected, TyType.fromHintText("Float"), EFloat(HxFloatPatternText.value(text)), ctx, pos);
		case PString(value):
			constant(expected, TyType.fromHintText("String"), EString(value), ctx, pos);
		case PBool(value):
			constant(expected, TyType.fromHintText("Bool"), EBool(value), ctx, pos);
		case POr(children):
			for (child in children)
				visit(child, expected, ctx, pos);
		case PCapture(_, inner) | PGuard(inner, _):
			visit(inner, expected, ctx, pos);
		case PArray(items):
			final item = arrayItem(expected);
			for (child in items)
				visit(child, item, ctx, pos);
		case PObject(names, children):
			final fields = anonymousFields(expected);
			for (index in 0...children.length)
				visit(children[index], fields != null ? fields.get(names[index]) : classField(expected, names[index], ctx.getIndex()), ctx, pos);
		case PEnumExtract(name, children, suffix):
			final arguments = expected == null ? null : TyEnumPatternArguments.resolve(expected, name, children.length, ctx, pos,
				TyEnumPatternArguments.hasWildcardSuffix(children, suffix));
			for (index in 0...children.length)
				visit(children[index], arguments == null || index >= arguments.length ? null : arguments[index], ctx, pos);
		case PExtractor(_, _) | PUnsupportedPattern(_) | PNull | PWildcard | PBind(_) | PEnumValue(_):
	}
}

/** Reject a constant whose type cannot be stored in the expected type, as `(constant : Expected)` would. */
private function constant(expected:Null<TyType>, actual:TyType, literal:HxExpr, ctx:TyperContext, pos:HxPos):Void {
	if (expected == null || !known(expected))
		return;
	if (TyValueCompatibility.accepts(ctx.getIndex(), expected, actual, literal))
		return;
	throw new TyperError(ctx.getFilePath(), pos, actual.getDisplay() + " should be " + display(expected, ctx.getIndex()));
}

/** Only a fully known, non-Dynamic type can reject a constant. */
private function known(type:TyType):Bool {
	final inner = type.unwrapNull();
	return !type.hasUnknownComponent()
		&& !type.isUnresolved()
		&& !inner.isDynamic()
		&& !inner.isTypeParameter()
		&& !inner.isOpenMethodParameter()
		&& !(inner.getNominalIdentity() != null && inner.getNominalIdentity().getCanonicalName() == "Any");
}

/**
	Print a type as upstream does: its package path and its own name, without the
	module that declares it (`haxe.Int32`, and `AInt` for an abstract declared in
	module `Main`), keeping a `Null<...>` wrapper.
**/
private function display(type:TyType, index:Null<TyperIndex>):String {
	if (type.isNullable())
		return "Null<" + display(type.unwrapNull(), index) + ">";
	final identity = type.getNominalIdentity();
	if (identity == null)
		return type.getDisplay();
	final arguments = type.getTypeArguments();
	final owner = index == null ? null : index.getByFullName(identity.getCanonicalName());
	var name = identity.getCanonicalName();
	if (owner != null) {
		final module = owner.getModulePath();
		final dot = module.lastIndexOf(".");
		name = (dot < 0 ? "" : module.substr(0, dot + 1)) + owner.getShortName();
	}
	return name + (arguments.length == 0 ? "" : "<" + [for (argument in arguments) display(argument, index)].join(", ") + ">");
}

private function arrayItem(type:Null<TyType>):Null<TyType> {
	if (type == null)
		return null;
	final container = TyAliasExpansion.revealNonNullable(type);
	final identity = container.getNominalIdentity();
	final arguments = container.getTypeArguments();
	final path = identity == null ? container.getUnresolvedPath() : identity.getCanonicalName();
	return arguments.length == 1 && path == "Array" ? arguments[0] : null;
}

/**
	The declared type of an instance field of a non-generic class, searching superclasses.
	A generic owner would need its type arguments applied, so it gives no type.
**/
private function classField(type:Null<TyType>, name:String, index:Null<TyperIndex>):Null<TyType> {
	if (type == null || index == null)
		return null;
	var current = TyAliasExpansion.revealNonNullable(type);
	final visited = new haxe.ds.StringMap<Bool>();
	while (current != null && current.getNominalIdentity() != null && current.getTypeArguments().length == 0) {
		final key = current.getNominalIdentity().getCanonicalName();
		final owner = index.getByFullName(key);
		if (owner == null
			|| visited.exists(key)
			|| !Std.isOfType(owner, TyClassInfo)
			|| TyNominalApplication.parameterIds(owner).length != 0)
			return null;
		visited.set(key, true);
		final field = owner.fieldInfo(name);
		if (field != null)
			return field.getIsStatic() ? null : field.getType();
		current = (cast owner : TyClassInfo).getSuperType();
	}
	return null;
}

private function anonymousFields(type:Null<TyType>):Null<haxe.ds.StringMap<TyType>> {
	if (type == null)
		return null;
	final structure = TyAliasExpansion.revealNonNullable(type);
	if (!structure.isAnonymous())
		return null;
	final fields = new haxe.ds.StringMap<TyType>();
	for (field in structure.getAnonymousFields())
		fields.set(field.name, field.isOptional && !field.type.isNullable() ? TyType.nullable(field.type) : field.type);
	return fields;
}
