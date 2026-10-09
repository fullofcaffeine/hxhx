import haxe.ds.StringMap;
import TypedExpr.TypedExprTag;

/** Receiver writers retain caller storage; other required calls may save a receiver value. */
private typedef RequiredInlineSelection = {
	final calls:StringMap<Bool>;
	final writers:StringMap<Bool>;
};

/**
	Expands calls whose Haxe bodies cannot be replaced by ordinary target calls.

	Static extern inline methods have no host implementation. Abstract methods
	that replace `this` must write to the caller's backing storage. Multi-type
	abstract methods also need their authored bodies because the
	selected provider does not own abstract-only methods. These calls use one
	body expansion, with exact declaration and local identities.

	Each this occurrence retains the caller's storage expression. Arguments are
	saved before the body, while writes happen at their original statement, even
	before a throw. A continuation through conditional branches turns helper
	returns into invocation results without introducing another callable or
	changing the caller's return destination. Unsupported body forms fail here;
	targets must never guess a receiver-reference convention.
 */
class TypedRequiredInlineLowering {
	final helpers:StringMap<TypedFunction>;
	final selected:StringMap<Bool>;
	final writers:StringMap<Bool>;
	final allocator:TyCompilerTemporaryAllocator;
	final active:Array<String> = [];
	final semanticIndex:TyperIndex;
	var typeBindings:StringMap<TyType> = new StringMap();

	function new(helpers:StringMap<TypedFunction>, selected:RequiredInlineSelection, owner:String, index:TyperIndex) {
		this.helpers = helpers;
		this.selected = selected.calls;
		this.writers = selected.writers;
		semanticIndex = index;
		allocator = new TyCompilerTemporaryAllocator(owner, "abstract-receiver-v1", "__hxhx_inline_receiver_");
	}

	static function key(declaration:TyDeclarationInfo):String
		return declaration.getIdentity().getCanonicalKey();

	static function voidType():TyType
		return TyType.fromHintText("Void");

	/** An implicit abstract call keeps its abstract owner even though explicit this reads expose backing storage. */
	function usesImplicitReceiver(callee:TypedExpr, declaration:TyDeclarationInfo):Bool {
		if (callee.getTag() == NameRead)
			return true;
		final owner = semanticIndex.getAbstractByFullName(declaration.getOwner().getCanonicalName());
		return owner != null
			&& owner.getMultiTypePolicy() != null
			&& callee.getTag() == FieldRead
			&& callee.getExpressions().length == 1
			&& callee.getExpressions()[0].getTag() == ThisValue;
	}

	static function reads(binding:TyLocalBinding, position:Null<HxPos>):TypedExpr
		return TypedExpr.localRead(binding.getSourceName(), binding.getType(), position, binding);

	/** Save a parameter or declared local using its instantiated contract, including an actual runtime conversion when required. */
	function storedValue(value:TypedExpr, declared:TyType):TypedExpr {
		final expected = TyTypeSubstitution.apply(declared, typeBindings);
		final conversion = TyImplicitConversionPlan.select(semanticIndex, expected, value.getType());
		if (conversion != null)
			return conversion.apply(value);
		// Ordinary assignment also admits Dynamic inputs and compatible nullable
		// views. Preserve both types for target storage without adding a runtime
		// checked cast or treating an unresolved relationship as permission.
		if (TyAssignmentCompatibility.classify(expected, value.getType(), Unchecked) == Compatible)
			return TypedExpr.castValue(value, "", expected, value.getPosition());
		throw "inline storage requires a proven conversion from "
			+ value.getType().getSemanticKey()
			+ " to "
			+ expected.getSemanticKey();
	}

