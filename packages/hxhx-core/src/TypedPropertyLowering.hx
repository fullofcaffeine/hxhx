import TypedExpr.TypedExprTag;

/**
	Resolve ordinary class properties before a backend sees executable bodies.

	A property read becomes its exact getter call; a write returns its setter's
	result. Updates save the receiver once and preserve the old value for postfix
	expressions. Real backing-field accesses retain a shared storage marker, so
	targets do not decide whether an accessor may bypass itself from its name.
	Abstract operator selection remains with the existing abstract lowering passes.
 */
class TypedPropertyLowering {
	final index:TyperIndex;
	final filePath:String;
	final owner:TyNominalInfo;
	final functionDeclaration:Null<TyDeclarationInfo>;
	final receiverType:TyType;
	final allocator:TyCompilerTemporaryAllocator;

	function new(index:TyperIndex, filePath:String, owner:TyNominalInfo, declaration:Null<TyDeclarationInfo>, identity:String) {
		this.index = index;
		this.filePath = filePath;
		this.owner = owner;
		this.functionDeclaration = declaration;
		this.receiverType = TyType.nominal(owner.getIdentity(), [
			for (parameter in TyNominalApplication.parameterIds(owner))
				TyType.typeParameter(parameter)
		]);
		this.allocator = new TyCompilerTemporaryAllocator(identity, "typed-properties-v1", "__hxhx_property_");
	}

	function error(expression:TypedExpr, message:String):TyperError
		return new TyperError(filePath, expression.getPosition() == null ? HxPos.unknown() : expression.getPosition(), message);

	/** Only exact indexed ordinary-class fields enter this pass. */
	function property(expression:TypedExpr):Null<TyFieldInfo> {
		final field = expression.getFieldInfo();
		if (field == null || expression.getHasPropertyStorageAccess())
			return null;
		final provider = index.getByFullName(field.getOwner().getCanonicalName());
		if (!Std.isOfType(provider, TyClassInfo))
			return null;
		if (provider.fieldInfo(field.getName()) != field)
			throw error(expression, "Property field belongs to another declaration index");
		return field.getPropertyGet() == "" && field.getPropertySet() == "" ? null : field;
	}

	function inOwnerFamily(field:TyFieldInfo):Bool
		return owner.getIdentity().equals(field.getOwner()) || TyNominalAncestor.view(index, receiverType, field.getOwner()) != null;

