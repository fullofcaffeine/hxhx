import haxe.ds.StringMap;
import TypedExpr.TypedExprTag;

private typedef TypedUnaryPlace = {
	final prefix:Array<TypedExpr>;
	final read:TyType->TypedExpr;
	final write:TypedExpr->TypedExpr;
};

private typedef TypedInlineBodyState = {
	final expressions:Array<TypedExpr>;
	var returned:Bool;
	var returnedValue:Bool;
};

/** Supplies deterministic temporary names during one shared lowering pass. **/
private class TypedUnaryLoweringCounter {
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
	Eliminates bound abstract unary operations from shared typed function bodies.

	Static helpers become exact calls without writeback. Non-inline instance
	helpers remain exact instance-semantic calls. Inline instance helpers are
	expanded into explicit reads, writes, temporaries, and ordered expression
	blocks. Backends therefore receive behavior that is already decided and never
	infer mutation or prefix/postfix results from spelling.

	The first supported inline subset covers local, field, and indexed places plus
	straight-line variables, expressions, assignments, and returns. Unsupported
	helper control flow fails in this shared pass instead of falling back to a
	target carrier operator.
**/
class TypedAbstractUnaryLowering {
	static function voidType():TyType
		return TyType.fromHintText("Void");

	static function helperKey(declaration:TyDeclarationInfo):String
		return declaration.getIdentity().getCanonicalKey();

	static function freshName(prefix:String, counter:TypedUnaryLoweringCounter):String {
		final value = counter.next();
		return "__hxhx_abstract_" + prefix + "_" + value;
	}

	static function directPlace(target:TypedExpr):TypedUnaryPlace {
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
			counter:TypedUnaryLoweringCounter):Null<TypedUnaryPlace> {
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
			throw new TyperError(filePath, position,
				"Static abstract property increment/decrement is not supported yet: "
				+ owner.getFullName()
				+ "."
				+ texts[0]);
		if (!property.hasExplicitGetter() || !property.hasExplicitSetter())
			throw new TyperError(filePath, position,
				"Abstract property increment/decrement requires explicit get and set accessors: "
				+ owner.getFullName()
				+ "."
				+ texts[0]);
		final getter = accessorDeclaration(owner, property.getGetterName(), 0);
		final setter = accessorDeclaration(owner, property.getSetterName(), 1);
		if (getter == null || setter == null)
			throw new TyperError(filePath, position,
				"Property update requires one exact getter and setter declaration: "
				+ owner.getFullName()
				+ "."
				+ texts[0]);

		final temporaryName = freshName("property_receiver", counter);
		final temporary = TypedExpr.temporary(temporaryName, receiver.getType().getDisplay(), receiver, voidType(), receiver.getPosition());
		function receiverRead():TypedExpr
			return TypedExpr.localRead(temporaryName, receiver.getType(), receiver.getPosition());
		function accessorCall(declaration:TyDeclarationInfo, arguments:Array<TypedExpr>, resultType:TyType):TypedExpr {
			final callee = TypedExpr.fieldRead(receiverRead(), declaration.getSignature().getName(), TyType.unknown(), target.getPosition());
			return TypedExpr.call(callee, arguments, declaration, resultType, target.getPosition());
		}
		return {
			prefix: [temporary],
			read: function(type:TyType) {
				final call = accessorCall(getter, [], getter.getSignature().getReturnType());
				return call.getType()
					.getSemanticKey() == type.getSemanticKey() ? call : TypedExpr.castValue(call, type.getDisplay(), type, call.getPosition());
			},
			write: function(value:TypedExpr) return accessorCall(setter, [value], setter.getSignature().getReturnType())
		};
	}