	/** Detect direct rebinding and calls to already-selected helpers to a fixed point. */
	static function needsExpression(expression:TypedExpr, selected:StringMap<Bool>):Bool {
		final children = expression.getExpressions();
		final updatingUnary = expression.getTag() == Unary
			&& (expression.getUnaryOperator() == HxUnaryOperator.Increment || expression.getUnaryOperator() == HxUnaryOperator.Decrement);
		if ((expression.getTag() == Assign || expression.getTag() == CompoundAssign || updatingUnary)
			&& children.length > 0
			&& children[0].getTag() == ThisValue)
			return true;
		final declaration = expression.getDeclaration();
		if (expression.getTag() == Call && declaration != null && !declaration.getIsStatic() && selected.exists(key(declaration)))
			return true;
		for (child in children)
			if (needsExpression(child, selected))
				return true;
		return false;
	}

	static function needsStatement(statement:TypedStmt, selected:StringMap<Bool>):Bool {
		for (expression in statement.getExpressions())
			if (needsExpression(expression, selected))
				return true;
		for (child in statement.getStatements())
			if (needsStatement(child, selected))
				return true;
		return false;
	}

	/** Source locals and earlier compiler temporaries both receive fresh caller-owned identities. */
	function substitute(expression:TypedExpr, receiver:Null<TypedExpr>, locals:StringMap<TyLocalBinding>):TypedExpr {
		final children = expression.getExpressions();
		switch expression.getTag() {
			case ThisValue:
				if (receiver == null)
					throw "static inline body cannot read an instance receiver";
				return receiver.withType(TyTypeSubstitution.apply(expression.getType(), typeBindings));
			case LocalRead:
				final bindings = expression.getLocalBindings();
				if (bindings.length != 1 || !locals.exists(bindings[0].getIdentity().getCanonicalKey()))
					throw "required inline body lost its exact local binding";
				return reads(locals.get(bindings[0].getIdentity().getCanonicalKey()), expression.getPosition());
			case Temporary:
				final bindings = expression.getLocalBindings();
				if (bindings.length != 1 || children.length != 1)
					throw "required inline temporary lacks its declaration";
				final initial = substitute(children[0], receiver, locals);
				final binding = allocator.allocate("temporary", initial.getType());
				locals.set(bindings[0].getIdentity().getCanonicalKey(), binding);
				return TypedExpr.temporary(binding.getSourceName(), binding.getType().getDisplay(), initial, voidType(), expression.getPosition(), binding);
			case Lambda | SourceFunction | ReturnExpr:
				throw "required inline requires explicit nested callable or expression return ownership";
			case _:
		}
		final rewritten = [for (child in children) substitute(child, receiver, locals)];
		final declaration = expression.getDeclaration();
		if (expression.getTag() == Call
			&& declaration != null
			&& !declaration.getIsStatic()
			&& usesImplicitReceiver(children[0], declaration)) {
			if (receiver == null)
				throw "static inline body cannot call an implicit instance method";
			rewritten[0] = TypedExpr.fieldRead(receiver, declaration.getSignature().getName(), children[0].getType(), children[0].getPosition());
		}
		try {
			return expand(expression.withInlineTypes(rewritten, typeBindings));
		} catch (error:haxe.Exception) {
			throw error.message + " while expanding " + active.join(" -> ") + " at " + Std.string(expression.getTag())
				+ (declaration == null ? "" : " " + key(declaration));
		}
	}

	/** A branch consumes the remaining helper statements only when it has not returned or thrown. */
	static function hasReturn(statement:TypedStmt):Bool {
		if (statement.getTag() == Return || statement.getTag() == ReturnVoid)
			return true;
		for (child in statement.getStatements())
			if (hasReturn(child))
				return true;
		return false;
	}

