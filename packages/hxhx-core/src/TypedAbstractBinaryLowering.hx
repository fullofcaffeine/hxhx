import haxe.ds.StringMap;
import TypedExpr.TypedExprTag;

private typedef TypedBinaryPlace = {
	final prefix:Array<TypedExpr>;
	final read:TyType->TypedExpr;
	final write:TypedExpr->TypedExpr;
};

private typedef TypedOrderedBinaryValues = {
	final prefix:Array<TypedExpr>;
	final left:TypedExpr;
	final right:TypedExpr;
};

private typedef TypedBinaryInlineBodyState = {
	final expressions:Array<TypedExpr>;
	var returned:Bool;
	var returnedValue:Bool;
};

/** Supplies deterministic temporary names during one binary lowering pass. **/
private class TypedBinaryLoweringCounter {
	public var value(default, null):Int;

	public function new() {
		value = 0;
	}

	public function next():Int {
		final current = value;
		value++;
		return current;
	}
}

/**
	Eliminates bound abstract binary operations from shared typed bodies.

	Every selected declaration becomes an exact call, a declaration-authorized
	carrier operation, or an explicit inline block. Source operands are evaluated
	left-to-right before a commutative call reverses argument order. Explicit
	compound helpers do not receive invented writeback; only Haxe's fallback from
	`a op= b` to `a = a op b` uses shared place analysis and an explicit write.

	This is a semantic Haxe lowering pass, not a target IR. Backends choose only
	representation and syntax for the resulting calls, temporaries, assignments,
	and ordinary binary operations.
**/
class TypedAbstractBinaryLowering {
	static function voidType():TyType
		return TyType.fromHintText("Void");

	static function helperKey(declaration:TyDeclarationInfo):String
		return declaration.getIdentity().getCanonicalKey();

	static function freshName(prefix:String, counter:TypedBinaryLoweringCounter):String {
		final value = counter.next();
		return "__hxhx_abstract_binary_" + prefix + "_" + value;
	}

	static function convert(expression:TypedExpr, expected:TyType, filePath:String, declaration:TyDeclarationInfo):TypedExpr {
		final actual = expression.getType();
		if (actual.getSemanticKey() == expected.getSemanticKey())
			return expression.withType(expected);
		if (expected.getSemanticKey() == "dynamic" || (expected.getDisplay() == "Float" && actual.getDisplay() == "Int"))
			return TypedExpr.castValue(expression, expected.getDisplay(), expected, expression.getPosition());
		throw new TyperError(filePath, expression.getPosition() == null ? HxPos.unknown() : expression.getPosition(),
			"Unsupported abstract binary conversion from "
			+ actual.getDisplay()
			+ " to "
			+ expected.getDisplay()
			+ " for "
			+ declaration.getIdentity().getCanonicalKey());
	}

	static function semanticResult(expression:TypedExpr, resultType:TyType):TypedExpr {
		return resultType.getNominalIdentity() == null ? expression : TypedExpr.castValue(expression, resultType.getDisplay(), resultType,
			expression.getPosition());
	}

	static function orderedValues(left:TypedExpr, right:TypedExpr, counter:TypedBinaryLoweringCounter):TypedOrderedBinaryValues {
		final leftName = freshName("left", counter);
		final rightName = freshName("right", counter);
		return {
			prefix: [
				TypedExpr.temporary(leftName, left.getType().getDisplay(), left, voidType(), left.getPosition()),
				TypedExpr.temporary(rightName, right.getType().getDisplay(), right, voidType(), right.getPosition())
			],
			left: TypedExpr.localRead(leftName, left.getType(), left.getPosition()),
			right: TypedExpr.localRead(rightName, right.getType(), right.getPosition())
		};
	}

	static function directPlace(target:TypedExpr):TypedBinaryPlace {
		return {
			prefix: [],
			read: function(type:TyType) return target.withType(type),
			write: function(value:TypedExpr) return TypedExpr.assign(target, value, value.getType(), target.getPosition())
		};
	}

	static function accessorDeclaration(owner:TyNominalInfo, name:String, arity:Int):Null<TyDeclarationInfo> {
		var selected:Null<TyDeclarationInfo> = null;
		for (signature in owner.instanceMethodCandidates(name)) {
			if (signature.getArgs().length != arity)
				continue;
			final declaration = owner.declarationForSignature(signature);
			if (declaration == null || selected != null)
				return null;
			selected = declaration;
		}
		return selected;
	}