	/** A matching accessor can reach real backing storage, but cannot invent it. */
	function access(expression:TypedExpr, writing:Bool, ?value:TypedExpr, unchecked:Bool = false, privateAccess:Bool = false):TypedExpr {
		final field = property(expression);
		if (field == null)
			return writing ? TypedExpr.assign(expression, value, value.getType(), expression.getPosition()) : expression;
		final mode = writing ? field.getPropertySet() : field.getPropertyGet();
		if (!unchecked && (mode == "never" || (mode == "null" && !privateAccess && !inOwnerFamily(field))))
			throw error(expression, "Property " + field.getName() + " cannot be accessed for " + (writing ? "writing" : "reading"));
		final accessorName = (writing ? "set_" : "get_") + field.getName();
		final bypass = functionDeclaration != null
			&& inOwnerFamily(field)
			&& functionDeclaration.getIsStatic() == field.getIsStatic()
			&& functionDeclaration.getSignature().getName() == accessorName;
		if (mode != "get" && mode != "set" || bypass) {
			if (!field.getHasStorage())
				throw error(expression, "Property " + field.getName() + " has no real backing variable; declare @:isVar to provide one");
			final storage = expression.withPropertyStorageAccess();
			return writing ? TypedExpr.assign(storage, value, value.getType(), expression.getPosition()) : storage;
		}
		final children = expression.getExpressions();
		final receiver = field.getIsStatic() ? null : children.length == 1 ? children[0] : TypedExpr.thisValue(receiverType, expression.getPosition());
		var provider = index.getByFullName(field.getOwner().getCanonicalName());
		if (receiver != null && receiver.getType().unwrapNull().getNominalIdentity() != null)
			provider = index.getByFullName(receiver.getType().unwrapNull().getNominalIdentity().getCanonicalName());
		final visited = new haxe.ds.StringMap<Bool>();
		var declaration:Null<TyDeclarationInfo> = null;
		while (provider != null) {
			final key = provider.getFullName();
			if (visited.exists(key))
				throw error(expression, "Property accessor inheritance contains a cycle");
			visited.set(key, true);
			final candidates = field.getIsStatic() ? provider.staticMethodCandidates(accessorName) : provider.instanceMethodCandidates(accessorName);
			if (candidates.length > 0) {
				if (candidates.length != 1)
					throw error(expression, "Property requires one exact accessor: " + accessorName);
				declaration = provider.declarationForSignature(candidates[0]);
				break;
			}
			// Only an indexed class owns the superclass edge used by ordinary accessors.
			final parent = Std.isOfType(provider, TyClassInfo) ? (cast provider : TyClassInfo).getSuperType() : null;
			provider = parent == null
				|| parent.getNominalIdentity() == null ? null : index.getByFullName(parent.getNominalIdentity().getCanonicalName());
		}
		if (declaration == null || provider == null)
			throw error(expression, "Property accessor is missing: " + accessorName);
		final signature = TyNominalApplication.signature(index, provider, receiver == null ? null : receiver.getType(), declaration.getSignature());
		if (signature.getArgs().length != (writing ? 1 : 0)
			|| TyAssignmentCompatibility.classify(expression.getType(), signature.getReturnType(), Unchecked) != Compatible
			|| writing
			&& TyAssignmentCompatibility.classify(signature.getArgs()[0], expression.getType(), Unchecked) != Compatible)
			throw error(expression, "Property accessor signature differs from its declared field: " + accessorName);
		final callableType = TyCallableSignature.fromDeclaration(declaration, signature).getFunctionType();
		final callee = receiver == null ? TypedExpr.staticMethodRead(accessorName, declaration, callableType, expression.getPosition(),
			true) : TypedExpr.instanceMethodRead(receiver, accessorName, declaration, callableType, expression.getPosition());
		final arguments = writing ? [convert(value, signature.getArgs()[0])] : [];
		final call = TypedExpr.call(callee, arguments, declaration, signature.getReturnType(), expression.getPosition(), receiver == null);
		return convert(call, expression.getType());
	}

	/** Keep the accessor's own input/output types visible beneath a proven property conversion. */
	function convert(value:TypedExpr, expected:TyType):TypedExpr {
		if (value.getType().getSemanticKey() == expected.getSemanticKey())
			return value;
		if (TyAssignmentCompatibility.classify(expected, value.getType(), Unchecked) != Compatible)
			throw error(value, "Property conversion is not compatible with its selected accessor");
		// Assignment does not introduce a checked-cast runtime test. Targets still
		// receive both exact types and must implement any representation conversion.
		return TypedExpr.castValue(value, "", expected, value.getPosition());
	}

	/** Read-modify-write operations save a receiver before either the getter or RHS runs. */
	function update(expression:TypedExpr, target:TypedExpr, value:TypedExpr, op:String, postfix:Bool, unchecked:Bool, privateAccess:Bool):TypedExpr {
		final prefix = new Array<TypedExpr>();
		var place = target;
		final children = target.getExpressions();
		if (!target.getFieldInfo().getIsStatic() && children.length == 1 && children[0].getTag() != SuperValue) {
			final binding = allocator.allocate("receiver", children[0].getType());
			prefix.push(TypedExpr.temporary(binding.getSourceName(), binding.getType().getDisplay(), children[0], TyType.fromHintText("Void"),
				children[0].getPosition(), binding));
			place = target.withExpressions([
				TypedExpr.localRead(binding.getSourceName(), binding.getType(), children[0].getPosition(), binding)
			]);
		}
		var before = access(place, false, null, unchecked, privateAccess);
		if (postfix) {
			final binding = allocator.allocate("before", before.getType());
			prefix.push(TypedExpr.temporary(binding.getSourceName(), binding.getType().getDisplay(), before, TyType.fromHintText("Void"),
				before.getPosition(), binding));
			before = TypedExpr.localRead(binding.getSourceName(), binding.getType(), before.getPosition(), binding);
		}
		prefix.push(access(place, true, TypedExpr.binary(op, before, value, target.getType(), expression.getPosition()), unchecked, privateAccess));
		if (postfix)
			prefix.push(before);
		return TypedExpr.block(prefix, expression.getType(), expression.getPosition());
	}