	/** Keep ordinary conditional effects linear; distribute the continuation only around helper returns. */
	function body(statements:Array<TypedStmt>, receiver:Null<TypedExpr>, locals:StringMap<TyLocalBinding>, resultType:TyType):TypedExpr {
		final output = new Array<TypedExpr>();
		for (index in 0...statements.length) {
			final statement = statements[index];
			final values = statement.getExpressions();
			final children = statement.getStatements();
			final position = statement.getPosition();
			switch statement.getTag() {
				case Expression:
					output.push(substitute(values[0], receiver, locals));
				case Var:
					final bindings = statement.getLocalBindings();
					if (bindings.length != 1 || values.length != 1 || statement.getMetadata().length != 0)
						throw "required inline local requires one initialized exact binding";
					final initial = storedValue(substitute(values[0], receiver, locals), bindings[0].getType());
					final binding = allocator.allocate("local", initial.getType());
					locals.set(bindings[0].getIdentity().getCanonicalKey(), binding);
					output.push(TypedExpr.temporary(binding.getSourceName(), binding.getType().getDisplay(), initial, voidType(), position, binding));
				case Return:
					output.push(substitute(values[0], receiver, locals));
					return TypedExpr.block(output, resultType, position);
				case ReturnVoid:
					if (!resultType.isVoid())
						throw "required inline returned no required value";
					output.push(TypedExpr.block([], voidType(), position));
					return TypedExpr.block(output, resultType, position);
				case Throw:
					output.push(TypedExpr.throwExpr(substitute(values[0], receiver, locals), position));
					return TypedExpr.block(output, resultType, position);
				case Block:
					output.push(body(children.concat(statements.slice(index + 1)), receiver, locals.copy(), resultType));
					return TypedExpr.block(output, resultType, position);
				case If:
					final condition = substitute(values[0], receiver, locals);
					if (!hasReturn(statement)) {
						final yes = body([children[0]], receiver, locals.copy(), voidType());
						final no = children.length == 2 ? body([children[1]], receiver, locals.copy(), voidType()) : null;
						output.push(TypedExpr.sourceIf(condition, yes, no, voidType(), position));
						continue;
					}
					final remaining = statements.slice(index + 1);
					final yes = body([children[0]].concat(remaining), receiver, locals.copy(), resultType);
					final no = body((children.length == 2 ? [children[1]] : []).concat(remaining), receiver, locals.copy(), resultType);
					output.push(TypedExpr.sourceIf(condition, yes, no, resultType, position));
					return TypedExpr.block(output, resultType, position);
				case _:
					throw "required inline requires shared support for statement " + Std.string(statement.getTag());
			}
		}
		if (!resultType.isVoid())
			throw "required inline can complete without its required result";
		output.push(TypedExpr.block([], voidType(), null));
		return TypedExpr.block(output, resultType, null);
	}

