package backend.ocaml;

/**
	Reads the module-local function name that an OCaml call-graph edge targets.

	OCaml requires a function binding to appear before a separate caller binding.
	The emitter uses this adapter while ordering functions, so every call encoding
	that can later emit a local call must report the same callee name here.
**/
class OcamlLocalCallDependency {
	public static function calleeName(expression:HxExpr):Null<String> {
		final exactInstanceCall = TypedExactCallSource.decodeInstance(expression);
		if (exactInstanceCall != null)
			return exactInstanceCall.method;
		return switch (expression) {
			case ECall(EIdent(name), _): name;
			case ECall(EField(_, field), _): field;
			case _: null;
		};
	}
}
