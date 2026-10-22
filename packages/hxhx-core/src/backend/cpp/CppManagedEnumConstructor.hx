package backend.cpp;

/**
	Construct a selected enum without executing its synthetic record-shaped body.
	The caller supplies an exact, current typed occurrence. Its applied signature
	owns payload types; the program inventory owns descriptor and constructor order.
	Each operand remains rooted until allocation publishes the complete payload.
 */
class CppManagedEnumConstructor {
	public final resultType:TyType;

	final target:{symbol:String, index:Int, arity:Int};
	final arguments:Array<HxExpr>;
	final argumentTypes:Array<TyType>;
	final parameters:Array<TyFunctionParameter>;
	final casts:Null<CppManagedCastPlan>;

	public function new(expression:HxExpr, source:TypedExpr, enums:CppManagedEnumDescriptors, resolveType:TyType->TyType, casts:Null<CppManagedCastPlan>) {
		final call = TypedExactEnumConstructorSource.decode(expression);
		final declaration = source == null ? null : source.getDeclaration();
		if (call == null
			|| source == null
			|| source.getTag() != Call
			|| declaration == null
			|| enums == null
			|| call.owner != declaration.getOwner().getCanonicalName()
			|| call.modulePath != declaration.getModulePath()
			|| call.declaration != declaration.getIdentity().getCanonicalKey()
			|| call.constructor != declaration.getSignature().getName())
			throw "managed enum construction requires its exact typed call";
		source.assertArgumentBinding();
		target = enums.constructorTarget(declaration);
		this.casts = casts;
		resultType = resolveType(source.getType());
		CppManagedClosureAbi.assertComplete(resultType);
		final resultOwner = resultType.getNominalIdentity();
		if (resultOwner == null || resultOwner.getCanonicalName() != call.owner)
			throw "managed enum construction result differs from its selected owner";
		final children = source.getExpressions();
		final callee = children[0];
		for (qualifier in callee.getExpressions())
			if (!typeQualifier(qualifier))
				throw "managed enum construction requires explicit receiver-effect lowering";
		final named = source.getNamedArguments();
		final binding = named == null ? source.getArgumentBinding() : named.getArguments();
		// Selected calls retain omitted parameters in their checked binding. The
		// source-shaped callee can describe only supplied operands of a generic call.
		final signature = TyCallableSignature.fromFunctionValue(resolveType(binding == null ? callee.getType() : binding.getFunctionType()));
		if (signature.getResultType().getSemanticKey() != resultType.getSemanticKey())
			throw "managed enum construction changed its applied result";
		parameters = signature.getParameters();
		arguments = call.arguments.copy();
		argumentTypes = binding == null ? [for (index in 1...children.length) resolveType(children[index].getType())] : TypedCallArgumentSource.types(binding)
			.map(resolveType);
		if (parameters.length != target.arity || arguments.length != argumentTypes.length || arguments.length > parameters.length)
			throw "managed enum construction changed its payload arity: " + parameters.length + "/" + target.arity + " parameters, " + arguments.length
				+ "/" + argumentTypes.length + " arguments";
		for (index in 0...parameters.length) {
			final parameter = parameters[index];
			if (parameter.isRest)
				throw "managed enum rest payload requires its container construction";
			if (index >= arguments.length) {
				if (!parameter.isOptional)
					throw "managed enum construction omitted a required payload";
			} else if (!CppManagedValueTransfer.supports(parameter.type, argumentTypes[index], casts)) {
				throw "managed enum payload requires an explicit typed conversion";
			}
		}
	}

	/** Qualifiers select a type; an ordinary value receiver cannot silently lose effects. */
	static function typeQualifier(source:TypedExpr):Bool {
		return switch source.getTag() {
			case RuntimeTypeValue: true;
			case NameRead: source.getFieldInfo() == null && source.getDeclaration() == null;
			case FieldRead:
				source.getFieldInfo() == null
				&& source.getDeclaration() == null
				&& source.getExpressions().length == 1
				&& typeQualifier(source.getExpressions()[0]);
			case _: false;
		};
	}

	/** Root operands before allocation and publish only after the complete payload exists. */
	public function render(heap:String, destination:String, renderValue:(HxExpr, String, String) -> Array<String>, indent:String):Array<String> {
		final lines = [indent + "{"];
		final values = new Array<String>();
		for (index in 0...parameters.length) {
			final root = destination + "_enum_arg" + index;
			lines.push(indent + "  hxhx::managed::Root<hxhx::managed::Value> " + root + "(" + heap + ");");
			if (index < arguments.length) {
				for (line in renderValue(arguments[index], root, indent + "  "))
					lines.push(line);
				for (line in CppManagedValueTransfer.convertRoot(parameters[index].type, argumentTypes[index], root, indent + "  ", casts))
					lines.push(line);
			}
			values.push(root + ".get()");
		}
		final payload = destination + "_enum_payload";
		lines.push(indent + "  hxhx::managed::Root<hxhx::managed::Ref<hxhx::managed::EnumPayload>> " + payload + "(" + heap + ");");
		lines.push(indent + "  " + heap + ".allocateInto(" + payload + ", " + target.symbol + ", " + target.index + ", std::vector<hxhx::managed::Value>{"
			+ values.join(", ") + "});");
		lines.push(indent + "  " + destination + ".set(hxhx::managed::Value::managed(" + payload + ".get()));");
		lines.push(indent + "}");
		return lines;
	}
}
