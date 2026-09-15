package backend.vm;

/**
	Emits reserved VM stack calls and the native-array length operation used to
	inspect their results. Callers exclude resolved class members first. Local
	reserved aliases still denote primitives, matching upstream Neko behavior.
	Arguments arrive in source order and appear exactly once in the output.
**/
function renderCall(callee:HxExpr, arguments:Array<String>):Null<String> {
	final primitive:Null<{symbol:String, arity:Int}> = switch (callee) {
		case EIdent("__dollar__callstack") | EIdent("$callstack"): {symbol: "$callstack", arity: 0};
		case EIdent("__dollar__excstack") | EIdent("$excstack"): {symbol: "$excstack", arity: 0};
		case EIdent("__dollar__asize") | EIdent("$asize"): {symbol: "$asize", arity: 1};
		case _: null;
	};
	if (primitive == null)
		return null;
	if (arguments.length != primitive.arity)
		throw "Neko primitive " + primitive.symbol + " requires " + primitive.arity + (primitive.arity == 1 ? " argument" : " arguments") + ", got "
			+ arguments.length;
	return primitive.symbol + "(" + arguments.join(", ") + ")";
}