	/** Static extern calls have no runtime receiver; abstract writers retain their caller's storage. */
	function expand(expression:TypedExpr):TypedExpr {
		final declaration = expression.getDeclaration();
		if (expression.getTag() != Call || declaration == null || !selected.exists(key(declaration)))
			return expression;
		final identity = key(declaration);
		if (active.contains(identity) || active.length >= 64)
			throw "recursive required inline expansion: " + identity;
		final helper = helpers.get(identity);
		final environment = helper.getEnvironment();
		final children = expression.getExpressions();
		final callee = children[0];
		if (environment == null)
			throw "required inline call requires its exact environment: " + identity;
		var receiver:Null<TypedExpr> = null;
		final prefix = new Array<TypedExpr>();
		final abstractOwner = semanticIndex.getAbstractByFullName(declaration.getOwner().getCanonicalName());
		final multiType = !declaration.getIsStatic() && abstractOwner != null && abstractOwner.getMultiTypePolicy() != null;
		var ownerBindings = new StringMap<TyType>();
		if (!declaration.getIsStatic()) {
			if (callee.getTag() != FieldRead || callee.getExpressions().length != 1)
				throw "required inline call requires its exact receiver: " + identity;
			receiver = callee.getExpressions()[0];
			if (multiType) {
				if (receiver.getType().getNominalIdentity() == null
					|| !receiver.getType().getNominalIdentity().equals(abstractOwner.getIdentity()))
					throw "multi-type inline receiver belongs to another applied owner";
				ownerBindings = TyTypeSubstitution.bind(abstractOwner.getTypeParameterIds(), receiver.getType().getTypeArguments(), identity);
			}
			if (multiType && !writers.exists(identity)) {
				final backing = TyTypeSubstitution.apply(abstractOwner.getUnderlyingType(), ownerBindings);
				// This abstract already stores the selected provider. Save the receiver
				// before arguments so repeated this reads cannot repeat caller effects.
				final stored = allocator.allocate("receiver", backing);
				prefix.push(TypedExpr.temporary(stored.getSourceName(), backing.getDisplay(),
					TypedExpr.castValue(receiver, "", backing, receiver.getPosition(), true), voidType(), receiver.getPosition(), stored));
				receiver = reads(stored, receiver.getPosition());
			} else
				switch receiver.getTag() {
					case LocalRead | NameRead | FieldRead | ArrayAccess | ThisValue:
					case _:
						throw "inline abstract receiver requires writable caller storage: " + identity;
				}
		}
		final arguments = children.slice(1);
		if (expression.getExtensionProvider() != null) {
			if (!declaration.getIsStatic() || callee.getTag() != FieldRead || callee.getExpressions().length != 1)
				throw "inline extension call requires its resolved receiver argument: " + identity;
			arguments.unshift(callee.getExpressions()[0]);
		}
		final parameters = environment.getParams();
		if (arguments.length != parameters.length)
			throw "required inline requires normalized exact arguments: " + identity;
		final named = expression.getNamedArguments();
		if (declaration.getTypeParameterIds().length != 0 && named == null)
			throw "generic inline call requires its selected argument signature";
		final selectedParameters = named == null ? declaration.getSignature().getArgs().copy() : named.getArguments().getFunctionType().getFunctionArguments();
		if (named != null && expression.getExtensionProvider() != null)
			selectedParameters.unshift(arguments[0].getType());
		final previousBindings = typeBindings;
		typeBindings = TyMethodGenericBinding.inlineBindings(declaration, selectedParameters, expression.getType(), semanticIndex);
		for (identity => type in ownerBindings)
			typeBindings.set(identity, type);
		final locals = new StringMap<TyLocalBinding>();
		for (index in 0...arguments.length) {
			final value = storedValue(arguments[index], parameters[index].getType());
			if (value.getType().hasUnknownComponent())
				throw "required inline argument requires a complete type";
			final binding = allocator.allocate("argument", value.getType());
			locals.set(parameters[index].getIdentity().getCanonicalKey(), binding);
			prefix.push(TypedExpr.temporary(binding.getSourceName(), binding.getType().getDisplay(), value, voidType(), value.getPosition(), binding));
		}
		active.push(identity);
		prefix.push(body(helper.getBody().getStatements(), receiver, locals, expression.getType()));
		active.pop();
		typeBindings = previousBindings;
		return TypedExpr.block(prefix, expression.getType(), expression.getPosition());
	}

	function expression(input:TypedExpr, implicitReceiver:Null<TypedExpr>):TypedExpr {
		final children = [for (child in input.getExpressions()) expression(child, implicitReceiver)];
		final declaration = input.getDeclaration();
		if (input.getTag() == Call
			&& declaration != null
			&& !declaration.getIsStatic()
			&& selected.exists(key(declaration))
			&& usesImplicitReceiver(children[0], declaration)) {
			if (implicitReceiver == null)
				throw "required inline lost its implicit source receiver";
			children[0] = TypedExpr.fieldRead(implicitReceiver, declaration.getSignature().getName(), children[0].getType(), children[0].getPosition());
		}
		return expand(input.withExpressions(children));
	}

	function statement(input:TypedStmt, receiver:Null<TypedExpr>):TypedStmt
		return input.withChildren([for (value in input.getExpressions()) expression(value, receiver)],
			[for (child in input.getStatements()) statement(child, receiver)]);

