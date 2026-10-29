/**
	Select named cases from the switch input's declaration or an exact visible name.

	Nested enum payloads use substituted argument types. Structural fields and
	array items pass their declared types to child patterns. Unsupported extractor
	result types remain unresolved; a backend must not invent a constructor owner.
	Dynamic inputs have no enum owner, so their patterns use ordinary module and
	import lookup. Generic payloads at that boundary retain Dynamic arguments.
 */
function resolve(input:TyType, patterns:Array<HxSwitchPattern>, context:TyperContext, position:HxPos):Null<TypedSwitchPatterns> {
	if (patterns == null || TypedSwitchPatterns.named(patterns).length == 0)
		return null;
	final selections = new Array<Null<TypedNamedPattern>>();
	function effective(type:TyType):TyType {
		if (type == null)
			return TyType.unknown();
		while (type.isNullable())
			type = type.unwrapNull();
		return type;
	}
	function select(type:TyType, name:String, arity:Int, payload:Bool, bareWildcardSuffix:Bool = false):Null<TypedNamedPattern> {
		final inputType = effective(type);
		var identity = inputType.getNominalIdentity();
		var owner = identity == null ? null : context.getIndex().getByFullName(identity.getCanonicalName());
		final dot = name.lastIndexOf(".");
		var member = dot < 0 ? name : name.substr(dot + 1);
		if (owner == null && inputType.isDynamic()) {
			if (dot >= 0) {
				owner = context.resolveType(name.substr(0, dot));
			} else if (payload) {
				final local = context.moduleEnumConstructorMethod(name);
				final method = local == null ? context.importedStaticMethod(name) : local;
				if (method != null) {
					owner = method.getProvider();
					member = method.getMemberName();
				}
			} else {
				final local = context.moduleEnumConstructorField(name);
				final field = local == null ? context.importedStaticField(name) : local;
				if (field != null) {
					owner = context.getIndex().getByFullName(field.getOwner().getCanonicalName());
					member = field.getName();
				}
			}
			identity = owner == null ? null : owner.getIdentity();
		}
		if (owner == null)
			return null;
		if (dot >= 0) {
			final qualifier = context.resolveType(name.substr(0, dot));
			if (qualifier == null || !qualifier.getIdentity().equals(identity))
				throw new TyperError(context.getFilePath(), position, "Invalid enum pattern " + name + ": constructor belongs to another enum");
		}
		if (owner.getIsEnum()) {
			final constructors = owner.getEnumDeclaration().getConstructors();
			for (index in 0...constructors.length) {
				final constructor = constructors[index];
				if (constructor.name != member)
					continue;
				if (constructor.arity != arity
					&& (!payload || !TyEnumPatternArguments.acceptsArity(owner.staticMethod(member), arity, bareWildcardSuffix)))
					throw new TyperError(context.getFilePath(), position, "Invalid enum pattern " + name + ": constructor or payload arity differs");
				return new TypedNamedPattern(Constructor(identity, member, index, constructor.arity));
			}
			throw new TyperError(context.getFilePath(), position,
				"Invalid enum pattern "
				+ name
				+ ": constructor does not belong to "
				+ identity.getCanonicalName());
		}
		final field = owner.fieldInfo(member);
		if (arity == 0 && field != null && field.getConstant().isEnumValue())
			return new TypedNamedPattern(Constant(field));
		return null;
	}
	function visit(pattern:HxSwitchPattern, type:TyType):Void {
		switch pattern {
			case PEnumValue(name):
				selections.push(select(type, name, 0, false));
			case PEnumExtract(name, children, provenance):
				final suffix = TyEnumPatternArguments.hasWildcardSuffix(children, provenance);
				final selection = select(type, name, children.length, true, suffix);
				selections.push(selection);
				var payloadType = type;
				var payloadName = name;
				if (effective(type).isDynamic() && selection != null) {
					switch selection.getKind() {
						case Constructor(owner, member, _, _):
							final declaration = context.getIndex().getByFullName(owner.getCanonicalName());
							if (!Std.isOfType(declaration, TyClassInfo))
								throw "selected enum pattern has no enum declaration";
							final enumOwner:TyClassInfo = cast declaration;
							payloadType = TyType.nominal(owner, [for (_ in enumOwner.getTypeParameterIds()) TyType.fromHintText("Dynamic")]);
							payloadName = owner.getCanonicalName() + "." + member;
						case Constant(_):
					}
				}
				final arguments = TyEnumPatternArguments.resolve(payloadType, payloadName, children.length, context, position, suffix);
				for (index in 0...children.length)
					visit(children[index], arguments == null ? TyType.unknown() : arguments[index]);
			case PObject(names, children):
				for (index in 0...children.length)
					visit(children[index], TyStructuralFieldRead.resolve(effective(type), names[index]));
			case PArray(children):
				final container = effective(type);
				final arguments = container.getTypeArguments();
				final identity = container.getNominalIdentity();
				final name = identity == null ? container.getUnresolvedPath() : identity.getCanonicalName();
				final item = (name == "Array" || name == "haxe.Array") && arguments.length == 1 ? arguments[0] : TyType.unknown();
				for (child in children)
					visit(child, item);
			case POr(children):
				for (child in children)
					visit(child, type);
			case PGuard(child, _) | PCapture(_, child) | PUnsupportedPattern(child):
				visit(child, type);
			case PExtractor(_, child):
				visit(child, TyType.unknown());
			case PNull | PWildcard | PBool(_) | PString(_) | PInt(_) | PBind(_):
		}
	}
	for (pattern in patterns)
		visit(pattern, input);
	return new TypedSwitchPatterns(input, patterns, selections);
}