	static function propertyPlaceFor(target:TypedExpr, index:TyperIndex, filePath:String, position:HxPos,
			counter:TypedBinaryLoweringCounter):Null<TypedBinaryPlace> {
		if (target.getTag() != TypedExprTag.FieldRead)
			return null;
		final texts = target.getTexts();
		final children = target.getExpressions();
		if (texts.length != 1 || children.length != 1)
			return null;
		final receiver = children[0];
		final receiverIdentity = receiver.getType().getNominalIdentity();
		final owner = receiverIdentity == null ? null : index.getByFullName(receiverIdentity.getCanonicalName());
		final property = owner == null ? null : owner.propertyInfo(texts[0]);
		if (property == null || !property.usesExplicitAccessors())
			return null;
		if (property.getIsStatic())
			throw new TyperError(filePath, position, "Static abstract compound properties are not supported yet: " + owner.getFullName() + "." + texts[0]);
		if (!property.hasExplicitGetter() || !property.hasExplicitSetter())
			throw new TyperError(filePath, position,
				"Abstract compound property requires explicit get and set accessors: "
				+ owner.getFullName()
				+ "."
				+ texts[0]);
		final getter = accessorDeclaration(owner, property.getGetterName(), 0);
		final setter = accessorDeclaration(owner, property.getSetterName(), 1);
		if (getter == null || setter == null)
			throw new TyperError(filePath, position,
				"Abstract compound property requires one exact getter and setter declaration: "
				+ owner.getFullName()
				+ "."
				+ texts[0]);

		final receiverName = freshName("property_receiver", counter);
		final prefix = [
			TypedExpr.temporary(receiverName, receiver.getType().getDisplay(), receiver, voidType(), receiver.getPosition())
		];
		function receiverRead():TypedExpr
			return TypedExpr.localRead(receiverName, receiver.getType(), receiver.getPosition());
		function accessorCall(declaration:TyDeclarationInfo, arguments:Array<TypedExpr>, resultType:TyType):TypedExpr {
			final callee = TypedExpr.fieldRead(receiverRead(), declaration.getSignature().getName(), TyType.unknown(), target.getPosition());
			return TypedExpr.call(callee, arguments, declaration, resultType, target.getPosition());
		}
		return {
			prefix: prefix,
			read: function(type:TyType) {
				final call = accessorCall(getter, [], getter.getSignature().getReturnType());
				return call.getType()
					.getSemanticKey() == type.getSemanticKey() ? call : TypedExpr.castValue(call, type.getDisplay(), type, call.getPosition());
			},
			write: function(value:TypedExpr) return accessorCall(setter, [value], setter.getSignature().getReturnType())
		};
	}

	static function placeFor(target:TypedExpr, index:TyperIndex, filePath:String, position:HxPos, counter:TypedBinaryLoweringCounter):TypedBinaryPlace {
		if (target.getTag() == TypedExprTag.LocalRead || target.getTag() == TypedExprTag.NameRead)
			return directPlace(target);
		final property = propertyPlaceFor(target, index, filePath, position, counter);
		if (property != null)
			return property;
		return switch (target.getTag()) {
			case FieldRead:
				final texts = target.getTexts();
				final children = target.getExpressions();
				final receiver = children[0];
				final receiverName = freshName("receiver", counter);
				final prefix = [
					TypedExpr.temporary(receiverName, receiver.getType().getDisplay(), receiver, voidType(), receiver.getPosition())
				];
				function field(type:TyType):TypedExpr {
					final receiverRead = TypedExpr.localRead(receiverName, receiver.getType(), receiver.getPosition());
					return TypedExpr.fieldRead(receiverRead, texts[0], type, target.getPosition());
				}
				{
					prefix: prefix,
					read: field,
					write: function(value:TypedExpr) return TypedExpr.assign(field(target.getType()), value, value.getType(), target.getPosition())
				};
			case ArrayAccess:
				final children = target.getExpressions();
				final array = children[0];
				final arrayIndex = children[1];
				final arrayName = freshName("array", counter);
				final indexName = freshName("index", counter);
				final prefix = [
					TypedExpr.temporary(arrayName, array.getType().getDisplay(), array, voidType(), array.getPosition()),
					TypedExpr.temporary(indexName, arrayIndex.getType().getDisplay(), arrayIndex, voidType(), arrayIndex.getPosition())
				];
				function access(type:TyType):TypedExpr {
					return TypedExpr.arrayAccess(TypedExpr.localRead(arrayName, array.getType(), array.getPosition()),
						TypedExpr.localRead(indexName, arrayIndex.getType(), arrayIndex.getPosition()), type, target.getPosition());
				}
				{
					prefix: prefix,
					read: access,
					write: function(value:TypedExpr) return TypedExpr.assign(access(target.getType()), value, value.getType(), target.getPosition())
				};
			case _:
				throw new TyperError(filePath, position, "Abstract compound operator requires an assignable local, field, property, or array element");
		};
	}

