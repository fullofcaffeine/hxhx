package backend.vm;

/** Emit reserved native-array construction and length operations with each operand used once. */
function renderCall(callee:HxExpr, arguments:Array<String>):Null<String> {
	return switch callee {
		case EIdent("__dollar__array") | EIdent("$array"):
			"$array(" + arguments.join(", ") + ")";
		case EIdent("__dollar__asize") | EIdent("$asize"):
			if (arguments.length != 1)
				throw "Neko primitive $asize requires 1 argument, got " + arguments.length;
			"$asize(" + arguments[0] + ")";
		case _: null;
	};
}
