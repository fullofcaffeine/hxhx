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

	static function orderedValues(left:TypedExpr, right:TypedExpr, allocator:TyCompilerTemporaryAllocator):TypedOrderedBinaryValues {
		final leftBinding = allocator.allocate("left", left.getType());
		final rightBinding = allocator.allocate("right", right.getType());
		final leftName = leftBinding.getSourceName();
		final rightName = rightBinding.getSourceName();
		return {
			prefix: [
				TypedExpr.temporary(leftName, left.getType().getDisplay(), left, voidType(), left.getPosition(), leftBinding),
				TypedExpr.temporary(rightName, right.getType().getDisplay(), right, voidType(), right.getPosition(), rightBinding)
			],
			left: TypedExpr.localRead(leftName, left.getType(), left.getPosition(), leftBinding),
			right: TypedExpr.localRead(rightName, right.getType(), right.getPosition(), rightBinding)
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
			allocator:TyCompilerTemporaryAllocator):Null<TypedBinaryPlace> {
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

		final receiverBinding = allocator.allocate("property_receiver", receiver.getType());
		final receiverName = receiverBinding.getSourceName();
		final prefix = [
			TypedExpr.temporary(receiverName, receiver.getType().getDisplay(), receiver, voidType(), receiver.getPosition(), receiverBinding)
		];
		function receiverRead():TypedExpr
			return TypedExpr.localRead(receiverName, receiver.getType(), receiver.getPosition(), receiverBinding);
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

	static function placeFor(target:TypedExpr, index:TyperIndex, filePath:String, position:HxPos, allocator:TyCompilerTemporaryAllocator):TypedBinaryPlace {
		if (target.getTag() == TypedExprTag.LocalRead || target.getTag() == TypedExprTag.NameRead)
			return directPlace(target);
		final property = propertyPlaceFor(target, index, filePath, position, allocator);
		if (property != null)
			return property;
		return switch (target.getTag()) {
			case FieldRead:
				final texts = target.getTexts();
				final children = target.getExpressions();
				final receiver = children[0];
				final receiverBinding = allocator.allocate("receiver", receiver.getType());
				final receiverName = receiverBinding.getSourceName();
				final prefix = [
					TypedExpr.temporary(receiverName, receiver.getType().getDisplay(), receiver, voidType(), receiver.getPosition(), receiverBinding)
				];
				function field(type:TyType):TypedExpr {
					final receiverRead = TypedExpr.localRead(receiverName, receiver.getType(), receiver.getPosition(), receiverBinding);
					return TypedExpr.fieldRead(receiverRead, texts[0], type, target.getPosition(), target.getFieldInfo());
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
				final arrayBinding = allocator.allocate("array", array.getType());
				final indexBinding = allocator.allocate("index", arrayIndex.getType());
				final arrayName = arrayBinding.getSourceName();
				final indexName = indexBinding.getSourceName();
				final prefix = [
					TypedExpr.temporary(arrayName, array.getType().getDisplay(), array, voidType(), array.getPosition(), arrayBinding),
					TypedExpr.temporary(indexName, arrayIndex.getType().getDisplay(), arrayIndex, voidType(), arrayIndex.getPosition(), indexBinding)
				];
				function access(type:TyType):TypedExpr {
					return TypedExpr.arrayAccess(TypedExpr.localRead(arrayName, array.getType(), array.getPosition(), arrayBinding),
						TypedExpr.localRead(indexName, arrayIndex.getType(), arrayIndex.getPosition(), indexBinding), type, target.getPosition());
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

	static function callArguments(binding:TyBoundAbstractBinaryOperator, sourceLeft:TypedExpr, sourceRight:TypedExpr):Array<TypedExpr> {
		final convertedLeft = binding.getSourceLeftConversion().apply(sourceLeft);
		final convertedRight = binding.getSourceRightConversion().apply(sourceRight);
		return binding.getReverseArguments() ? [convertedRight, convertedLeft] : [convertedLeft, convertedRight];
	}

	static function staticCall(binding:TyBoundAbstractBinaryOperator, left:TypedExpr, right:TypedExpr, index:TyperIndex, filePath:String,
			allocator:TyCompilerTemporaryAllocator):TypedExpr {
		final info = binding.getOperatorInfo();
		final declaration = info.getDeclaration();
		final ordered = orderedValues(left, right, allocator);
		final owner = index.getByFullName(declaration.getOwner().getCanonicalName());
		final ownerName = owner == null ? declaration.getOwner().getCanonicalName() : owner.getShortName();
		final calleeOwner = TypedExpr.nameRead(ownerName, TyType.nominal(declaration.getOwner(), [], ownerName), left.getPosition());
		final callee = TypedExpr.fieldRead(calleeOwner, declaration.getSignature().getName(), TyType.unknown(), left.getPosition());
		final call = TypedExpr.call(callee, callArguments(binding, ordered.left, ordered.right), declaration, info.getResultType(), left.getPosition());
		final expressions = ordered.prefix.copy();
		expressions.push(semanticResult(call, info.getResultType()));
		return TypedExpr.block(expressions, info.getResultType(), left.getPosition());
	}

	static function instanceCall(binding:TyBoundAbstractBinaryOperator, left:TypedExpr, right:TypedExpr, filePath:String,
			allocator:TyCompilerTemporaryAllocator):TypedExpr {
		final info = binding.getOperatorInfo();
		final declaration = info.getDeclaration();
		final ordered = orderedValues(left, right, allocator);
		final callArgs = callArguments(binding, ordered.left, ordered.right);
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
		return TyAbstractNativeBinaryOperation.carrierType(type, index);
	}

	static function carrierValue(expression:TypedExpr, declaredType:TyType, index:TyperIndex):TypedExpr {
		final carrier = carrierType(declaredType, index);
		return carrier.getSemanticKey() == expression.getType()
			.getSemanticKey() ? expression.withType(carrier) : TypedExpr.castValue(expression, carrier.getDisplay(), carrier, expression.getPosition());
	}

	/** Make Haxe string-concatenation conversion explicit before target emission. **/
	static function nativeOperand(expression:TypedExpr, operationType:TyType):TypedExpr {
		if (operationType.getDisplay() == "String" && expression.getType().getDisplay() != "String") {
			final stringType = TyType.fromHintText("String");
			final owner = TypedExpr.nameRead("Std", TyType.fromHintText("Std"), expression.getPosition());
			final callee = TypedExpr.fieldRead(owner, "string", TyType.unknown(), expression.getPosition());
			return TypedExpr.call(callee, [expression], null, stringType, expression.getPosition());
		}
		return expression;
	}

	static function nativeBodylessValue(binding:TyBoundAbstractBinaryOperator, left:TypedExpr, right:TypedExpr, index:TyperIndex, filePath:String,
			allocator:TyCompilerTemporaryAllocator):TypedExpr {
		final info = binding.getOperatorInfo();
		final declaration = info.getDeclaration();
		final ordered = orderedValues(left, right, allocator);
		final arguments = callArguments(binding, ordered.left, ordered.right);
		final carrierLeft = carrierValue(arguments[0], info.getLeftType(), index);
		final carrierRight = carrierValue(arguments[1], info.getRightType(), index);
		final resultCarrier = carrierType(info.getResultType(), index);
		final nativeType = TyAbstractNativeBinaryOperation.validate(info, index, filePath);
		final operation = TypedExpr.binary(info.getOperator(), nativeOperand(carrierLeft, nativeType), nativeOperand(carrierRight, nativeType), nativeType,
			left.getPosition());
		final result = semanticResult(convert(operation, resultCarrier, filePath, declaration), info.getResultType());
		final expressions = ordered.prefix.copy();
		expressions.push(result);
		return TypedExpr.block(expressions, info.getResultType(), left.getPosition());
	}

	static function fallbackWriteback(binding:TyBoundAbstractBinaryOperator, left:TypedExpr, right:TypedExpr, index:TyperIndex, filePath:String,
			allocator:TyCompilerTemporaryAllocator):TypedExpr {
		final info = binding.getOperatorInfo();
		final declaration = info.getDeclaration();
		final place = placeFor(left, index, filePath, left.getPosition() == null ? HxPos.unknown() : left.getPosition(), allocator);
		final expressions = place.prefix.copy();
		final currentBinding = allocator.allocate("current", left.getType());
		final currentName = currentBinding.getSourceName();
		expressions.push(TypedExpr.temporary(currentName, left.getType().getDisplay(), place.read(left.getType()), voidType(), left.getPosition(),
			currentBinding));
		final rightBinding = allocator.allocate("right", right.getType());
		final rightName = rightBinding.getSourceName();
		expressions.push(TypedExpr.temporary(rightName, right.getType().getDisplay(), right, voidType(), right.getPosition(), rightBinding));
		final currentRead = TypedExpr.localRead(currentName, left.getType(), left.getPosition(), currentBinding);
		final rightRead = TypedExpr.localRead(rightName, right.getType(), right.getPosition(), rightBinding);
		final owner = index.getByFullName(declaration.getOwner().getCanonicalName());
		final ownerName = owner == null ? declaration.getOwner().getCanonicalName() : owner.getShortName();
		final callArgs = callArguments(binding, currentRead, rightRead);
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
		final resultBinding = allocator.allocate("result", left.getType());
		final resultName = resultBinding.getSourceName();
		final resultConversion = binding.getResultConversion();
		if (resultConversion == null)
			throw "abstract compound fallback lost its selected result conversion";
		final resultValue = resultConversion.apply(semanticResult(call, info.getResultType()));
		expressions.push(TypedExpr.temporary(resultName, left.getType().getDisplay(), resultValue, voidType(), left.getPosition(), resultBinding));
		final resultRead = TypedExpr.localRead(resultName, left.getType(), left.getPosition(), resultBinding);
		expressions.push(place.write(resultRead));
		expressions.push(resultRead);
		return TypedExpr.block(expressions, left.getType(), left.getPosition());
	}

	static function nativeBodylessCompound(binding:TyBoundAbstractBinaryOperator, left:TypedExpr, right:TypedExpr, index:TyperIndex, filePath:String,
			allocator:TyCompilerTemporaryAllocator):TypedExpr {
		final info = binding.getOperatorInfo();
		final declaration = info.getDeclaration();
		final baseOp = HxBinaryOperatorTools.baseOperator(binding.getSourceOperator());
		if (baseOp == null)
			return nativeBodylessValue(binding, left, right, index, filePath, allocator);
		final place = placeFor(left, index, filePath, left.getPosition() == null ? HxPos.unknown() : left.getPosition(), allocator);
		final expressions = place.prefix.copy();
		final currentBinding = allocator.allocate("native_current", left.getType());
		final currentName = currentBinding.getSourceName();
		expressions.push(TypedExpr.temporary(currentName, left.getType().getDisplay(), place.read(left.getType()), voidType(), left.getPosition(),
			currentBinding));
		final rightBinding = allocator.allocate("native_right", right.getType());
		final rightName = rightBinding.getSourceName();
		expressions.push(TypedExpr.temporary(rightName, right.getType().getDisplay(), right, voidType(), right.getPosition(), rightBinding));
		final callArgs = callArguments(binding, TypedExpr.localRead(currentName, left.getType(), left.getPosition(), currentBinding),
			TypedExpr.localRead(rightName, right.getType(), right.getPosition(), rightBinding));
		final carrierLeft = carrierValue(callArgs[0], info.getLeftType(), index);
		final carrierRight = carrierValue(callArgs[1], info.getRightType(), index);
		final resultCarrier = carrierType(info.getResultType(), index);
		final nativeType = TyAbstractNativeBinaryOperation.validate(info, index, filePath);
		final operation = TypedExpr.binary(baseOp, nativeOperand(carrierLeft, nativeType), nativeOperand(carrierRight, nativeType), nativeType,
			left.getPosition());
		final resultConversion = binding.getResultConversion();
		if (resultConversion == null)
			throw "bodyless abstract compound fallback lost its selected result conversion";
		final semanticValue = resultConversion.apply(semanticResult(convert(operation, resultCarrier, filePath, declaration), info.getResultType()));
		final resultBinding = allocator.allocate("native_result", left.getType());
		final resultName = resultBinding.getSourceName();
		expressions.push(TypedExpr.temporary(resultName, left.getType().getDisplay(), semanticValue, voidType(), left.getPosition(), resultBinding));
		final resultRead = TypedExpr.localRead(resultName, left.getType(), left.getPosition(), resultBinding);
		expressions.push(place.write(resultRead));
		expressions.push(resultRead);
		return TypedExpr.block(expressions, left.getType(), left.getPosition());
	}

	static function substituteExpression(expression:TypedExpr, place:TypedBinaryPlace, parameters:StringMap<TypedExpr>,
			renamedLocals:StringMap<TyLocalBinding>):TypedExpr {
		final children = expression.getExpressions();
		return switch (expression.getTag()) {
			case ThisValue:
				place.read(expression.getType());
			case LocalRead:
				final sourceBindings = expression.getLocalBindings();
				if (sourceBindings.length != 1)
					throw "inline abstract binary helper local read lost its exact source binding";
				final sourceIdentity = sourceBindings[0].getIdentity().getCanonicalKey();
				final renamed = renamedLocals.get(sourceIdentity);
				if (renamed != null) TypedExpr.localRead(renamed.getSourceName(), expression.getType(), expression.getPosition(), renamed); else {
					final parameter = parameters.get(sourceIdentity);
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
			renamedLocals:StringMap<TyLocalBinding>, state:TypedBinaryInlineBodyState, helpers:StringMap<TypedFunction>, index:TyperIndex, filePath:String,
			allocator:TyCompilerTemporaryAllocator, declaration:TyDeclarationInfo):Void {
		for (statement in statements) {
			if (state.returned)
				return;
			final expressions = statement.getExpressions();
			switch (statement.getTag()) {
				case Block:
					lowerInlineStatements(statement.getStatements(), place, parameters, renamedLocals, state, helpers, index, filePath, allocator, declaration);
				case Var:
					final names = statement.getNames();
					final sourceBindings = statement.getLocalBindings();
					if (sourceBindings.length != 1)
						throw "inline abstract binary helper declaration lost its exact source binding";
					final initializer = expressions.length == 0 ? TypedExpr.nullValue(TyType.unknown(),
						statement.getPosition()) : lowerExpression(substituteExpression(expressions[0], place, parameters, renamedLocals), helpers, index,
							filePath, allocator);
					final renamed = allocator.allocate(names[0], initializer.getType());
					renamedLocals.set(sourceBindings[0].getIdentity().getCanonicalKey(), renamed);
					state.expressions.push(TypedExpr.temporary(renamed.getSourceName(), names.length > 1 ? names[1] : "", initializer, voidType(),
						statement.getPosition(), renamed));
				case Expression:
					state.expressions.push(lowerExpression(substituteExpression(expressions[0], place, parameters, renamedLocals), helpers, index, filePath,
						allocator));
				case Return:
					state.expressions.push(lowerExpression(substituteExpression(expressions[0], place, parameters, renamedLocals), helpers, index, filePath,
						allocator));
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
			filePath:String, allocator:TyCompilerTemporaryAllocator):TypedExpr {
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
		final place = placeFor(receiver, index, filePath, receiver.getPosition() == null ? HxPos.unknown() : receiver.getPosition(), allocator);
		final prefix = new Array<TypedExpr>();
		final argumentConversion = binding.getReverseArguments() ? binding.getSourceLeftConversion() : binding.getSourceRightConversion();
		final expectedArgumentType = argumentConversion.getExpectedType();
		final convertedArgument = argumentConversion.apply(argument);
		final argumentBinding = allocator.allocate("argument", expectedArgumentType);
		final argumentName = argumentBinding.getSourceName();
		if (binding.getReverseArguments()) {
			prefix.push(TypedExpr.temporary(argumentName, expectedArgumentType.getDisplay(), convertedArgument, voidType(), argument.getPosition(),
				argumentBinding));
			for (entry in place.prefix)
				prefix.push(entry);
		} else {
			for (entry in place.prefix)
				prefix.push(entry);
			prefix.push(TypedExpr.temporary(argumentName, expectedArgumentType.getDisplay(), convertedArgument, voidType(), argument.getPosition(),
				argumentBinding));
		}
		final parameterNames = declaration.getSignature().getArgNames();
		final helperParameters = helperEnvironment == null ? [] : helperEnvironment.getParams();
		if (parameterNames.length != 1 || helperParameters.length != 1)
			throw new TyperError(filePath, declaration.getPosition(),
				"Inline abstract binary helper lost its explicit parameter: " + declaration.getIdentity().getCanonicalKey());
		final parameters = new StringMap<TypedExpr>();
		parameters.set(helperParameters[0].getIdentity().getCanonicalKey(),
			TypedExpr.localRead(argumentName, expectedArgumentType, argument.getPosition(), argumentBinding));
		final state:TypedBinaryInlineBodyState = {expressions: prefix, returned: false, returnedValue: false};
		lowerInlineStatements(helper.getBody().getStatements(), place, parameters, new StringMap<TyLocalBinding>(), state, helpers, index, filePath,
			allocator, declaration);
		if (!resultType.isVoid() && !state.returnedValue)
			throw new TyperError(filePath, declaration.getPosition(),
				"Inline abstract binary helper did not produce its declared result: " + declaration.getIdentity().getCanonicalKey());
		if (state.expressions.length == 0)
			state.expressions.push(TypedExpr.nullValue(resultType, left.getPosition()));
		final block = TypedExpr.block(state.expressions, resultType, left.getPosition());
		return semanticResult(block, resultType);
	}

	static function lowerExpression(expression:TypedExpr, helpers:StringMap<TypedFunction>, index:TyperIndex, filePath:String,
			allocator:TyCompilerTemporaryAllocator):TypedExpr {
		final loweredChildren = [
			for (child in expression.getExpressions())
				lowerExpression(child, helpers, index, filePath, allocator)
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
			return fallbackWriteback(selected, left, right, index, filePath, allocator);
		final declaration = selected.getOperatorInfo().getDeclaration();
		if (!declaration.getHasBody())
			return HxBinaryOperatorTools.isCompoundAssignment(selected.getSourceOperator()) ? nativeBodylessCompound(selected, left, right, index, filePath,
				allocator) : nativeBodylessValue(selected, left, right, index, filePath, allocator);
		if (declaration.getIsStatic())
			return staticCall(selected, left, right, index, filePath, allocator);
		if (!declaration.getIsInline())
			return instanceCall(selected, left, right, filePath, allocator);
		return inlineCall(selected, left, right, helpers, index, filePath, allocator);
	}

	static function lowerStatement(statement:TypedStmt, helpers:StringMap<TypedFunction>, index:TyperIndex, filePath:String,
			allocator:TyCompilerTemporaryAllocator):TypedStmt {
		final expressions = [
			for (expression in statement.getExpressions())
				lowerExpression(expression, helpers, index, filePath, allocator)
		];
		final statements = [
			for (child in statement.getStatements())
				lowerStatement(child, helpers, index, filePath, allocator)
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
		if (!HxBinaryOperatorTools.isAbstractOverloadable(texts[0]))
			return;
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
		final lowered = [
			for (typedClass in classes)
				typedClass.withFunctions([
					for (typedFunction in typedClass.getFunctions()) {
						final body = typedFunction.getBody();
						final allocator = new TyCompilerTemporaryAllocator(typedFunction.getStableIdentity(), "typed-abstract-binary-v1",
							"__hxhx_abstract_binary_");
						final statements = [
							for (statement in body.getStatements())
								lowerStatement(statement, helpers, index, filePath, allocator)
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
