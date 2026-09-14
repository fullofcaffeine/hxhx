package backend.ocaml;

/**
	Makes plain Int field updates explicit for native OCaml emission.

	One receiver capture and one old-value capture preserve effects and postfix
	results. Exact field facts restrict this pass to ordinary instance storage;
	properties, static fields, nullable values, and overloaded operators retain
	their existing owners. Macro quotations remain source syntax.
**/
private function lowerExpression(expression:TypedExpr, allocator:TyCompilerTemporaryAllocator):TypedExpr {
	if (expression.getTag() == MacroExpr || expression.getTag() == MacroType)
		return expression;
	final children = [for (child in expression.getExpressions()) lowerExpression(child, allocator)];
	final rebuilt = expression.withExpressions(children);
	if (rebuilt.getTag() != Unary || children.length != 1)
		return rebuilt;
	final op = rebuilt.getUnaryOperator();
	if (op != HxUnaryOperator.Increment && op != HxUnaryOperator.Decrement)
		return rebuilt;
	final operand = children[0];
	final field = operand.getFieldInfo();
	final intType = TyType.fromHintText("Int");
	if (operand.getTag() != FieldRead
		|| field == null
		|| field.getIsStatic()
		|| field.getIsFinal()
		|| field.getType().getSemanticKey() != intType.getSemanticKey()
		|| (field.getPropertyGet() != "" && field.getPropertyGet() != "default")
		|| (field.getPropertySet() != "" && field.getPropertySet() != "default"))
		return rebuilt;
	final position = expression.getPosition();
	final receiver = operand.getExpressions()[0];
	final receiverBinding = allocator.allocate("receiver", receiver.getType());
	final oldBinding = allocator.allocate("old", intType);
	final nextBinding = allocator.allocate("next", intType);
	function read(binding:TyLocalBinding):TypedExpr
		return TypedExpr.localRead(binding.getSourceName(), binding.getType(), position, binding);
	function capture(binding:TyLocalBinding, value:TypedExpr):TypedExpr
		return TypedExpr.temporary(binding.getSourceName(), binding.getType().getCanonicalDisplay(), value, TyType.fromHintText("Void"), position, binding);
	final place = TypedExpr.fieldRead(read(receiverBinding), field.getName(), intType, position, field);
	final next = TypedExpr.binary(op == HxUnaryOperator.Increment ? "+" : "-", read(oldBinding), TypedExpr.intLiteral(1, intType, position), intType, position);
	return TypedExpr.block([
		capture(receiverBinding, receiver),
		capture(oldBinding, place),
		capture(nextBinding, TypedExpr.assign(place, next, intType, position)),
		read(rebuilt.getUnaryFixity() == HxUnaryFixity.Postfix ? oldBinding : nextBinding)
	], intType, position);
}

private function lowerStatement(statement:TypedStmt, allocator:TyCompilerTemporaryAllocator):TypedStmt {
	return statement.withChildren([
		for (expression in statement.getExpressions()) lowerExpression(expression, allocator)
	], [for (child in statement.getStatements()) lowerStatement(child, allocator)]);
}

/** Lower function bodies and field initializers without changing declaration identities. */
private function lowerClasses(classes:Array<TypedClass>):Array<TypedClass> {
	return [
		for (typedClass in classes) {
			final functions = [
				for (fn in typedClass.getFunctions()) {
					final allocator = new TyCompilerTemporaryAllocator(fn.getStableIdentity(), "typed-int-field-update-v1", "__hxhx_int_field_");
					final body = fn.getBody();
					fn.withBody(new TypedFunctionBody([for (statement in body.getStatements()) lowerStatement(statement, allocator)],
						body.getSourceFingerprint()));
				}
			];
			final initializers = [
				for (initializer in typedClass.getFieldInitializers()) {
					final field = initializer.getField();
					final allocator = new TyCompilerTemporaryAllocator(field.getCanonicalKey(), "typed-int-field-update-v1", "__hxhx_int_field_");
					new TypedFieldInitializer(field, lowerExpression(initializer.getExpression(), allocator));
				}
			];
			new TypedClass(typedClass.getSourceDeclaration(), typedClass.getSemanticInfo(), functions, initializers, typedClass.getResolvedExtends(),
				typedClass.getResolvedImplements());
		}
	];
}

/** Apply the same mutation contract after whole-program abstract-operator selection. */
function lowerModules(modules:Array<TypedModule>):Array<TypedModule> {
	return [
		for (module in modules) module.withTypedClasses(lowerClasses(module.getTypedClasses()))
	];
}