	static function callArguments(binding:TyBoundAbstractBinaryOperator, sourceLeft:TypedExpr, sourceRight:TypedExpr, filePath:String):Array<TypedExpr> {
		final info = binding.getOperatorInfo();
		final declaration = info.getDeclaration();
		final convertedLeft = convert(sourceLeft, binding.getSourceLeftParameterType(), filePath, declaration);
		final convertedRight = convert(sourceRight, binding.getSourceRightParameterType(), filePath, declaration);
		return binding.getReverseArguments() ? [convertedRight, convertedLeft] : [convertedLeft, convertedRight];
	}

	static function staticCall(binding:TyBoundAbstractBinaryOperator, left:TypedExpr, right:TypedExpr, index:TyperIndex, filePath:String,
			counter:TypedBinaryLoweringCounter):TypedExpr {
		final info = binding.getOperatorInfo();
		final declaration = info.getDeclaration();
		final ordered = orderedValues(left, right, counter);
		final owner = index.getByFullName(declaration.getOwner().getCanonicalName());
		final ownerName = owner == null ? declaration.getOwner().getCanonicalName() : owner.getShortName();
		final calleeOwner = TypedExpr.nameRead(ownerName, TyType.nominal(declaration.getOwner(), [], ownerName), left.getPosition());
		final callee = TypedExpr.fieldRead(calleeOwner, declaration.getSignature().getName(), TyType.unknown(), left.getPosition());
		final call = TypedExpr.call(callee, callArguments(binding, ordered.left, ordered.right, filePath), declaration, info.getResultType(),
			left.getPosition());
		final expressions = ordered.prefix.copy();
		expressions.push(semanticResult(call, info.getResultType()));
		return TypedExpr.block(expressions, info.getResultType(), left.getPosition());
	}

	static function instanceCall(binding:TyBoundAbstractBinaryOperator, left:TypedExpr, right:TypedExpr, filePath:String,
			counter:TypedBinaryLoweringCounter):TypedExpr {
		final info = binding.getOperatorInfo();
		final declaration = info.getDeclaration();
		final ordered = orderedValues(left, right, counter);
		final callArgs = callArguments(binding, ordered.left, ordered.right, filePath);
		// callArguments has already restored declaration order after any
		// commutative source reversal. An instance declaration always receives its
		// owning abstract as the first entry and its explicit argument second.
		final receiver = callArgs[0];
		final argument = callArgs[1];
		final callee = TypedExpr.fieldRead(receiver, declaration.getSignature().getName(), TyType.unknown(), left.getPosition());
		final call = TypedExpr.call(callee, [argument], declaration, info.getResultType(), left.getPosition());
		final expressions = ordered.prefix.copy();
		expressions.push(semanticResult(call, info.getResultType()));
		return TypedExpr.block(expressions, info.getResultType(), left.getPosition());
	}

	static function carrierType(type:TyType, index:TyperIndex):TyType {
		final identity = type == null ? null : type.getNominalIdentity();
		final info = identity == null ? null : index.getAbstractByFullName(identity.getCanonicalName());
		return info == null ? type : info.getUnderlyingType();
	}

	static function carrierValue(expression:TypedExpr, declaredType:TyType, index:TyperIndex):TypedExpr {
		final carrier = carrierType(declaredType, index);
		return carrier.getSemanticKey() == expression.getType()
			.getSemanticKey() ? expression.withType(carrier) : TypedExpr.castValue(expression, carrier.getDisplay(), carrier, expression.getPosition());
	}

