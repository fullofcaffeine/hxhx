package backend.ocaml;

/**
	Makes ordinary Int field updates and String field appends explicit for native OCaml.

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
	if (rebuilt.getTag() == CompoundAssign)
		return lowerFieldCompound(rebuilt, allocator);
	if (rebuilt.getTag() != Unary || children.length != 1)
		return rebuilt;
	final op = rebuilt.getUnaryOperator();
	if (op != HxUnaryOperator.Increment && op != HxUnaryOperator.Decrement)
		return rebuilt;
	final operand = children[0];
	final field = operand.getFieldInfo();
	final intType = TyType.fromHintText("Int");
	if ((operand.getTag() != FieldRead && operand.getTag() != NameRead)
		|| field == null
		|| field.getIsStatic()
		|| field.getIsFinal()
		|| field.getType().getSemanticKey() != intType.getSemanticKey()
		|| (field.getPropertyGet() != "" && field.getPropertyGet() != "default")
		|| (field.getPropertySet() != "" && field.getPropertySet() != "default"))
		return rebuilt;
	final position = expression.getPosition();
	final receiver = operand.getTag() == FieldRead ? operand.getExpressions()[0] : null;
	final receiverBinding = receiver == null ? null : allocator.allocate("receiver", receiver.getType());
	final oldBinding = allocator.allocate("old", intType);
	final nextBinding = allocator.allocate("next", intType);
	function read(binding:TyLocalBinding):TypedExpr
		return TypedExpr.localRead(binding.getSourceName(), binding.getType(), position, binding);
	function capture(binding:TyLocalBinding, value:TypedExpr):TypedExpr
		return TypedExpr.temporary(binding.getSourceName(), binding.getType().getCanonicalDisplay(), value, TyType.fromHintText("Void"), position, binding);
	final place = receiverBinding == null ? operand : TypedExpr.fieldRead(read(receiverBinding), field.getName(), intType, position, field);
	final next = TypedExpr.binary(op == HxUnaryOperator.Increment ? "+" : "-", read(oldBinding), TypedExpr.intLiteral(1, intType, position), intType, position);
	final sequence = receiverBinding == null ? [] : [capture(receiverBinding, receiver)];
	return TypedExpr.block(sequence.concat([
		capture(oldBinding, place),
		capture(nextBinding, TypedExpr.assign(place, next, intType, position)),
		read(rebuilt.getUnaryFixity() == HxUnaryFixity.Postfix ? oldBinding : nextBinding)
	]), intType, position);
}

/**
	Capture the receiver and old value before the RHS, then return the written value.
	Admits String `+=` appends and Int `+=`, `-=`, `*=` updates with an Int operand,
	such as `state.index += value.length`; other operand types keep their owners.
 */
private function lowerFieldCompound(expression:TypedExpr, allocator:TyCompilerTemporaryAllocator):TypedExpr {
	final children = expression.getExpressions();
	if (children.length != 2)
		return expression;
	final assignment = expression.getTexts()[0];
	final operand = children[0];
	final field = operand.getFieldInfo();
	final key = operand.getType().getSemanticKey();
	final stringAppend = assignment == "+=" && key == "primitive:String";
	final intUpdate = (assignment == "+=" || assignment == "-=" || assignment == "*=")
		&& key == "primitive:Int"
		&& children[1].getType().getSemanticKey() == "primitive:Int";
	if ((!stringAppend && !intUpdate)
		|| (operand.getTag() != FieldRead && operand.getTag() != NameRead)
		|| field == null
		|| field.getIsStatic()
		|| field.getIsFinal()
		|| expression.getType().getSemanticKey() != key
		|| (field.getPropertyGet() != "" && field.getPropertyGet() != "default")
		|| (field.getPropertySet() != "" && field.getPropertySet() != "default"))
		return expression;
	final valueType = operand.getType();
	final position = expression.getPosition();
	function read(binding:TyLocalBinding):TypedExpr
		return TypedExpr.localRead(binding.getSourceName(), binding.getType(), position, binding);
	function capture(binding:TyLocalBinding, value:TypedExpr):TypedExpr
		return TypedExpr.temporary(binding.getSourceName(), binding.getType().getCanonicalDisplay(), value, TyType.fromHintText("Void"), position, binding);
	final sequence = new Array<TypedExpr>();
	var place = operand;
	if (operand.getTag() == FieldRead) {
		final receiver = operand.getExpressions()[0];
		final receiverBinding = allocator.allocate("receiver", receiver.getType());
		sequence.push(capture(receiverBinding, receiver));
		place = TypedExpr.fieldRead(read(receiverBinding), field.getName(), valueType, position, field);
	}
	final oldBinding = allocator.allocate("old", valueType);
	final rightBinding = allocator.allocate("right", children[1].getType());
	final nextBinding = allocator.allocate("next", valueType);
	sequence.push(capture(oldBinding, place));
	sequence.push(capture(rightBinding, children[1]));
	final next = TypedExpr.binary(assignment.substr(0, 1), read(oldBinding), read(rightBinding), valueType, position);
	sequence.push(capture(nextBinding, TypedExpr.assign(place, next, valueType, position)));
	sequence.push(read(nextBinding));
	return TypedExpr.block(sequence, valueType, position);
}

private function lowerStatement(statement:TypedStmt, allocator:TyCompilerTemporaryAllocator):TypedStmt {
	return statement.withChildren([
		for (expression in statement.getExpressions())
			lowerExpression(expression, allocator)
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
			typedClass.withMembers({functions: functions, fields: typedClass.getFields(), initializers: initializers});
		}
	];
}

/** Apply the same mutation contract after whole-program abstract-operator selection. */
function lowerModules(modules:Array<TypedModule>):Array<TypedModule> {
	return [
		for (module in modules)
			module.withTypedClasses(lowerClasses(module.getTypedClasses()))
	];
}
