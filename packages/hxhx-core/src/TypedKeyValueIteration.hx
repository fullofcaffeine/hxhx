/** Exact source and replay facts shared by statement and expression loops. */
private typedef IterationInput<T> = {
	protocol:TypedExpr,
	body:T,
	bindings:Array<TyLocalBinding>,
	target:TyControlTarget,
	position:Null<HxPos>,
	owner:String
}

/** One saved protocol result or authored loop variable, with its precise initializer. */
private typedef IterationLocal = {
	binding:TyLocalBinding,
	initializer:TypedExpr,
	?target:TyControlTarget
}

/**
	Materialize the selected key/value protocol as ordinary typed executable nodes.
	Acquisition happens once, hasNext runs at every loop edge, and one next result
	supplies both source bindings. Original loop targets and declaration identities
	survive, while compiler temporaries are owned by this function and loop.
 */
class TypedKeyValueIteration {
	/** Replay consumes only the exact query occurrences recorded by inference. */
	public static function protocol(source:HxExpr, selected:TyKeyValueProtocolSource, build:HxExpr->TypedExpr):TypedExpr {
		if (!selected.owns(source))
			throw "iterator protocol belongs to another authored source occurrence";
		return TypedExpr.keyValueProtocol({
			acquire: build(selected.acquire),
			condition: build(selected.condition),
			next: build(selected.next),
			key: build(selected.key),
			value: build(selected.value)
		});
	}

	/** Only complete typed protocol evidence may be attached to a source loop. */
	public static function assertProtocol(node:TypedExpr):Void {
		final children = node.getExpressions();
		if (node.getTag() != KeyValueProtocol || !node.getType().isVoid() || children.length != 5)
			throw "iterator protocol requires acquisition, condition, next, key and value operands";
		if (children[1].getType().getSemanticKey() != "primitive:Bool")
			throw "iterator protocol condition must have Boolean type";
		for (child in children)
			if (child.getType().hasUnknownComponent())
				throw "iterator protocol operands must have complete types";
	}

	/** Structural iterator methods have an exact member signature without a nominal declaration. */
	static function structuralCall(call:TypedExpr, callee:TypedExpr, receiver:TyType):Bool {
		if (!receiver.isAnonymous() || callee.getTexts().length != 1)
			return false;
		for (field in receiver.getAnonymousFields())
			if (field.name == callee.getTexts()[0]
				&& !field.isOptional
				&& field.visibility == Public
				&& field.type.isFunction()
				&& !field.type.hasUnknownComponent()
				&& field.type.getFunctionArguments().length == 0
				&& field.type.getSemanticKey() == callee.getType().getSemanticKey()
				&& field.type.getFunctionReturn().getSemanticKey() == call.getType().getSemanticKey()) {
				return switch field.kind {
					case Method(parameters): parameters.length == 0;
					case Variable(_, get, _): get == "" || get == "default";
				};
			}
		return false;
	}

	/** Replace only a selected call's receiver, retaining its declaration and application facts. */
	static function receiver(call:TypedExpr, value:TypedExpr):TypedExpr {
		final children = call.getExpressions();
		if (call.getTag() != Call
			|| children.length != 1
			|| children[0].getTag() != FieldRead
			|| children[0].getExpressions().length != 1)
			throw "iterator protocol requires an exact zero-argument instance call: "
				+ call.getTag()
				+ ", operands="
				+ children.length
				+ ", callee="
				+ (children.length == 0 ? "missing" : Std.string(children[0].getTag()))
				+ ", declaration="
				+ (call.getDeclaration() == null ? "missing" : call.getDeclaration().getIdentity().getCanonicalKey())
				+ ", receiver="
				+ value.getType().getSemanticKey();
		if (children[0].getExpressions()[0].getType().getSemanticKey() != value.getType().getSemanticKey())
			throw "iterator receiver substitution changed its selected type";
		if (call.getDeclaration() == null && !structuralCall(call, children[0], value.getType()))
			throw "iterator protocol call lacks a complete nominal or structural contract";
		return call.withExpressions([children[0].withExpressions([value])]);
	}