	static function nativeBinaryType(op:String, left:TyType, right:TyType, result:TyType, declaration:TyDeclarationInfo, filePath:String):TyType {
		if (op == "+" && left.getDisplay() == "String" && right.getDisplay() == "String")
			return TyType.fromHintText("String");
		if ((op == "+" || op == "-" || op == "*" || op == "/" || op == "%") && left.isNumeric() && right.isNumeric())
			return left.getDisplay() == "Float"
				|| right.getDisplay() == "Float" ? TyType.fromHintText("Float") : TyType.fromHintText("Int");
		if ((op == "&" || op == "|" || op == "^" || op == "<<" || op == ">>" || op == ">>>")
			&& left.getDisplay() == "Int"
			&& right.getDisplay() == "Int")
			return TyType.fromHintText("Int");
		if ((op == "==" || op == "!=" || op == "<" || op == "<=" || op == ">" || op == ">=")
			&& (left.getSemanticKey() == right.getSemanticKey() || (left.isNumeric() && right.isNumeric())))
			return TyType.fromHintText("Bool");
		throw new TyperError(filePath, declaration.getPosition(),
			"Bodyless abstract binary operator requires compatible primitive carriers: "
			+ declaration.getIdentity().getCanonicalKey()
			+ " uses "
			+ left.getDisplay()
			+ " and "
			+ right.getDisplay()
			+ " for result "
			+ result.getDisplay());
	}

	static function nativeBodylessValue(binding:TyBoundAbstractBinaryOperator, left:TypedExpr, right:TypedExpr, index:TyperIndex, filePath:String,
			counter:TypedBinaryLoweringCounter):TypedExpr {
		final info = binding.getOperatorInfo();
		final declaration = info.getDeclaration();
		if (info.getResultType().isUnknown() || info.getResultType().isVoid())
			throw new TyperError(filePath, declaration.getPosition(),
				"Bodyless abstract binary operator requires an explicit value result: " + declaration.getIdentity().getCanonicalKey());
		final ordered = orderedValues(left, right, counter);
		final arguments = callArguments(binding, ordered.left, ordered.right, filePath);
		final carrierLeft = carrierValue(arguments[0], info.getLeftType(), index);
		final carrierRight = carrierValue(arguments[1], info.getRightType(), index);
		final resultCarrier = carrierType(info.getResultType(), index);
		final nativeType = nativeBinaryType(info.getOperator(), carrierLeft.getType(), carrierRight.getType(), resultCarrier, declaration, filePath);
		final operation = TypedExpr.binary(info.getOperator(), carrierLeft, carrierRight, nativeType, left.getPosition());
		final result = resultCarrier.getSemanticKey() == nativeType.getSemanticKey() ? operation : TypedExpr.castValue(operation, resultCarrier.getDisplay(),
			resultCarrier, left.getPosition());
		final expressions = ordered.prefix.copy();
		expressions.push(info.getResultType()
			.getSemanticKey() == result.getType()
			.getSemanticKey() ? result : TypedExpr.castValue(result, info.getResultType().getDisplay(), info.getResultType(), left.getPosition()));
		return TypedExpr.block(expressions, info.getResultType(), left.getPosition());
	}

