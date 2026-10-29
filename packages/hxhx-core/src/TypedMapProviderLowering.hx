/**
	Use the selected standard-library Map implementation for collection syntax.

	JavaScript uses this provider route before ordinary abstract/inline lowering.
	Allocation therefore makes the same key-storage choice as new Map(), and
	literals, comprehensions, indexing, and methods share one object. Targets with
	their own physical Map representation do not select this pass. Parsed source
	and macro quotations remain unchanged.
 */
class TypedMapProviderLowering {
	final index:TyperIndex;
	final allocator:TyCompilerTemporaryAllocator;

	function new(index:TyperIndex, owner:String) {
		this.index = index;
		allocator = new TyCompilerTemporaryAllocator(owner, "map-providers-v1", "__hxhx_map_");
	}

	static function isMap(type:TyType):Bool {
		final identity = type.unwrapNull().getNominalIdentity();
		return identity != null && identity.getCanonicalName() == "haxe.ds.Map";
	}

	/** Preserve existing typed owners when this pass changes none of their children. */
	static function same<T>(before:Array<T>, after:Array<T>):Bool {
		if (before.length != after.length)
			return false;
		for (ordinal in 0...before.length)
			if (before[ordinal] != after[ordinal])
				return false;
		return true;
	}

	/** Keep the indexed declaration and applied callable type; spelling alone is not a call contract. */
	function call(receiver:TypedExpr, name:String, arguments:Array<TypedExpr>, result:TyType, position:Null<HxPos>):TypedExpr {
		final type = receiver.getType().unwrapNull();
		final provider = index.getAbstractByFullName("haxe.ds.Map");
		if (!isMap(type)
			|| provider == null
			|| !provider.getIdentity().equals(type.getNominalIdentity())
			|| type.getTypeArguments().length != 2
			|| type.hasUnknownComponent())
			throw "Map syntax requires its exact applied provider";
		final candidates = provider.instanceMethodCandidates(name);
		if (candidates.length != 1)
			throw "Map syntax requires one declared " + name + " method";
		final declaration = provider.declarationForSignature(candidates[0]);
		final signature = TyNominalApplication.signature(index, provider, type, candidates[0]);
		if (declaration == null || signature.getArgs().length != arguments.length)
			throw "Map syntax lost its selected method contract";
		final callable = TyCallableSignature.fromDeclaration(declaration, signature).getFunctionType();
		final converted = [
			for (ordinal in 0...arguments.length)
				convert(arguments[ordinal], signature.getArgs()[ordinal])
		];
		final callee = TypedExpr.instanceMethodRead(receiver, name, declaration, callable, position);
		final value = TypedExpr.call(callee, converted, declaration, signature.getReturnType(), position);
		return convert(value, result);
	}

	/** Declared abstract conversions execute once at their original operand position. */
	function convert(value:TypedExpr, expected:TyType):TypedExpr {
		if (value.getType().getSemanticKey() == expected.getSemanticKey())
			return value;
		final header = TyImplicitConversionPlan.select(index, expected, value.getType());
		if (header != null)
			return header.apply(value);
		final conversion = TyAbstractMethodConversion.select(index, expected, value.getType());
		if (conversion != null)
			return conversion.apply(value);
		if (TyAssignmentCompatibility.classify(expected, value.getType(), Unchecked) != Compatible)
			throw "Map syntax operand differs from its selected method type";
		return TypedExpr.castValue(value, "", expected, value.getPosition());
	}

	function save(value:TypedExpr, role:String, steps:Array<TypedExpr>):TypedExpr {
		final binding = allocator.allocate(role, value.getType());
		steps.push(TypedExpr.temporary(binding.getSourceName(), binding.getType().getDisplay(), value, TyType.fromHintText("Void"), value.getPosition(),
			binding));
		return TypedExpr.localRead(binding.getSourceName(), binding.getType(), value.getPosition(), binding);
	}

