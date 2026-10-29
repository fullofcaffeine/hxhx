/**
	Identify operands that describe JavaScript syntax instead of runtime values.

	The selected js.Syntax declaration authorizes native syntax emission. Saving
	its callee as a function would lose that declaration and read a nonexistent
	runtime member. Likewise, code's template and construct's literal class name
	must remain syntax. Other operands still evaluate in source order before a
	later statement-valued argument. Ordinary methods retain callable capture.
 */
function retainsOperand(call:TypedExpr, index:Int, operand:TypedExpr):Bool {
	final declaration = call.getDeclaration();
	if (call.getTag() != Call
		|| declaration == null
		|| !declaration.getIsStatic()
		|| declaration.getHasBody()
		|| declaration.getOwner().getCanonicalName() != "js.Syntax"
		|| declaration.getModulePath() != "js.Syntax")
		return false;
	return switch declaration.getSignature().getName() {
		case "code": index == 0 || index == 1;
		case "construct": index == 0 || (index == 1 && operand.getTag() == StringValue);
		case "typeof" | "delete": index == 0;
		case _: false;
	};
}
