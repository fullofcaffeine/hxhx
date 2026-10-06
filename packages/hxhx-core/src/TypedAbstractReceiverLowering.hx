import haxe.ds.StringMap;
import TypedExpr.TypedExprTag;

/**
	Expands inline abstract calls that can replace their caller's backing value.

	Each this occurrence retains the caller's storage expression. Arguments are
	saved before the body, while writes happen at their original statement, even
	before a throw. A continuation through conditional branches turns helper
	returns into invocation results without introducing another callable or
	changing the caller's return destination. Unsupported body forms fail here;
	targets must never guess a receiver-reference convention.
 */
class TypedAbstractReceiverLowering {
	final helpers:StringMap<TypedFunction>;
	final selected:StringMap<Bool>;
	final allocator:TyCompilerTemporaryAllocator;
	final active:Array<String> = [];

	function new(helpers:StringMap<TypedFunction>, selected:StringMap<Bool>, owner:String) {
		this.helpers = helpers;
		this.selected = selected;
		allocator = new TyCompilerTemporaryAllocator(owner, "abstract-receiver-v1", "__hxhx_inline_receiver_");
	}

	static function key(declaration:TyDeclarationInfo):String
		return declaration.getIdentity().getCanonicalKey();

	static function voidType():TyType
		return TyType.fromHintText("Void");

