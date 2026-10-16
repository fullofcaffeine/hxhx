package backend.vm;

/**
	Emit the fixed-size VM array operations used by the authored Neko providers.
	Allocation, overlapping copies, and slicing keep the VM's native bounds and
	copy semantics. Resizing a Haxe Array remains the Array provider's responsibility.
	The caller excludes declared Haxe methods before selecting reserved primitives.
 */
function renderCall(callee:HxExpr, arguments:Array<String>):Null<String> {
	return switch callee {
		case EIdent("__dollar__array") | EIdent("$array"):
			"$array(" + arguments.join(", ") + ")";
		case EIdent("__dollar__asize") | EIdent("$asize"):
			renderPrimitive("$asize", 1, arguments);
		case EIdent("__dollar__amake") | EIdent("$amake"):
			renderPrimitive("$amake", 1, arguments);
		case EIdent("__dollar__ablit") | EIdent("$ablit"):
			renderPrimitive("$ablit", 5, arguments);
		case EIdent("__dollar__asub") | EIdent("$asub"):
			renderPrimitive("$asub", 3, arguments);
		case _: null;
	};
}

/** Reject malformed primitive calls without duplicating or reordering their operands. */
private function renderPrimitive(symbol:String, arity:Int, arguments:Array<String>):String {
	if (arguments.length != arity)
		throw "Neko primitive "
			+ symbol
			+ " requires "
			+ arity
			+ (arity == 1 ? " argument" : " arguments")
			+ ", got "
			+ arguments.length;
	return symbol + "(" + arguments.join(", ") + ")";
}