	static function lower(classes:Array<TypedClass>, index:TyperIndex, helpers:StringMap<TypedFunction>, selected:RequiredInlineSelection):Array<TypedClass> {
		return [
			for (owner in classes) {
				final functions = [
					for (fn in owner.getFunctions()) {
						final pass = new TypedRequiredInlineLowering(helpers, selected, fn.getStableIdentity(), index);
						final abstractInfo = fn.getDeclaration() == null ? null : index.getAbstractByFullName(fn.getDeclaration()
							.getOwner()
							.getCanonicalName());
						final receiverType = abstractInfo == null ? null : abstractInfo.getMultiTypePolicy() == null ? abstractInfo.getUnderlyingType() : TyType.nominal(abstractInfo.getIdentity(),
							[
							for (parameter in abstractInfo.getTypeParameterIds())
								TyType.typeParameter(parameter)
						]);
						final receiver = receiverType == null ? null : TypedExpr.thisValue(receiverType, null);
						fn.withBody(new TypedFunctionBody([for (item in fn.getBody().getStatements()) pass.statement(item, receiver)],
							fn.getBody().getSourceFingerprint()),
							[
								for (value in fn.getDefaults())
									new TypedFunctionDefault(value.getParameterIndex(), pass.expression(value.getExpression(), receiver))
							]);
					}
				];
				final initializers = [
					for (initializer in owner.getFieldInitializers()) {
						final pass = new TypedRequiredInlineLowering(helpers, selected, initializer.getField().getCanonicalKey(), index);
						new TypedFieldInitializer(initializer.getField(), pass.expression(initializer.getExpression(), null));
					}
				];
				owner.withMembers({functions: functions, fields: owner.getFields(), initializers: initializers});
			}
		];
	}

	static function inventory(classes:Array<TypedClass>, index:TyperIndex, helpers:StringMap<TypedFunction>):Void {
		for (owner in classes)
			for (fn in owner.getFunctions()) {
				final declaration = fn.getDeclaration();
				if (declaration != null
					&& declaration.getIsInline()
					&& declaration.getHasBody()
					&& ((declaration.getIsStatic() && HxClassDecl.getIsExtern(owner.getSourceDeclaration()))
						|| (!declaration.getIsStatic() && index.getAbstractByFullName(declaration.getOwner().getCanonicalName()) != null)))
					helpers.set(key(declaration), fn);
			}
	}

	static function select(helpers:StringMap<TypedFunction>, index:TyperIndex):RequiredInlineSelection {
		final selected = new StringMap<Bool>();
		// Every static helper in this inventory is an authored extern inline body.
		for (identity => helper in helpers) {
			final declaration = helper.getDeclaration();
			if (declaration.getIsStatic())
				selected.set(identity, true);
		}
		var changed = true;
		while (changed) {
			changed = false;
			for (identity => helper in helpers)
				if (!selected.exists(identity))
					for (statement in helper.getBody().getStatements())
						if (needsStatement(statement, selected)) {
							selected.set(identity, true);
							changed = true;
							break;
						}
		}
		final calls = selected.copy();
		for (identity => helper in helpers) {
			final owner = index.getAbstractByFullName(helper.getDeclaration().getOwner().getCanonicalName());
			if (owner != null && owner.getMultiTypePolicy() != null)
				calls.set(identity, true);
		}
		return {calls: calls, writers: selected};
	}

	public static function lowerClasses(classes:Array<TypedClass>, index:TyperIndex):Array<TypedClass> {
		final helpers = new StringMap<TypedFunction>();
		inventory(classes, index, helpers);
		return lower(classes, index, helpers, select(helpers, index));
	}

	public static function lowerModules(modules:Array<TypedModule>, index:TyperIndex):Array<TypedModule> {
		final helpers = new StringMap<TypedFunction>();
		for (module in modules)
			inventory(module.getTypedClasses(), index, helpers);
		final selected = select(helpers, index);
		return [
			for (module in modules)
				module.withTypedClasses(lower(module.getTypedClasses(), index, helpers, selected))
		];
	}
}