	/** One allocation precedes ordered entries or the original loop/guard control. */
	function literal(expression:TypedExpr):TypedExpr {
		final type = expression.getType();
		final position = expression.getPosition();
		final allocation = switch TyMultiTypeSelection.select(index, type) {
			case Selected(selection): new TypedMultiTypeConstruction(selection, index, [], []).apply([], type, position);
			case Rejected(reason): throw reason;
			case Ordinary: throw "Map literal requires its declared multi-type construction";
		};
		final steps = new Array<TypedExpr>();
		final result = save(allocation, "result", steps);
		final children = expression.getExpressions();
		if (children.length == 1 && children[0].getTag() == SourceFor) {
			steps.push(lower(TypedMapComprehensionLowering.insertYields(children[0], result)));
		} else {
			for (entry in children) {
				final operands = entry.getExpressions();
				if (entry.getTag() != Binary || entry.getTexts()[0] != "=>" || operands.length != 2)
					throw "Map literal requires typed key/value entries";
				steps.push(call(result, "set", [lower(operands[0]), lower(operands[1])], TyType.fromHintText("Void"), entry.getPosition()));
			}
		}
		steps.push(result);
		return TypedExpr.block(steps, type, position);
	}

	/** Reads and assignment save the receiver before the inline accessor evaluates its arguments. */
	function access(expression:TypedExpr, address:Array<TypedExpr>, assigned:Null<TypedExpr>):TypedExpr {
		final steps = new Array<TypedExpr>();
		final receiver = save(lower(address[0]), "receiver", steps);
		final arguments = [lower(address[1])];
		if (assigned != null)
			arguments.push(lower(assigned));
		steps.push(call(receiver, assigned == null ? "get" : "arrayWrite", arguments, expression.getType(), expression.getPosition()));
		return TypedExpr.block(steps, expression.getType(), expression.getPosition());
	}

	/** Indexed increments use numeric backing storage, as ordinary getter/setter properties do. */
	function increment(value:TypedExpr, expression:TypedExpr):TypedExpr {
		final applied = value.getType().unwrapNull();
		final identity = applied.getNominalIdentity();
		final info = identity == null ? null : index.getAbstractByFullName(identity.getCanonicalName());
		final carrier = info == null ? applied : TyTypeSubstitution.apply(info.getUnderlyingType(),
			TyTypeSubstitution.bind(info.getTypeParameterIds(), applied.getTypeArguments(), info.getIdentity().getCanonicalName()));
		if (!carrier.isNumeric())
			throw "Map increment requires Int or Float backing storage: "
				+ value.getType().getSemanticKey()
				+ " -> "
				+ carrier.getSemanticKey();
		// The indexed accessor owns this numeric operation. These views preserve
		// the validated backing representation without selecting value-level ++ or +.
		final needsView = value.getType().getSemanticKey() != carrier.getSemanticKey();
		final operand = needsView ? TypedExpr.castValue(value, carrier.getCanonicalDisplay(), carrier, expression.getPosition()) : value;
		final op = expression.getUnaryOperator() == HxUnaryOperator.Increment ? "+" : "-";
		final result = TypedExpr.binary(op, operand, TypedExpr.intLiteral(1, TyType.fromHintText("Int"), expression.getPosition()), carrier,
			expression.getPosition());
		return needsView ? TypedExpr.castValue(result, value.getType().getCanonicalDisplay(), value.getType(), expression.getPosition()) : result;
	}