	static function fallbackWriteback(binding:TyBoundAbstractBinaryOperator, left:TypedExpr, right:TypedExpr, index:TyperIndex, filePath:String,
			counter:TypedBinaryLoweringCounter):TypedExpr {
		final info = binding.getOperatorInfo();
		final declaration = info.getDeclaration();
		final place = placeFor(left, index, filePath, left.getPosition() == null ? HxPos.unknown() : left.getPosition(), counter);
		final expressions = place.prefix.copy();
		final currentName = freshName("current", counter);
		expressions.push(TypedExpr.temporary(currentName, left.getType().getDisplay(), place.read(left.getType()), voidType(), left.getPosition()));
		final rightName = freshName("right", counter);
		expressions.push(TypedExpr.temporary(rightName, right.getType().getDisplay(), right, voidType(), right.getPosition()));
		final currentRead = TypedExpr.localRead(currentName, left.getType(), left.getPosition());
		final rightRead = TypedExpr.localRead(rightName, right.getType(), right.getPosition());
		final owner = index.getByFullName(declaration.getOwner().getCanonicalName());
		final ownerName = owner == null ? declaration.getOwner().getCanonicalName() : owner.getShortName();
		final callArgs = callArguments(binding, currentRead, rightRead, filePath);
		final call = if (declaration.getIsStatic()) {
			final calleeOwner = TypedExpr.nameRead(ownerName, TyType.nominal(declaration.getOwner(), [], ownerName), left.getPosition());
			final callee = TypedExpr.fieldRead(calleeOwner, declaration.getSignature().getName(), TyType.unknown(), left.getPosition());
			TypedExpr.call(callee, callArgs, declaration, info.getResultType(), left.getPosition());
		} else {
			final receiver = callArgs[0];
			final argument = callArgs[1];
			final callee = TypedExpr.fieldRead(receiver, declaration.getSignature().getName(), TyType.unknown(), left.getPosition());
			TypedExpr.call(callee, [argument], declaration, info.getResultType(), left.getPosition());
		};
		final resultName = freshName("result", counter);
		final resultValue = convert(semanticResult(call, info.getResultType()), left.getType(), filePath, declaration);
		expressions.push(TypedExpr.temporary(resultName, left.getType().getDisplay(), resultValue, voidType(), left.getPosition()));
		final resultRead = TypedExpr.localRead(resultName, left.getType(), left.getPosition());
		expressions.push(place.write(resultRead));
		expressions.push(resultRead);
		return TypedExpr.block(expressions, left.getType(), left.getPosition());
	}

	static function nativeBodylessCompound(binding:TyBoundAbstractBinaryOperator, left:TypedExpr, right:TypedExpr, index:TyperIndex, filePath:String,
			counter:TypedBinaryLoweringCounter):TypedExpr {
		final info = binding.getOperatorInfo();
		final declaration = info.getDeclaration();
		final baseOp = HxBinaryOperatorTools.baseOperator(binding.getSourceOperator());
		if (baseOp == null)
			return nativeBodylessValue(binding, left, right, index, filePath, counter);
		final place = placeFor(left, index, filePath, left.getPosition() == null ? HxPos.unknown() : left.getPosition(), counter);
		final expressions = place.prefix.copy();
		final currentName = freshName("native_current", counter);
		expressions.push(TypedExpr.temporary(currentName, left.getType().getDisplay(), place.read(left.getType()), voidType(), left.getPosition()));
		final rightName = freshName("native_right", counter);
		expressions.push(TypedExpr.temporary(rightName, right.getType().getDisplay(), right, voidType(), right.getPosition()));
		final callArgs = callArguments(binding, TypedExpr.localRead(currentName, left.getType(), left.getPosition()),
			TypedExpr.localRead(rightName, right.getType(), right.getPosition()), filePath);
		final carrierLeft = carrierValue(callArgs[0], info.getLeftType(), index);
		final carrierRight = carrierValue(callArgs[1], info.getRightType(), index);
		final resultCarrier = carrierType(info.getResultType(), index);
		final nativeType = nativeBinaryType(baseOp, carrierLeft.getType(), carrierRight.getType(), resultCarrier, declaration, filePath);
		final operation = TypedExpr.binary(baseOp, carrierLeft, carrierRight, nativeType, left.getPosition());
		final semanticValue = convert(TypedExpr.castValue(operation, info.getResultType().getDisplay(), info.getResultType(), left.getPosition()),
			left.getType(), filePath, declaration);
		final resultName = freshName("native_result", counter);
		expressions.push(TypedExpr.temporary(resultName, left.getType().getDisplay(), semanticValue, voidType(), left.getPosition()));
		final resultRead = TypedExpr.localRead(resultName, left.getType(), left.getPosition());
		expressions.push(place.write(resultRead));
		expressions.push(resultRead);
		return TypedExpr.block(expressions, left.getType(), left.getPosition());
	}

