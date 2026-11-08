package backend.ocaml;

/**
	Makes ordinary Int field updates, String field appends, and `++`/`--` on
	Int and Float fields, anonymous-structure fields, and array elements
	explicit for native OCaml.

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
	if (operand.getTag() == ArrayAccess)
		return lowerIndexedStep(rebuilt, operand, allocator);
	final field = operand.getFieldInfo();
	final valueType = operand.getType();
	final stepType = steppedType(valueType);
	if (stepType == null)
		return rebuilt;
	final key = stepType.getSemanticKey();
	// A field of an anonymous structure (`{k: 1}`) has no declared field facts.
	// Its read and write already lower through the structural object path.
	final structural = field == null
		&& operand.getTag() == FieldRead
		&& TyAliasExpansion.revealNonNullable(operand.getExpressions()[0].getType()).isAnonymous();
	if (structural && valueType.isNullable())
		return rebuilt;
	if (!structural
		&& ((operand.getTag() != FieldRead && operand.getTag() != NameRead)
			|| field == null
			|| field.getIsStatic()
			|| field.getIsFinal()
			|| field.getType().getSemanticKey() != valueType.getSemanticKey()
			|| (field.getPropertyGet() != "" && field.getPropertyGet() != "default")
			|| (field.getPropertySet() != "" && field.getPropertySet() != "default")))
		return rebuilt;
	final position = expression.getPosition();
	final receiver = operand.getTag() == FieldRead ? operand.getExpressions()[0] : null;
	final fieldName = structural ? operand.getTexts()[0] : field.getName();
	final receiverBinding = receiver == null ? null : allocator.allocate("receiver", receiver.getType());
	final oldBinding = allocator.allocate("old", valueType);
	final nextBinding = allocator.allocate("next", stepType);
	function read(binding:TyLocalBinding):TypedExpr
		return TypedExpr.localRead(binding.getSourceName(), binding.getType(), position, binding);
	function capture(binding:TyLocalBinding, value:TypedExpr):TypedExpr
		return TypedExpr.temporary(binding.getSourceName(), binding.getType().getCanonicalDisplay(), value, TyType.fromHintText("Void"), position, binding);
	final place = receiverBinding == null ? operand : TypedExpr.fieldRead(read(receiverBinding), fieldName, valueType, position, field);
	final one = key == "primitive:Int" ? TypedExpr.intLiteral(1, stepType, position) : TypedExpr.floatLiteral(1.0, stepType, position);
	final next = TypedExpr.binary(op == HxUnaryOperator.Increment ? "+" : "-", read(oldBinding), one, stepType, position);
	final sequence = receiverBinding == null ? [] : [capture(receiverBinding, receiver)];
	final result = read(rebuilt.getUnaryFixity() == HxUnaryFixity.Postfix ? oldBinding : nextBinding);
	return TypedExpr.block(sequence.concat([
		capture(oldBinding, place),
		capture(nextBinding, TypedExpr.assign(place, next, stepType, position)),
		result
	]), result.getType(), position);
}

/**
	The type `++`/`--` computes in for a slot of type `type`: `Int` or `Float`,
	also when the slot is `Null<Int>` or `Null<Float>`. Returns null for every
	other type. A null value throws "Null Access" when it is read for the
	arithmetic.

	Each lowered binding keeps the type of the value it actually holds. The old
	value is read from the slot, so it has the slot type: for a `Null<Int>` slot
	it is the nullable carrier (`Obj.t` natively). The new value is computed in
	the stepped type, and the assignment that stores it yields that same plain
	`int` or `float`, so the assignment and the `next` binding have the stepped
	type. The block then has the type of the binding it yields: the slot type for
	postfix and the stepped type for prefix. Typing the prefix result as
	`Null<Int>` while it held a plain `int` made a later read into an `Int`
	local unwrap a value that was never boxed, which OCaml rejects.
**/
private function steppedType(type:TyType):Null<TyType> {
	final inner = type.isNullable() ? type.unwrapNull() : type;
	final key = inner.getSemanticKey();
	return key == "primitive:Int" || key == "primitive:Float" ? inner : null;
}

/**
	Lower `a[i]++`, `++a[i]`, `a[i]--`, and `--a[i]` on an `Array<Int>` or `Array<Float>`.

	Stage3 had no lowering for an indexed operand, so the whole update became a
	placeholder and was dropped. This rewrites it into operations Stage3 already
	emits: bind the array and the index once, read the old element, store
	old plus or minus 1, then yield the old value (postfix) or the new value
	(prefix). The array and index expressions run once, in source order.
	`Int`, `Float`, `Null<Int>`, and `Null<Float>` elements are lowered (see
	`steppedType`); other element types, and other indexed receivers such as
	abstracts with `@:arrayAccess`, keep their existing owners.
 */
private function lowerIndexedStep(expression:TypedExpr, operand:TypedExpr, allocator:TyCompilerTemporaryAllocator):TypedExpr {
	final parts = operand.getExpressions();
	if (parts.length != 2)
		return expression;
	final array = parts[0];
	final index = parts[1];
	final arrayType = TyAliasExpansion.reveal(array.getType());
	final identity = arrayType.getNominalIdentity();
	if (identity == null || identity.getCanonicalName() != "Array" || arrayType.getTypeArguments().length != 1)
		return expression;
	final elementType = operand.getType();
	final stepType = steppedType(elementType);
	if (stepType == null)
		return expression;
	final key = stepType.getSemanticKey();
	final position = expression.getPosition();
	function read(binding:TyLocalBinding):TypedExpr
		return TypedExpr.localRead(binding.getSourceName(), binding.getType(), position, binding);
	function capture(binding:TyLocalBinding, value:TypedExpr):TypedExpr
		return TypedExpr.temporary(binding.getSourceName(), binding.getType().getCanonicalDisplay(), value, TyType.fromHintText("Void"), position, binding);
	final arrayBinding = allocator.allocate("array", array.getType());
	final indexBinding = allocator.allocate("index", index.getType());
	final oldBinding = allocator.allocate("old", elementType);
	final nextBinding = allocator.allocate("next", stepType);
	final place = TypedExpr.arrayAccess(read(arrayBinding), read(indexBinding), elementType, position);
	final one = key == "primitive:Int" ? TypedExpr.intLiteral(1, stepType, position) : TypedExpr.floatLiteral(1.0, stepType, position);
	final next = TypedExpr.binary(expression.getUnaryOperator() == HxUnaryOperator.Increment ? "+" : "-", read(oldBinding), one, stepType, position);
	final result = read(expression.getUnaryFixity() == HxUnaryFixity.Postfix ? oldBinding : nextBinding);
	// Binding types follow the values they hold; see `steppedType`.
	return TypedExpr.block([
		capture(arrayBinding, array),
		capture(indexBinding, index),
		capture(oldBinding, place),
		capture(nextBinding, TypedExpr.assign(place, next, stepType, position)),
		result
	], result.getType(), position);
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
