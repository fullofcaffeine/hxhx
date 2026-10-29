package backend.vm;

/**
	Explicit VM object operations keep reflection policy in the authored provider.
	Callers exclude resolved class members. Reserved local aliases still select
	the native operation, as they do in upstream Neko.
 */
function renderCall(callee:HxExpr, arguments:Array<String>):Null<String> {
	final selected = switch callee {
		case EIdent("__dollar__typeof") | EIdent("$typeof"): {symbol: "$typeof", arity: 1};
		case EIdent("__dollar__hash") | EIdent("$hash"): {symbol: "$hash", arity: 1};
		case EIdent("__dollar__objset") | EIdent("$objset"): {symbol: "$objset", arity: 3};
		case _: null;
	};
	if (selected == null)
		return null;
	if (arguments.length != selected.arity)
		throw "Neko " + selected.symbol + " requires " + selected.arity + " operands";
	return selected.symbol + "(" + arguments.join(", ") + ")";
}

/** The reserved object-kind alias denotes the VM constant, including when a local shares its spelling. */
function renderValue(name:String):Null<String>
	return name == "__dollar__tobject" || name == "$tobject" ? "$tobject" : null;