	static function substituteExpression(expression:TypedExpr, place:TypedBinaryPlace, parameters:StringMap<TypedExpr>,
			renamedLocals:StringMap<String>):TypedExpr {
		final children = expression.getExpressions();
		return switch (expression.getTag()) {
			case ThisValue:
				place.read(expression.getType());
			case LocalRead:
				final texts = expression.getTexts();
				final renamed = renamedLocals.get(texts[0]);
				if (renamed != null) TypedExpr.localRead(renamed, expression.getType(), expression.getPosition()); else {
					final parameter = parameters.get(texts[0]);
					parameter == null ? expression : parameter;
				}
			case Assign if (children.length == 2 && children[0].getTag() == TypedExprTag.ThisValue):
				place.write(substituteExpression(children[1], place, parameters, renamedLocals));
			case CompoundAssign if (children.length == 2 && children[0].getTag() == TypedExprTag.ThisValue):
				final texts = expression.getTexts();
				TypedExpr.compoundAssign(texts[0], place.read(children[0].getType()), substituteExpression(children[1], place, parameters, renamedLocals),
					children[0].getType(), expression.getPosition());
			case _:
				expression.withExpressions([
					for (child in children)
						substituteExpression(child, place, parameters, renamedLocals)
				]);
		};
	}

	static function lowerInlineStatements(statements:Array<TypedStmt>, place:TypedBinaryPlace, parameters:StringMap<TypedExpr>,
			renamedLocals:StringMap<String>, state:TypedBinaryInlineBodyState, helpers:StringMap<TypedFunction>, index:TyperIndex, filePath:String,
			counter:TypedBinaryLoweringCounter, declaration:TyDeclarationInfo):Void {
		for (statement in statements) {
			if (state.returned)
				return;
			final expressions = statement.getExpressions();
			switch (statement.getTag()) {
				case Block:
					lowerInlineStatements(statement.getStatements(), place, parameters, renamedLocals, state, helpers, index, filePath, counter, declaration);
				case Var:
					final names = statement.getNames();
					final renamed = freshName(names[0], counter);
					final initializer = expressions.length == 0 ? TypedExpr.nullValue(TyType.unknown(),
						statement.getPosition()) : lowerExpression(substituteExpression(expressions[0], place, parameters, renamedLocals), helpers, index,
							filePath, counter);
					renamedLocals.set(names[0], renamed);
					state.expressions.push(TypedExpr.temporary(renamed, names.length > 1 ? names[1] : "", initializer, voidType(), statement.getPosition()));
				case Expression:
					state.expressions.push(lowerExpression(substituteExpression(expressions[0], place, parameters, renamedLocals), helpers, index, filePath,
						counter));
				case Return:
					state.expressions.push(lowerExpression(substituteExpression(expressions[0], place, parameters, renamedLocals), helpers, index, filePath,
						counter));
					state.returned = true;
					state.returnedValue = true;
				case ReturnVoid:
					state.returned = true;
				case _:
					throw new TyperError(filePath, declaration.getPosition(),
						"Inline abstract binary helper contains unsupported typed statement "
						+ Std.string(statement.getTag())
						+ ": "
						+ declaration.getIdentity().getCanonicalKey());
			}
		}
	}