	static function reads(binding:TyLocalBinding, position:Null<HxPos>):TypedExpr
		return TypedExpr.localRead(binding.getSourceName(), binding.getType(), position, binding);

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
		if (expression.getTag() == Call && declaration != null && selected.exists(key(declaration)))
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
	function substitute(expression:TypedExpr, receiver:TypedExpr, locals:StringMap<TyLocalBinding>):TypedExpr {
		final children = expression.getExpressions();
		switch expression.getTag() {
			case ThisValue:
				return receiver.withType(expression.getType());
			case LocalRead:
				final bindings = expression.getLocalBindings();
				if (bindings.length != 1 || !locals.exists(bindings[0].getIdentity().getCanonicalKey()))
					throw "inline abstract receiver body lost its exact local binding";
				return reads(locals.get(bindings[0].getIdentity().getCanonicalKey()), expression.getPosition());
			case Temporary:
				final bindings = expression.getLocalBindings();
				if (bindings.length != 1 || children.length != 1)
					throw "inline abstract receiver temporary lacks its declaration";
				final initial = substitute(children[0], receiver, locals);
				final binding = allocator.allocate("temporary", initial.getType());
				locals.set(bindings[0].getIdentity().getCanonicalKey(), binding);
				return TypedExpr.temporary(binding.getSourceName(), binding.getType().getDisplay(), initial, voidType(), expression.getPosition(), binding);
			case Lambda | SourceFunction | ReturnExpr:
				throw "inline abstract receiver requires explicit nested callable or expression return ownership";
			case _:
		}
		final rewritten = [for (child in children) substitute(child, receiver, locals)];
		final declaration = expression.getDeclaration();
		if (expression.getTag() == Call && declaration != null && !declaration.getIsStatic() && children[0].getTag() == NameRead)
			rewritten[0] = TypedExpr.fieldRead(receiver, declaration.getSignature().getName(), children[0].getType(), children[0].getPosition());
		return expand(expression.withExpressions(rewritten));
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
	function body(statements:Array<TypedStmt>, receiver:TypedExpr, locals:StringMap<TyLocalBinding>, resultType:TyType):TypedExpr {
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
						throw "inline abstract receiver local requires one initialized exact binding";
					final initial = substitute(values[0], receiver, locals);
					final binding = allocator.allocate("local", initial.getType());
					locals.set(bindings[0].getIdentity().getCanonicalKey(), binding);
					output.push(TypedExpr.temporary(binding.getSourceName(), binding.getType().getDisplay(), initial, voidType(), position, binding));
				case Return:
					output.push(substitute(values[0], receiver, locals));
					return TypedExpr.block(output, resultType, position);
				case ReturnVoid:
					if (!resultType.isVoid())
						throw "inline abstract receiver returned no required value";
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
					throw "inline abstract receiver requires shared support for statement " + Std.string(statement.getTag());
			}
		}
		if (!resultType.isVoid())
			throw "inline abstract receiver can complete without its required result";
		output.push(TypedExpr.block([], voidType(), null));
		return TypedExpr.block(output, resultType, null);
	}

	/** Only declaration-selected inline receiver writers enter this expansion contract. */
	function expand(expression:TypedExpr):TypedExpr {
		final declaration = expression.getDeclaration();
		if (expression.getTag() != Call || declaration == null || !selected.exists(key(declaration)))
			return expression;
		final identity = key(declaration);
		if (active.contains(identity) || active.length >= 64)
			throw "recursive inline abstract receiver expansion: " + identity;
		final helper = helpers.get(identity);
		final environment = helper.getEnvironment();
		final children = expression.getExpressions();
		final callee = children[0];
		if (callee.getTag() != FieldRead || callee.getExpressions().length != 1 || environment == null)
			throw "inline abstract receiver call requires its exact receiver and environment: " + identity;
		final arguments = children.slice(1);
		switch callee.getExpressions()[0].getTag() {
			case LocalRead | NameRead | FieldRead | ArrayAccess | ThisValue:
			case _:
				throw "inline abstract receiver requires writable caller storage: " + identity;
		}
		final parameters = environment.getParams();
		if (arguments.length != parameters.length)
			throw "inline abstract receiver requires normalized exact arguments: " + identity;
		final locals = new StringMap<TyLocalBinding>();
		final prefix = new Array<TypedExpr>();
		for (index in 0...arguments.length) {
			final value = arguments[index];
			if (value.getType().hasUnknownComponent())
				throw "inline abstract receiver argument requires a complete type";
			final binding = allocator.allocate("argument", value.getType());
			locals.set(parameters[index].getIdentity().getCanonicalKey(), binding);
			prefix.push(TypedExpr.temporary(binding.getSourceName(), binding.getType().getDisplay(), value, voidType(), value.getPosition(), binding));
		}
		active.push(identity);
		prefix.push(body(helper.getBody().getStatements(), callee.getExpressions()[0], locals, expression.getType()));
		active.pop();
		return TypedExpr.block(prefix, expression.getType(), expression.getPosition());
	}

	function expression(input:TypedExpr, implicitReceiver:Null<TypedExpr>):TypedExpr {
		final children = [for (child in input.getExpressions()) expression(child, implicitReceiver)];
		final declaration = input.getDeclaration();
		if (input.getTag() == Call && declaration != null && selected.exists(key(declaration)) && children[0].getTag() == NameRead) {
			if (implicitReceiver == null)
				throw "inline abstract receiver lost its implicit source receiver";
			children[0] = TypedExpr.fieldRead(implicitReceiver, declaration.getSignature().getName(), children[0].getType(), children[0].getPosition());
		}
		return expand(input.withExpressions(children));
	}

	function statement(input:TypedStmt, receiver:Null<TypedExpr>):TypedStmt
		return input.withChildren([for (value in input.getExpressions()) expression(value, receiver)],
			[for (child in input.getStatements()) statement(child, receiver)]);

	static function lower(classes:Array<TypedClass>, index:TyperIndex, helpers:StringMap<TypedFunction>, selected:StringMap<Bool>):Array<TypedClass> {
		return [
			for (owner in classes)
				owner.withFunctions([
					for (fn in owner.getFunctions()) {
						final pass = new TypedAbstractReceiverLowering(helpers, selected, fn.getStableIdentity());
						final abstractInfo = index.getAbstractByFullName(fn.getOwnerName());
						final receiver = abstractInfo == null ? null : TypedExpr.thisValue(abstractInfo.getUnderlyingType(), null);
						fn.withBody(new TypedFunctionBody([for (item in fn.getBody().getStatements()) pass.statement(item, receiver)],
							fn.getBody().getSourceFingerprint()),
							[
								for (value in fn.getDefaults())
									new TypedFunctionDefault(value.getParameterIndex(), pass.expression(value.getExpression(), receiver))
							]);
					}
				])
		];
	}

	static function inventory(classes:Array<TypedClass>, index:TyperIndex, helpers:StringMap<TypedFunction>):Void {
		for (owner in classes)
			for (fn in owner.getFunctions()) {
				final declaration = fn.getDeclaration();
				if (declaration != null
					&& declaration.getIsInline()
					&& !declaration.getIsStatic()
					&& index.getAbstractByFullName(declaration.getOwner().getCanonicalName()) != null)
					helpers.set(key(declaration), fn);
			}
	}

	static function select(helpers:StringMap<TypedFunction>):StringMap<Bool> {
		final selected = new StringMap<Bool>();
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
		return selected;
	}

	public static function lowerClasses(classes:Array<TypedClass>, index:TyperIndex):Array<TypedClass> {
		final helpers = new StringMap<TypedFunction>();
		inventory(classes, index, helpers);
		return lower(classes, index, helpers, select(helpers));
	}

	public static function lowerModules(modules:Array<TypedModule>, index:TyperIndex):Array<TypedModule> {
		final helpers = new StringMap<TypedFunction>();
		for (module in modules)
			inventory(module.getTypedClasses(), index, helpers);
		final selected = select(helpers);
		return [
			for (module in modules)
				module.withTypedClasses(lower(module.getTypedClasses(), index, helpers, selected))
		];
	}
}