	static function placeFor(target:TypedExpr, filePath:String, position:HxPos, counter:TypedUnaryLoweringCounter):TypedUnaryPlace {
		final tag = target.getTag();
		if (tag == TypedExprTag.LocalRead || tag == TypedExprTag.NameRead)
			return directPlace(target);
		return switch (target.getTag()) {
			case FieldRead:
				final texts = target.getTexts();
				final children = target.getExpressions();
				final receiver = children[0];
				final temporaryName = freshName("receiver", counter);
				final temporary = TypedExpr.temporary(temporaryName, receiver.getType().getDisplay(), receiver, voidType(), receiver.getPosition());
				function field(type:TyType):TypedExpr {
					final receiverRead = TypedExpr.localRead(temporaryName, receiver.getType(), receiver.getPosition());
					return TypedExpr.fieldRead(receiverRead, texts[0], type, target.getPosition());
				}
				{
					prefix: [temporary],
					read: field,
					write: function(value:TypedExpr) return TypedExpr.assign(field(target.getType()), value, value.getType(), target.getPosition())
				};
			case ArrayAccess:
				final children = target.getExpressions();
				function access(type:TyType):TypedExpr
					return TypedExpr.arrayAccess(children[0], children[1], type, target.getPosition());
				{
					// Compatibility note: do not memoize the array/index. Haxe 4.3.7
					// observably evaluates an overloaded indexed read and write separately.
					prefix: [],
					read: access,
					write: function(value:TypedExpr) return TypedExpr.assign(access(target.getType()), value, value.getType(), target.getPosition())
				};
			case _:
				throw new TyperError(filePath, position, "Inline abstract unary operator requires an assignable local, field, or array element");
		};
	}

	static function substituteExpression(expression:TypedExpr, place:TypedUnaryPlace, renamedLocals:StringMap<String>):TypedExpr {
		final children = expression.getExpressions();
		return switch (expression.getTag()) {
			case ThisValue:
				place.read(expression.getType());
			case LocalRead:
				final texts = expression.getTexts();
				final renamed = renamedLocals.get(texts[0]);
				renamed == null ? expression : TypedExpr.localRead(renamed, expression.getType(), expression.getPosition());
			case Assign if (children.length == 2 && children[0].getTag() == TypedExprTag.ThisValue):
				place.write(substituteExpression(children[1], place, renamedLocals));
			case CompoundAssign if (children.length == 2 && children[0].getTag() == TypedExprTag.ThisValue):
				final texts = expression.getTexts();
				final compound = texts[0];
				final right = substituteExpression(children[1], place, renamedLocals);
				final carrierType = children[0].getType();
				// The compound lvalue is one observable occurrence. A separate helper
				// result read remains a second occurrence, matching measured Haxe 4.3.7
				// indexed prefix/postfix behavior without target-side memoization.
				TypedExpr.compoundAssign(compound, place.read(carrierType), right, carrierType, expression.getPosition());
			case _:
				expression.withExpressions([for (child in children) substituteExpression(child, place, renamedLocals)]);
		};
	}

	static function lowerInlineStatements(statements:Array<TypedStmt>, place:TypedUnaryPlace, renamedLocals:StringMap<String>, state:TypedInlineBodyState,
			helpers:StringMap<TypedFunction>, index:TyperIndex, filePath:String, counter:TypedUnaryLoweringCounter, declaration:TyDeclarationInfo):Void {
		for (statement in statements) {
			if (state.returned)
				return;
			final expressions = statement.getExpressions();
			switch (statement.getTag()) {
				case Block:
					lowerInlineStatements(statement.getStatements(), place, renamedLocals, state, helpers, index, filePath, counter, declaration);
				case Var:
					final names = statement.getNames();
					final renamed = freshName(names[0], counter);
					renamedLocals.set(names[0], renamed);
					final initializer = expressions.length == 0 ? TypedExpr.nullValue(TyType.unknown(),
						statement.getPosition()) : lowerExpression(substituteExpression(expressions[0], place, renamedLocals), helpers, index, filePath,
							counter);
					state.expressions.push(TypedExpr.temporary(renamed, names.length > 1 ? names[1] : "", initializer, voidType(), statement.getPosition()));
				case Expression:
					state.expressions.push(lowerExpression(substituteExpression(expressions[0], place, renamedLocals), helpers, index, filePath, counter));
				case Return:
					state.expressions.push(lowerExpression(substituteExpression(expressions[0], place, renamedLocals), helpers, index, filePath, counter));
					state.returned = true;
					state.returnedValue = true;
				case ReturnVoid:
					state.returned = true;
				case _:
					throw new TyperError(filePath, declaration.getPosition(),
						"Inline abstract unary helper contains unsupported typed statement "
						+ Std.string(statement.getTag())
						+ ": "
						+ declaration.getIdentity().getCanonicalKey());
			}
		}
	}