	static function inlineCall(binding:TyBoundAbstractBinaryOperator, left:TypedExpr, right:TypedExpr, helpers:StringMap<TypedFunction>, index:TyperIndex,
			filePath:String, counter:TypedBinaryLoweringCounter):TypedExpr {
		final info = binding.getOperatorInfo();
		final declaration = info.getDeclaration();
		final helper = helpers.get(helperKey(declaration));
		if (helper == null)
			throw new TyperError(filePath, left.getPosition() == null ? HxPos.unknown() : left.getPosition(),
				"Inline abstract binary helper body is outside the typed program: " + declaration.getIdentity().getCanonicalKey());
		var resultType = info.getResultType();
		final helperEnvironment = helper.getEnvironment();
		final inferredResult = helperEnvironment == null ? TyType.unknown() : helperEnvironment.getReturnType();
		if (resultType.isUnknown()) {
			if (inferredResult.isUnknown())
				throw new TyperError(filePath, declaration.getPosition(),
					"Inline abstract binary helper result could not be inferred: " + declaration.getIdentity().getCanonicalKey());
			resultType = inferredResult;
		} else if (!inferredResult.isUnknown() && TyType.unify(resultType, inferredResult) == null) {
			throw new TyperError(filePath, declaration.getPosition(),
				"Inline abstract binary helper result conflicts with its declaration: " + declaration.getIdentity().getCanonicalKey());
		}

		final receiver = binding.getReverseArguments() ? right : left;
		final argument = binding.getReverseArguments() ? left : right;
		final place = placeFor(receiver, index, filePath, receiver.getPosition() == null ? HxPos.unknown() : receiver.getPosition(), counter);
		final prefix = new Array<TypedExpr>();
		final argumentName = freshName("argument", counter);
		final expectedArgumentType = binding.getReverseArguments() ? info.getLeftType() : info.getRightType();
		final convertedArgument = convert(argument, expectedArgumentType, filePath, declaration);
		if (binding.getReverseArguments()) {
			prefix.push(TypedExpr.temporary(argumentName, expectedArgumentType.getDisplay(), convertedArgument, voidType(), argument.getPosition()));
			for (entry in place.prefix)
				prefix.push(entry);
		} else {
			for (entry in place.prefix)
				prefix.push(entry);
			prefix.push(TypedExpr.temporary(argumentName, expectedArgumentType.getDisplay(), convertedArgument, voidType(), argument.getPosition()));
		}
		final parameterNames = declaration.getSignature().getArgNames();
		if (parameterNames.length != 1)
			throw new TyperError(filePath, declaration.getPosition(),
				"Inline abstract binary helper lost its explicit parameter: " + declaration.getIdentity().getCanonicalKey());
		final parameters = new StringMap<TypedExpr>();
		parameters.set(parameterNames[0], TypedExpr.localRead(argumentName, expectedArgumentType, argument.getPosition()));
		final state:TypedBinaryInlineBodyState = {expressions: prefix, returned: false, returnedValue: false};
		lowerInlineStatements(helper.getBody().getStatements(), place, parameters, new StringMap<String>(), state, helpers, index, filePath, counter,
			declaration);
		if (!resultType.isVoid() && !state.returnedValue)
			throw new TyperError(filePath, declaration.getPosition(),
				"Inline abstract binary helper did not produce its declared result: " + declaration.getIdentity().getCanonicalKey());
		if (state.expressions.length == 0)
			state.expressions.push(TypedExpr.nullValue(resultType, left.getPosition()));
		final block = TypedExpr.block(state.expressions, resultType, left.getPosition());
		return semanticResult(block, resultType);
	}

	static function lowerExpression(expression:TypedExpr, helpers:StringMap<TypedFunction>, index:TyperIndex, filePath:String,
			counter:TypedBinaryLoweringCounter):TypedExpr {
		final loweredChildren = [
			for (child in expression.getExpressions())
				lowerExpression(child, helpers, index, filePath, counter)
		];
		final rebuilt = expression.withExpressions(loweredChildren);
		if (rebuilt.getTag() != TypedExprTag.Binary && rebuilt.getTag() != TypedExprTag.CompoundAssign)
			return rebuilt;
		final texts = rebuilt.getTexts();
		if (texts.length != 1 || loweredChildren.length != 2)
			throw "typed binary expression has an invalid structural payload";
		final left = loweredChildren[0];
		final right = loweredChildren[1];
		final selected = TyAbstractBinaryBinding.select(index, left.getType(), right.getType(), texts[0], filePath,
			rebuilt.getPosition() == null ? HxPos.unknown() : rebuilt.getPosition());
		if (selected == null)
			return rebuilt;
		if (selected.getRequiresWriteback())
			return fallbackWriteback(selected, left, right, index, filePath, counter);
		final declaration = selected.getOperatorInfo().getDeclaration();
		if (!declaration.getHasBody())
			return HxBinaryOperatorTools.isCompoundAssignment(selected.getSourceOperator()) ? nativeBodylessCompound(selected, left, right, index, filePath,
				counter) : nativeBodylessValue(selected, left, right, index, filePath, counter);
		if (declaration.getIsStatic())
			return staticCall(selected, left, right, index, filePath, counter);
		if (!declaration.getIsInline())
			return instanceCall(selected, left, right, filePath, counter);
		return inlineCall(selected, left, right, helpers, index, filePath, counter);
	}

	static function lowerStatement(statement:TypedStmt, helpers:StringMap<TypedFunction>, index:TyperIndex, filePath:String,
			counter:TypedBinaryLoweringCounter):TypedStmt {
		final expressions = [
			for (expression in statement.getExpressions())
				lowerExpression(expression, helpers, index, filePath, counter)
		];
		final statements = [
			for (child in statement.getStatements())
				lowerStatement(child, helpers, index, filePath, counter)
		];
		return statement.withChildren(expressions, statements);
	}

