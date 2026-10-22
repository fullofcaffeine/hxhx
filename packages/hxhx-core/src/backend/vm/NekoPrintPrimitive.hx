package backend.vm;

/** Emit the reserved VM print operation, using each ordered operand once. Resolved class members take precedence. */
function renderCall(callee:HxExpr, arguments:Array<String>):Null<String> {
	return switch callee {
		case EIdent("__dollar__print") | EIdent("$print"): "$print(" + arguments.join(", ") + ")";
		case _: null;
	};
}
