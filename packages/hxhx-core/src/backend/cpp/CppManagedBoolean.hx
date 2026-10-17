package backend.cpp;

/** Only Boolean values and one nullable Boolean wrapper may select control branches. */
function supportsCondition(type:TyType):Bool
	return type.getSemanticKey() == "primitive:Bool" || type.getSemanticKey() == "nullable:primitive:Bool";

/** Equality preserves nullable identity: an absent Boolean is distinct from false. */
function supportsEquality(op:String, left:TyType, right:TyType):Bool
	return (op == "==" || op == "!=") && supportsCondition(left) && supportsCondition(right);

/** Both operands are already rooted and evaluated; only present Boolean payloads may be read. */
function compare(op:String, leftType:TyType, rightType:TyType, left:String, right:String, destination:String, indent:String):Array<String> {
	if (!supportsEquality(op, leftType, rightType))
		throw "managed Boolean equality requires exact Bool or nullable Bool operands";
	final a = "(" + left + ".kind() == hxhx::managed::ValueKind::Null)";
	final b = "(" + right + ".kind() == hxhx::managed::ValueKind::Null)";
	final equality = leftType.isNullable()
		|| rightType.isNullable() ? "(("
			+ a
			+ " || "
			+ b
			+ ") ? ("
			+ a
			+ " && "
			+ b
			+ ") : ("
			+ left
			+ ".asBoolean() == "
			+ right
			+ ".asBoolean()))" : "("
			+ left
			+ ".asBoolean() == "
			+ right
			+ ".asBoolean())";
	return [
		indent + destination + ".set(hxhx::managed::Value::boolean(" + (op == "!=" ? "!" : "") + equality + "));"
	];
}

/**
	Read an already evaluated value as a native condition. An absent nullable Bool
	selects the false branch without changing its stored value. This is a condition
	read, not permission to convert arbitrary Dynamic values or logical results.
 */
function conditionValue(type:TyType, value:String):String {
	if (!supportsCondition(type))
		throw "managed condition requires Bool or nullable Bool";
	final read = CppManagedLeaf.read(TyType.fromHintText("Bool"), value);
	return type.isNullable() ? "(" + value + ".kind() != hxhx::managed::ValueKind::Null && " + read + ")" : read;
}

/** Validate condition operands without assigning a stored type to a logical result. */
function requireCondition(value:HxExpr, valueType:HxExpr->TyType, requireExpression:HxExpr->Void, ?checkedCondition:HxExpr->Null<TyType>):Void {
	requireExpression(value);
	switch value {
		case EParenthesized(inner, _) | EUntyped(inner) | EUnop(LogicalNot, Prefix, inner):
			requireCondition(inner, valueType, requireExpression, checkedCondition);
		case EBinop(op, left, right) if (op == "&&" || op == "||"):
			requireCondition(left, valueType, requireExpression, checkedCondition);
			requireCondition(right, valueType, requireExpression, checkedCondition);
		case ETernary(condition, yes, no):
			for (part in [condition, yes, no])
				requireCondition(part, valueType, requireExpression, checkedCondition);
		case _:
			if (!supportsCondition(valueType(value)) && !checkedDynamic(value, valueType(value), checkedCondition))
				throw "managed condition requires Bool or nullable Bool";
	}
}

/** A Dynamic storage type alone cannot authorize a Boolean conversion outside a checked condition. */
private function checkedDynamic(value:HxExpr, type:TyType, checkedCondition:Null<HxExpr->Null<TyType>>):Bool {
	if (!type.isDynamic() || checkedCondition == null)
		return false;
	final checked = checkedCondition(value);
	return checked != null && checked.getSemanticKey() == type.getSemanticKey();
}

/**
	Native Boolean operators preserve short-circuit order for condition-only reads.
	Each leaf stays rooted until its truth is read; only a native Bool leaves its
	scope. No nullable logical value is stored or converted by this path.
 */
function renderCondition(value:HxExpr, input:{
	heap:String,
	prefix:String,
	valueType:HxExpr->TyType,
	requireExpression:HxExpr->Void,
	?checkedCondition:HxExpr->Null<TyType>,
	renderValue:(HxExpr, String, String) -> Array<String>
}):String {
	input.requireExpression(value);
	return switch value {
		case EParenthesized(inner, _) | EUntyped(inner): renderCondition(inner, input);
		case EUnop(LogicalNot, Prefix, inner): "!(" + renderCondition(inner, input) + ")";
		case EBinop(op, left, right) if (op == "&&" || op == "||"):
			"("
			+ renderCondition(left, input)
			+ " "
			+ op
			+ " "
			+ renderCondition(right, input)
			+ ")";
		case ETernary(condition, yes, no):
			"("
			+ renderCondition(condition, input)
			+ " ? "
			+ renderCondition(yes, input)
			+ " : "
			+ renderCondition(no, input)
			+ ")";
		case _:
			final type = input.valueType(value);
			final root = input.prefix + "condition";
			final test = checkedDynamic(value, type,
				input.checkedCondition) ? CppManagedDynamicCondition.read(root + ".get()") : conditionValue(type, root + ".get()");
			final lines = [
				"([&]() -> bool {",
				"  hxhx::managed::Root<hxhx::managed::Value> " + root + "(" + input.heap + ");"
			];
			for (line in input.renderValue(value, root, "  "))
				lines.push(line);
			lines.push("  return " + test + ";");
			lines.push("}())");
			lines.join("\n");
	};
}

/** Boolean operators retain source short-circuit effects while using ordinary rooted value transport. */
function resultType(op:String, left:TyType, right:TyType):TyType {
	if ((op != "&&" && op != "||") || left.getSemanticKey() != "primitive:Bool" || right.getSemanticKey() != "primitive:Bool")
		throw "managed logical operation requires two exact Bool operands";
	return TyType.fromHintText("Bool");
}

/** Evaluate the right operand only when the left value cannot determine the result. */
function render(input:{
	op:String,
	left:HxExpr,
	right:HxExpr,
	heap:String,
	destination:String,
	renderValue:(HxExpr, String, String) -> Array<String>
}, indent:String):Array<String> {
	final test = input.destination + "_logical_left";
	final lines = [
		indent + "{",
		indent + "  hxhx::managed::Root<hxhx::managed::Value> " + test + "(" + input.heap + ");"
	];
	for (line in input.renderValue(input.left, test, indent + "  "))
		lines.push(line);
	lines.push(indent + "  if (" + (input.op == "&&" ? "" : "!") + test + ".get().asBoolean()) {");
	for (line in input.renderValue(input.right, input.destination, indent + "    "))
		lines.push(line);
	lines.push(indent + "  } else {");
	lines.push(indent + "    " + input.destination + ".set(" + test + ".get());");
	lines.push(indent + "  }");
	lines.push(indent + "}");
	return lines;
}
