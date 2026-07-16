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

	static function inlineCall(binding:TyAbstractOperatorInfo, operand:TypedExpr, helpers:StringMap<TypedFunction>, index:TyperIndex, filePath:String,
			counter:TypedUnaryLoweringCounter):TypedExpr {
		final declaration = binding.getDeclaration();
		final helper = helpers.get(helperKey(declaration));
		if (helper == null)
			throw new TyperError(filePath, operand.getPosition(),
				"Inline abstract unary helper body is outside the typed program: " + declaration.getIdentity().getCanonicalKey());
		final place = placeFor(operand, filePath, operand.getPosition(), counter);
		final state:TypedInlineBodyState = {expressions: place.prefix.copy(), returned: false, returnedValue: false};
		lowerInlineStatements(helper.getBody().getStatements(), place, new StringMap<String>(), state, helpers, index, filePath, counter, declaration);
		if (!binding.getResultType().isVoid() && !state.returnedValue)
			throw new TyperError(filePath, declaration.getPosition(),
				"Inline abstract unary helper did not produce its declared result: " + declaration.getIdentity().getCanonicalKey());
		if (state.expressions.length == 0)
			state.expressions.push(TypedExpr.nullValue(binding.getResultType(), operand.getPosition()));
		final block = TypedExpr.block(state.expressions, binding.getResultType(), operand.getPosition());
		return binding.getResultType()
			.getNominalIdentity() == null ? block : TypedExpr.castValue(block, binding.getResultType().getDisplay(), binding.getResultType(),
			operand.getPosition());
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
		final selected = TyAbstractUnaryBinding.select(index, operand.getType(), op, fixity, filePath,
			rebuilt.getPosition() == null ? HxPos.unknown() : rebuilt.getPosition());
		if (selected == null)
			return rebuilt;
		final declaration = selected.getDeclaration();
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