	static function assertNoAbstractBinaryExpression(expression:TypedExpr, index:TyperIndex, owner:String):Void {
		for (child in expression.getExpressions())
			assertNoAbstractBinaryExpression(child, index, owner);
		if (expression.getTag() != TypedExprTag.Binary && expression.getTag() != TypedExprTag.CompoundAssign)
			return;
		final texts = expression.getTexts();
		final children = expression.getExpressions();
		if (texts.length != 1 || children.length != 2)
			throw "lowered typed binary expression has an invalid structural payload in " + owner;
		if (TyAbstractBinaryBinding.permitsOrdinaryFallback(texts[0], children[0].getType(), children[1].getType()))
			return;
		for (child in children) {
			final identity = child.getType().getNominalIdentity();
			if (identity != null && index.getAbstractByFullName(identity.getCanonicalName()) != null)
				throw "abstract binary operation survived shared typed lowering in "
					+ owner
					+ ": "
					+ identity.getCanonicalName()
					+ " "
					+ texts[0];
		}
	}

	static function assertNoAbstractBinaryStatements(statements:Array<TypedStmt>, index:TyperIndex, owner:String):Void {
		for (statement in statements) {
			for (expression in statement.getExpressions())
				assertNoAbstractBinaryExpression(expression, index, owner);
			assertNoAbstractBinaryStatements(statement.getStatements(), index, owner);
		}
	}

	static function assertNoAbstractBinary(classes:Array<TypedClass>, index:TyperIndex):Void {
		for (typedClass in classes)
			for (typedFunction in typedClass.getFunctions()) {
				final owner = typedFunction.getStableIdentity();
				for (statement in typedFunction.getBody().getStatements()) {
					for (expression in statement.getExpressions())
						assertNoAbstractBinaryExpression(expression, index, owner);
					assertNoAbstractBinaryStatements(statement.getStatements(), index, owner);
				}
			}
	}

	static function collectHelpers(classes:Array<TypedClass>, helpers:StringMap<TypedFunction>):Void {
		if (classes == null)
			return;
		for (typedClass in classes)
			for (typedFunction in typedClass.getFunctions()) {
				final declaration = typedFunction.getDeclaration();
				if (declaration != null)
					helpers.set(helperKey(declaration), typedFunction);
			}
	}

	static function lowerClassesWithHelpers(classes:Array<TypedClass>, index:TyperIndex, filePath:String, helpers:StringMap<TypedFunction>):Array<TypedClass> {
		if (classes == null || index == null)
			return classes == null ? [] : classes.copy();
		final counter = new TypedBinaryLoweringCounter();
		final lowered = [
			for (typedClass in classes)
				typedClass.withFunctions([
					for (typedFunction in typedClass.getFunctions()) {
						final body = typedFunction.getBody();
						final statements = [
							for (statement in body.getStatements())
								lowerStatement(statement, helpers, index, filePath, counter)
						];
						typedFunction.withBody(new TypedFunctionBody(statements, body.getSourceFingerprint()));
					}
				])
		];
		assertNoAbstractBinary(lowered, index);
		return lowered;
	}

	/** Lower every class after its typed helper bodies are available. **/
	public static function lowerClasses(classes:Array<TypedClass>, index:TyperIndex, filePath:String):Array<TypedClass> {
		final helpers = new StringMap<TypedFunction>();
		collectHelpers(classes, helpers);
		return lowerClassesWithHelpers(classes, index, filePath, helpers);
	}

	/** Lower a complete typed program with one transient exact helper-body catalog. **/
	public static function lowerModules(modules:Array<TypedModule>, index:TyperIndex):Array<TypedModule> {
		if (modules == null || index == null)
			return modules == null ? [] : modules.copy();
		final helpers = new StringMap<TypedFunction>();
		for (typedModule in modules)
			collectHelpers(typedModule.getTypedClasses(), helpers);
		return [
			for (typedModule in modules)
				typedModule.withTypedClasses(lowerClassesWithHelpers(typedModule.getTypedClasses(), index, typedModule.getParsed().getFilePath(), helpers))
		];
	}
}