	static function staticCall(binding:TyAbstractOperatorInfo, operand:TypedExpr, index:TyperIndex):TypedExpr {
		final declaration = binding.getDeclaration();
		final owner = index.getByFullName(declaration.getOwner().getCanonicalName());
		final ownerName = owner == null ? declaration.getOwner().getCanonicalName() : owner.getShortName();
		final calleeOwner = TypedExpr.nameRead(ownerName, TyType.nominal(declaration.getOwner(), [], ownerName), operand.getPosition());
		final callee = TypedExpr.fieldRead(calleeOwner, declaration.getSignature().getName(), TyType.unknown(), operand.getPosition());
		final call = TypedExpr.call(callee, [operand], declaration, binding.getResultType(), operand.getPosition());
		return binding.getResultType()
			.getNominalIdentity() == null ? call : TypedExpr.castValue(call, binding.getResultType().getDisplay(), binding.getResultType(), operand.getPosition());
	}

	static function instanceCall(binding:TyAbstractOperatorInfo, operand:TypedExpr):TypedExpr {
		final declaration = binding.getDeclaration();
		final callee = TypedExpr.fieldRead(operand, declaration.getSignature().getName(), TyType.unknown(), operand.getPosition());
		final call = TypedExpr.call(callee, [], declaration, binding.getResultType(), operand.getPosition());
		return binding.getResultType()
			.getNominalIdentity() == null ? call : TypedExpr.castValue(call, binding.getResultType().getDisplay(), binding.getResultType(), operand.getPosition());
	}

	/**
		Lower an explicitly bodyless abstract declaration to the ordinary carrier
		operation authorized by that declaration. The semantic abstract remains the
		outer result type; only this operation's operand/result view uses the primitive
		carrier. This is deliberately narrower than a carrier fallback: a missing or
		body-bearing declaration never reaches this path.
	**/
	static function nativeBodylessOperation(binding:TyAbstractOperatorInfo, operand:TypedExpr, abstractInfo:TyAbstractInfo, filePath:String):TypedExpr {
		final declaration = binding.getDeclaration();
		final carrierType = abstractInfo.getUnderlyingType();
		final op = binding.getOperator();
		final supported = if (op == HxUnaryOperator.Negate || op == HxUnaryOperator.Increment || op == HxUnaryOperator.Decrement) carrierType.isNumeric() else
			if (op == HxUnaryOperator.LogicalNot) carrierType.getDisplay() == "Bool" else carrierType.getDisplay() == "Int";
		if (!supported)
			throw new TyperError(filePath, operand.getPosition(),
				"Bodyless abstract unary operator requires a compatible primitive carrier: "
				+ declaration.getIdentity().getCanonicalKey()
				+ " uses "
				+ carrierType.getDisplay());
		final resultType = binding.getResultType();
		if (resultType.isUnknown() || resultType.isVoid())
			throw new TyperError(filePath, declaration.getPosition(),
				"Bodyless abstract unary operator requires an explicit value result: " + declaration.getIdentity().getCanonicalKey());

		final carrierOperand = op == HxUnaryOperator.Increment
			|| op == HxUnaryOperator.Decrement ? operand.withType(carrierType) : TypedExpr.castValue(operand, carrierType.getDisplay(), carrierType,
				operand.getPosition());
		final carrierResult = TypedExpr.unary(op, binding.getFixity(), carrierOperand, carrierType, operand.getPosition());
		return resultType.getSemanticKey() == carrierType.getSemanticKey() ? carrierResult : TypedExpr.castValue(carrierResult, resultType.getDisplay(),
			resultType, operand.getPosition());
	}