	function lower(expression:TypedExpr, unchecked:Bool = false, privateAccess:Bool = false):TypedExpr {
		final children = expression.getExpressions();
		final tag = expression.getTag();
		// A quote describes source rather than an executable access. Preserve its
		// permission node for macro inspection and later typing of expanded code.
		if (tag == MacroExpr)
			return expression;
		if (tag == PrivateAccess)
			return lower(children[0], unchecked, true);
		// Explicit untyped source permits restricted stored-field access. It does
		// not fabricate storage for a virtual property or discard accessor calls.
		final uncheckedChildren = unchecked || tag == Untyped;
		var place = children.length == 0 ? null : children[0];
		var uncheckedPlace = unchecked;
		var privatePlace = privateAccess;
		// Prefix untyped syntax can wrap the written place instead of the whole
		// assignment. Select its setter before any recursive read lowering.
		while (place != null && (place.getTag() == Untyped || place.getTag() == PrivateAccess) && place.getExpressions().length == 1) {
			uncheckedPlace = uncheckedPlace || place.getTag() == Untyped;
			privatePlace = privatePlace || place.getTag() == PrivateAccess;
			place = place.getExpressions()[0];
		}
		if ((tag == Assign || tag == CompoundAssign || tag == Unary) && place != null && property(place) != null) {
			// Rebuild the place's receiver without first turning the place into a read.
			final target = place.withExpressions([for (child in place.getExpressions()) lower(child, uncheckedPlace, privatePlace)]);
			if (tag == Assign)
				return access(target, true, lower(children[1], uncheckedChildren, privateAccess), uncheckedPlace, privatePlace);
			if (tag == CompoundAssign) {
				final op = HxBinaryOperatorTools.baseOperator(expression.getTexts()[0]);
				if (op == null)
					throw error(expression, "Property compound update requires its binary operator");
				return update(expression, target, lower(children[1], uncheckedChildren, privateAccess), op, false, uncheckedPlace, privatePlace);
			}
			final op = expression.getUnaryOperator();
			if (op == HxUnaryOperator.Increment || op == HxUnaryOperator.Decrement)
				return update(expression, target, TypedExpr.intLiteral(1, TyType.fromHintText("Int"), expression.getPosition()),
					op == HxUnaryOperator.Increment ? "+" : "-", expression.getUnaryFixity() == HxUnaryFixity.Postfix, uncheckedPlace, privatePlace);
		}
		final rebuilt = expression.withExpressions([for (child in children) lower(child, uncheckedChildren, privateAccess)]);
		return property(rebuilt) == null ? rebuilt : access(rebuilt, false, null, unchecked, privateAccess);
	}

	function statement(value:TypedStmt):TypedStmt
		return value.withChildren([for (expression in value.getExpressions()) lower(expression)], [for (child in value.getStatements()) statement(child)]);

	/** Initializers and function bodies share property selection while retaining their original source identities. */
	public static function lowerClasses(classes:Array<TypedClass>, index:TyperIndex, filePath:String):Array<TypedClass> {
		return [
			for (typedClass in classes) {
				final owner = typedClass.getSemanticInfo();
				if (owner == null) typedClass; else {
					final functions = [
						for (fn in typedClass.getFunctions()) {
							final lowering = new TypedPropertyLowering(index, filePath, owner, fn.getDeclaration(), fn.getStableIdentity());
							fn.withBody(new TypedFunctionBody([for (stmt in fn.getBody().getStatements()) lowering.statement(stmt)],
								fn.getBody().getSourceFingerprint()),
								[
									for (value in fn.getDefaults())
										new TypedFunctionDefault(value.getParameterIndex(), lowering.lower(value.getExpression()))
								]);
						}
					];
					final initializers = [
						for (initializer in typedClass.getFieldInitializers()) {
							final lowering = new TypedPropertyLowering(index, filePath, owner, null, initializer.getField().getCanonicalKey());
							new TypedFieldInitializer(initializer.getField(), lowering.lower(initializer.getExpression()));
						}
					];
					typedClass.withMembers({functions: functions, fields: typedClass.getFields(), initializers: initializers});
				}
			}
		];
	}

	public static function lowerModules(modules:Array<TypedModule>, index:TyperIndex):Array<TypedModule>
		return [
			for (module in modules)
				module.withTypedClasses(lowerClasses(module.getTypedClasses(), index, module.getParsed().getFilePath()))
		];
}
