package backend.vm;

/**
	Lower explicit VM call operations used by the authored reflection provider.
	The provider owns argument padding and Array-to-native conversion; these
	primitives only expose the VM's fixed-arity query and receiver-aware call.
 */
function renderCall(callee:HxExpr, arguments:Array<String>):Null<String> {
	final selected = switch callee {
		case EIdent("__dollar__nargs") | EIdent("$nargs"): {symbol: "$nargs", arity: 1};
		case EIdent("__dollar__call") | EIdent("$call"): {symbol: "$call", arity: 3};
		case _: null;
	};
	if (selected == null)
		return null;
	if (arguments.length != selected.arity)
		throw "Neko " + selected.symbol + " requires " + selected.arity + " operands";
	return selected.symbol + "(" + arguments.join(", ") + ")";
}