	static function inlineCall(binding:TyAbstractOperatorInfo, operand:TypedExpr, helpers:StringMap<TypedFunction>, index:TyperIndex, filePath:String,
			counter:TypedUnaryLoweringCounter):TypedExpr {
		final declaration = binding.getDeclaration();
		final helper = helpers.get(helperKey(declaration));
		if (helper == null)
			throw new TyperError(filePath, operand.getPosition(),
				"Inline abstract unary helper body is outside the typed program: " + declaration.getIdentity().getCanonicalKey());
		var resultType = binding.getResultType();
		final helperEnvironment = helper.getEnvironment();
		final inferredResult = helperEnvironment == null ? TyType.unknown() : helperEnvironment.getReturnType();
		if (resultType.isUnknown()) {
			if (inferredResult.isUnknown())
				throw new TyperError(filePath, declaration.getPosition(),
					"Inline abstract unary helper result could not be inferred: " + declaration.getIdentity().getCanonicalKey());
			resultType = inferredResult;
		} else if (!inferredResult.isUnknown() && TyType.unify(resultType, inferredResult) == null) {
			throw new TyperError(filePath, declaration.getPosition(),
				"Inline abstract unary helper result conflicts with its declaration: " + declaration.getIdentity().getCanonicalKey());
		}
		final place = placeFor(operand, filePath, operand.getPosition(), counter);
		final state:TypedInlineBodyState = {expressions: place.prefix.copy(), returned: false, returnedValue: false};
		lowerInlineStatements(helper.getBody().getStatements(), place, new StringMap<String>(), state, helpers, index, filePath, counter, declaration);
		if (!resultType.isVoid() && !state.returnedValue)
			throw new TyperError(filePath, declaration.getPosition(),
				"Inline abstract unary helper did not produce its declared result: " + declaration.getIdentity().getCanonicalKey());
		if (state.expressions.length == 0)
			state.expressions.push(TypedExpr.nullValue(resultType, operand.getPosition()));
		final block = TypedExpr.block(state.expressions, resultType, operand.getPosition());
		return resultType.getNominalIdentity() == null ? block : TypedExpr.castValue(block, resultType.getDisplay(), resultType, operand.getPosition());
	}

	/** Lower Haxe's getter/setter prefix/postfix contract without selecting the value abstract's helper. **/
	static function propertyUpdate(expression:TypedExpr, operand:TypedExpr, abstractInfo:TyAbstractInfo, place:TypedUnaryPlace, op:HxUnaryOperator,
			fixity:HxUnaryFixity, counter:TypedUnaryLoweringCounter, filePath:String):TypedExpr {
		final resultType = operand.getType();
		final carrierType = abstractInfo.getUnderlyingType();
		if (!carrierType.isNumeric())
			throw new TyperError(filePath, expression.getPosition(),
				"Abstract property increment/decrement requires an Int or Float underlying carrier: " + resultType.getDisplay());
		final binaryOperator = op == HxUnaryOperator.Increment ? "+" : "-";
		final one = TypedExpr.intLiteral(1, TyType.fromHintText("Int"), expression.getPosition());
		final expressions = place.prefix.copy();
		if (fixity == HxUnaryFixity.Prefix) {
			final current = place.read(carrierType);
			final updatedCarrier = TypedExpr.binary(binaryOperator, current, one, carrierType, expression.getPosition());
			final updated = TypedExpr.castValue(updatedCarrier, resultType.getDisplay(), resultType, expression.getPosition());
			expressions.push(place.write(updated));
		} else {
			final oldName = freshName("property_old", counter);
			final oldValue = place.read(resultType);
			expressions.push(TypedExpr.temporary(oldName, resultType.getDisplay(), oldValue, voidType(), expression.getPosition()));
			final oldRead = TypedExpr.localRead(oldName, resultType, expression.getPosition());
			final carrierRead = TypedExpr.castValue(oldRead, carrierType.getDisplay(), carrierType, expression.getPosition());
			final updatedCarrier = TypedExpr.binary(binaryOperator, carrierRead, one, carrierType, expression.getPosition());
			final updated = TypedExpr.castValue(updatedCarrier, resultType.getDisplay(), resultType, expression.getPosition());
			expressions.push(place.write(updated));
			expressions.push(oldRead);
		}
		final block = TypedExpr.block(expressions, resultType, expression.getPosition());
		return TypedExpr.castValue(block, resultType.getDisplay(), resultType, expression.getPosition());
	}