	/** Typed member reads keep their selected field contract when the pair is saved once. */
	static function pairField(field:TypedExpr, pair:TypedExpr):TypedExpr {
		if (field.getTag() != FieldRead
			|| field.getExpressions().length != 1
			|| field.getExpressions()[0].getType().getSemanticKey() != pair.getType().getSemanticKey())
			throw "iterator pair requires its exact key/value field contract";
		return field.withExpressions([pair]);
	}

	/** Validate once and prepare both executable forms from the same selected protocol. */
	static function prepare<T>(input:IterationInput<T>):{cursor:IterationLocal, locals:Array<IterationLocal>, condition:TypedExpr} {
		if (input.target == null || input.target.getOwnerIdentity() != input.owner || input.bindings.length != 2)
			throw "iterator lowering requires its exact loop and source bindings";
		assertProtocol(input.protocol);
		final operands = input.protocol.getExpressions();
		final acquire = operands[0];
		final hasNext = operands[1];
		final next = operands[2];
		final key = operands[3];
		final value = operands[4];
		if (hasNext.getType().getSemanticKey() != "primitive:Bool" || next.getType().hasUnknownComponent())
			throw "iterator protocol requires a Boolean condition and complete pair type";
		final allocator = new TyCompilerTemporaryAllocator(input.owner, "key-value-protocol-v1:" + input.target.getCanonicalIdentity(), "__hxhx_iterator_");
		final iterator = allocator.allocate("cursor", acquire.getType());
		final pair = allocator.allocate("pair", next.getType());
		final iteratorRead = TypedExpr.localRead(iterator.getSourceName(), iterator.getType(), input.position, iterator);
		final pairRead = TypedExpr.localRead(pair.getSourceName(), pair.getType(), input.position, pair);
		final fields = [pairField(key, pairRead), pairField(value, pairRead)];
		final locals:Array<IterationLocal> = [{binding: pair, initializer: receiver(next, iteratorRead)}];
		for (index in 0...2) {
			final binding = input.bindings[index];
			if (binding.getType().getSemanticKey() != fields[index].getType().getSemanticKey())
				throw "iterator pair field changed its source binding type";
			locals.push({binding: binding, initializer: fields[index], target: input.target});
		}
		return {cursor: {binding: iterator, initializer: acquire}, locals: locals, condition: receiver(hasNext, iteratorRead)};
	}

	/** Statement loops retain their original statement body and control destination. */
	public static function lower(input:IterationInput<TypedStmt>):TypedStmt {
		final plan = prepare(input);
		function variable(local:IterationLocal):TypedStmt {
			final binding = local.binding;
			return TypedStmt.variable(binding.getSourceName(), binding.getType().getCanonicalDisplay(), local.initializer, input.position, null, binding)
				.withControlTarget(local.target);
		}
		final body = [for (local in plan.locals) variable(local)];
		body.push(input.body);
		return TypedStmt.block([
			variable(plan.cursor),
			TypedStmt.whileStmt(plan.condition, TypedStmt.block(body, input.position), input.position).withControlTarget(input.target)
		], input.position);
	}

	/**
		Expression loops remain an ordinary typed sequence until control lowering.
		That pass must still visit the authored body, so its returns exit the original
		function and its break/continue nodes retain this loop's destination.
	 */
	public static function lowerExpression(input:IterationInput<TypedExpr>):TypedExpr {
		final plan = prepare(input);
		final voidType = TyType.fromHintText("Void");
		function variable(local:IterationLocal):TypedExpr {
			final binding = local.binding;
			return TypedExpr.variableDeclarations([
				TypedExpr.variableDeclaration(binding.getSourceName(), binding.getType().getCanonicalDisplay(), local.initializer, false, false,
					binding.getType(), input.position, binding)
					.withControlTarget(local.target)], voidType, input.position);
		}
		final body = [for (local in plan.locals) variable(local)];
		body.push(input.body);
		return TypedExpr.block([
			variable(plan.cursor),
			TypedExpr.whileExpr(plan.condition, body, true, voidType, input.position, Normal).withControlTarget(input.target)
		], voidType, input.position);
	}
}
