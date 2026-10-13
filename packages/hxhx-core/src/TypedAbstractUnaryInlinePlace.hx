/** The unary operator's selected storage and the effects that precede its body. */
typedef TypedUnaryPlace = {
	final prefix:Array<TypedExpr>;
	final read:TyType->TypedExpr;
	final write:TypedExpr->TypedExpr;
};

/** Inline bodies also need a compound update that retains one exact destination. */
typedef TypedInlineUnaryPlace = {
	> TypedUnaryPlace,
	final receiverType:TyType;
	final compound:(String, TypedExpr, TyType, Null<HxPos>) -> TypedExpr;
	final update:(HxUnaryOperator, HxUnaryFixity, TyType, Null<HxPos>) -> TypedExpr;
};

/**
	Expose an abstract's backing value without changing its caller-owned binding.
	Only the selected inline declaration can request these representation views.
	Each write converts back to the original abstract storage immediately. Compound
	updates capture their address and old value before RHS effects; subsequent
	reads in the helper still follow the unary operator's separate place contract.
 */
function prepare(input:{
	place:TypedUnaryPlace,
	receiver:TyType,
	abstractInfo:TyAbstractInfo,
	declaration:TyDeclarationInfo,
	allocator:TyCompilerTemporaryAllocator
}):TypedInlineUnaryPlace {
	final owner = input.abstractInfo;
	final declaration = input.declaration;
	final receiver = input.receiver;
	if (owner == null
		|| receiver.getNominalIdentity() == null
		|| !owner.getIdentity().equals(receiver.getNominalIdentity())
		|| !owner.getIdentity().equals(declaration.getOwner())
		|| owner.declarationForSignature(declaration.getSignature()) != declaration
		|| declaration.getIsStatic()
		|| !declaration.getIsInline()
		|| !declaration.getHasBody())
		throw "inline unary storage requires its exact abstract declaration and receiver";
	final bindings = TyTypeSubstitution.bind(owner.getTypeParameterIds(), receiver.getTypeArguments(), declaration.getIdentity().getCanonicalKey());
	final backing = TyTypeSubstitution.apply(owner.getUnderlyingType(), bindings);
	function view(value:TypedExpr, expected:TyType):TypedExpr {
		final actual = value.getType().getSemanticKey();
		final target = expected.getSemanticKey();
		if (actual == target)
			return value;
		if (!((actual == receiver.getSemanticKey() && target == backing.getSemanticKey())
			|| (actual == backing.getSemanticKey() && target == receiver.getSemanticKey())))
			throw "inline unary storage view differs from its selected abstract backing";
		return TypedExpr.castValue(value, expected.getDisplay(), expected, value.getPosition(), true);
	}
	function modify(op:String, right:TypedExpr, type:TyType, position:Null<HxPos>, returnPrevious:Bool):TypedExpr {
		final expected = TyTypeSubstitution.apply(type, bindings);
		if (expected.getSemanticKey() != backing.getSemanticKey())
			throw "inline unary compound update differs from its selected backing type";
		final base = HxBinaryOperatorTools.baseOperator(op);
		if (base == null)
			throw "inline unary compound update requires its typed base operator";
		final expressions = new Array<TypedExpr>();
		function capture(value:TypedExpr):TypedExpr {
			final local = input.allocator.allocate("inline_storage", value.getType());
			expressions.push(TypedExpr.temporary(local.getSourceName(), local.getType().getDisplay(), value, TyType.fromHintText("Void"), value.getPosition(),
				local));
			return TypedExpr.localRead(local.getSourceName(), local.getType(), value.getPosition(), local);
		}
		final destination = TypedCompoundDestination.retain(input.place.read(receiver), capture);
		final previous = capture(view(destination, backing));
		final updated = TypedExpr.binary(base, previous, right, backing, position);
		final assignment = TypedExpr.assign(destination, view(updated, receiver), receiver, position);
		expressions.push(view(assignment, backing));
		if (returnPrevious)
			expressions.push(previous);
		return TypedExpr.block(expressions, backing, position);
	}
	return {
		prefix: input.place.prefix,
		receiverType: receiver,
		read: type -> view(input.place.read(receiver), TyTypeSubstitution.apply(type, bindings)),
		write: value -> {
			final written = input.place.write(view(value, receiver));
			return view(written, value.getType());
		},
		compound: (op, right, type, position) -> modify(op, right, type, position, false),
		update: (op, fixity, type, position) -> {
			if (op != HxUnaryOperator.Increment && op != HxUnaryOperator.Decrement)
				throw "inline unary storage update requires increment or decrement";
			return modify(op == HxUnaryOperator.Increment ? "+=" : "-=", TypedExpr.intLiteral(1, TyType.fromHintText("Int"), position), type, position,
				fixity == HxUnaryFixity.Postfix);
		}
	};
}