	static function lowerExpression(expression:TypedExpr, helpers:StringMap<TypedFunction>, index:TyperIndex, filePath:String,
			counter:TypedUnaryLoweringCounter):TypedExpr {
		final loweredChildren = [
			for (child in expression.getExpressions())
				lowerExpression(child, helpers, index, filePath, counter)
		];
		final rebuilt = expression.withExpressions(loweredChildren);
		if (rebuilt.getTag() != TypedExprTag.Unary)
			return rebuilt;
		final op = rebuilt.getUnaryOperator();
		final fixity = rebuilt.getUnaryFixity();
		if (op == null || fixity == null || loweredChildren.length != 1)
			throw "typed unary expression has an invalid structural payload";
		final operand = loweredChildren[0];
		final operandIdentity = operand.getType().getNominalIdentity();
		final abstractInfo = operandIdentity == null ? null : index.getAbstractByFullName(operandIdentity.getCanonicalName());
		if (abstractInfo != null && (op == HxUnaryOperator.Increment || op == HxUnaryOperator.Decrement)) {
			final propertyPlace = propertyPlaceFor(operand, index, filePath, rebuilt.getPosition() == null ? HxPos.unknown() : rebuilt.getPosition(), counter);
			if (propertyPlace != null)
				return propertyUpdate(rebuilt, operand, abstractInfo, propertyPlace, op, fixity, counter, filePath);
		}
		final selected = TyAbstractUnaryBinding.select(index, operand.getType(), op, fixity, filePath,
			rebuilt.getPosition() == null ? HxPos.unknown() : rebuilt.getPosition());
		if (selected == null)
			return rebuilt;
		final declaration = selected.getDeclaration();
		if (!declaration.getHasBody())
			return nativeBodylessOperation(selected, operand, abstractInfo, filePath);
		if (declaration.getIsStatic())
			return staticCall(selected, operand, index);
		if (!declaration.getIsInline())
			return instanceCall(selected, operand);
		return inlineCall(selected, operand, helpers, index, filePath, counter);
	}

	static function lowerStatement(statement:TypedStmt, helpers:StringMap<TypedFunction>, index:TyperIndex, filePath:String,
			counter:TypedUnaryLoweringCounter):TypedStmt {
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

	static function assertNoAbstractUnaryExpression(expression:TypedExpr, index:TyperIndex, owner:String):Void {
		for (child in expression.getExpressions())
			assertNoAbstractUnaryExpression(child, index, owner);
		if (expression.getTag() != TypedExprTag.Unary)
			return;
		final children = expression.getExpressions();
		if (children.length != 1)
			throw "lowered typed unary expression has an invalid structural payload in " + owner;
		final identity = children[0].getType().getNominalIdentity();
		if (identity != null && index.getAbstractByFullName(identity.getCanonicalName()) != null)
			throw "abstract unary operation survived shared typed lowering in " + owner + ": " + identity.getCanonicalName();
	}

	static function assertNoAbstractUnary(classes:Array<TypedClass>, index:TyperIndex):Void {
		for (typedClass in classes)
			for (typedFunction in typedClass.getFunctions()) {
				final owner = typedFunction.getStableIdentity();
				for (statement in typedFunction.getBody().getStatements()) {
					for (expression in statement.getExpressions())
						assertNoAbstractUnaryExpression(expression, index, owner);
					assertNoAbstractUnaryStatements(statement.getStatements(), index, owner);
				}
			}
	}

	static function assertNoAbstractUnaryStatements(statements:Array<TypedStmt>, index:TyperIndex, owner:String):Void {
		for (statement in statements) {
			for (expression in statement.getExpressions())
				assertNoAbstractUnaryExpression(expression, index, owner);
			assertNoAbstractUnaryStatements(statement.getStatements(), index, owner);
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

		final counter = new TypedUnaryLoweringCounter();
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
		assertNoAbstractUnary(lowered, index);
		return lowered;
	}

	/** Lower every function in one typed module after all local helper bodies exist. **/
	public static function lowerClasses(classes:Array<TypedClass>, index:TyperIndex, filePath:String):Array<TypedClass> {
		final helpers = new StringMap<TypedFunction>();
		collectHelpers(classes, helpers);
		return lowerClassesWithHelpers(classes, index, filePath, helpers);
	}

	/**
		Seal a complete typed program using one transient helper-body catalog.

		The catalog is derived from structural typed declarations and discarded after
		lowering; it is not a semantic side table. This program boundary lets an
		operator use in one module inline the exact helper declared in another before
		any backend can observe the body.
	**/
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