	/** Haxe 4.3.7 saves the key first; prefix/postfix then read and write through separate receiver evaluations. */
	function update(expression:TypedExpr, place:TypedExpr):TypedExpr {
		final steps = new Array<TypedExpr>();
		final address = place.getExpressions();
		// The applied Map owns its stored value contract even when the earlier
		// general indexed-expression inference still reports Dynamic.
		final context = TypedMapLiteral.context(address[0].getType());
		if (context == null)
			throw "Map update requires its applied key and value types";
		final valueType = context.value;
		final unary = expression.getTag() == Unary;
		final sourceKey = lower(address[1]);
		// Compound access converts its saved key once before the receiver. Unary
		// access instead performs the conversion separately at get and arrayWrite.
		final key = save(unary ? sourceKey : convert(sourceKey, context.key), "key", steps);
		final receiver = save(lower(address[0]), "receiver", steps);
		final before = save(call(receiver, "get", [key], valueType, place.getPosition()), "before", steps);
		// Keep += intact so shared abstract-operator selection can distinguish it
		// from + before the accessor stores its result.
		var value = unary ? increment(before,
			expression) : TypedExpr.compoundAssign(expression.getTexts()[0], before, lower(expression.getExpressions()[1]), valueType,
				expression.getPosition());
		var destination = receiver;
		if (unary) {
			value = save(value, "after", steps);
			destination = save(lower(address[0]), "write_receiver", steps);
		}
		steps.push(call(destination, "arrayWrite", [key, value], expression.getType(), expression.getPosition()));
		if (unary && expression.getUnaryFixity() == HxUnaryFixity.Postfix)
			steps.push(before);
		return TypedExpr.block(steps, expression.getType(), expression.getPosition());
	}

	function lower(expression:TypedExpr):TypedExpr {
		if (expression.getTag() == MacroExpr)
			return expression;
		final children = expression.getExpressions();
		final tag = expression.getTag();
		if (tag == ArrayDecl && isMap(expression.getType()))
			return literal(expression);
		final place = children.length == 0 ? null : children[0];
		if (place != null && place.getTag() == ArrayAccess && isMap(place.getExpressions()[0].getType())) {
			final address = place.getExpressions();
			if (tag == Assign)
				return access(expression, address, children[1]);
			if (tag == CompoundAssign
				|| (tag == Unary
					&& (expression.getUnaryOperator() == HxUnaryOperator.Increment
						|| expression.getUnaryOperator() == HxUnaryOperator.Decrement)))
				return update(expression, place);
		}
		if (tag == ArrayAccess && isMap(children[0].getType()))
			return access(expression, children, null);
		if (tag == MapInsert)
			return call(lower(children[0]), "set", [lower(children[1]), lower(children[2])], expression.getType(), expression.getPosition());
		final rewritten = [for (child in children) lower(child)];
		return same(children, rewritten) ? expression : expression.withExpressions(rewritten);
	}

	function statement(value:TypedStmt):TypedStmt {
		final expressions = [for (expression in value.getExpressions()) lower(expression)];
		final statements = [for (child in value.getStatements()) statement(child)];
		return same(value.getExpressions(), expressions)
			&& same(value.getStatements(), statements) ? value : value.withChildren(expressions, statements);
	}

	/** Run while the index is available, before provider bodies are inlined or reference closure selects their dependencies. */
	public static function lowerClasses(classes:Array<TypedClass>, index:TyperIndex):Array<TypedClass> {
		return [
			for (owner in classes) {
				final functions = [
					for (fn in owner.getFunctions()) {
						final pass = new TypedMapProviderLowering(index, fn.getStableIdentity());
						final statements = [for (stmt in fn.getBody().getStatements()) pass.statement(stmt)];
						final defaults = [
							for (value in fn.getDefaults()) {
								final expression = pass.lower(value.getExpression());
								expression == value.getExpression() ? value : new TypedFunctionDefault(value.getParameterIndex(), expression);
							}
						];
						same(fn.getBody().getStatements(), statements)
					&& same(fn.getDefaults(), defaults) ? fn : fn.withBody(new TypedFunctionBody(statements, fn.getBody().getSourceFingerprint()), defaults);
					}
				];
				final initializers = [
					for (initializer in owner.getFieldInitializers()) {
						final pass = new TypedMapProviderLowering(index, initializer.getField().getCanonicalKey());
						final expression = pass.lower(initializer.getExpression());
						expression == initializer.getExpression() ? initializer : new TypedFieldInitializer(initializer.getField(), expression);
					}
				];
				same(owner.getFunctions(), functions)
			&& same(owner.getFieldInitializers(), initializers) ? owner : owner.withMembers({
				functions: functions,
				fields: owner.getFields(),
				initializers: initializers
			});
			}
		];
	}
}
