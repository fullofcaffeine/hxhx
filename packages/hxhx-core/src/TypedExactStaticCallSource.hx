/** A selected static declaration paired with its original call shape and ordered arguments. */
typedef TypedExactStaticCall = {
	final owner:String;
	final declaration:String;
	final method:String;
	final resultType:String;
	final callee:HxExpr;
	final arguments:Array<HxExpr>;
};

/**
	Preserve static-call selection across the temporary source-shaped backend adapter.

	The typed tree owns declaration selection. Source emitters can restore the
	ordinary call while representation backends consume its exact owner and body.
	The original callee preserves existing alias and builtin rendering behavior.
**/
class TypedExactStaticCallSource {
	public static inline final INTRINSIC = "__hxhx_exact_static_call";

	public static function encode(owner:String, declaration:String, method:String, resultType:String, callee:HxExpr, arguments:Array<HxExpr>):HxExpr {
		final payload:Array<HxExpr> = [
			EString(owner),
			EString(declaration),
			EString(method),
			EString(resultType),
			callee
		];
		return ECall(EIdent(INTRINSIC), payload.concat(arguments));
	}

	/** Ordinary expressions return null; a malformed reserved payload must not become an ordinary call. */
	public static function decode(expression:HxExpr):Null<TypedExactStaticCall> {
		final payload = switch (expression) {
			case ECall(EIdent(INTRINSIC), arguments): arguments;
			case _: return null;
		};
		if (payload.length < 5)
			throw "exact static call contains a malformed typed payload";
		return switch (payload.slice(0, 4)) {
			case [EString(owner), EString(declaration), EString(method), EString(resultType)]:
				if (owner.length == 0 || declaration.length == 0 || method.length == 0 || resultType.length == 0)
					throw "exact static call contains empty typed identities";
				{
					owner: owner,
					declaration: declaration,
					method: method,
					resultType: resultType,
					callee: payload[4],
					arguments: payload.slice(5)
				};
			case _: throw "exact static call contains a malformed typed payload";
		};
	}

	/** Restore the source call without changing argument evaluation order. */
	public static function ordinaryCall(call:TypedExactStaticCall):HxExpr
		return ECall(call.callee, call.arguments.copy());
}
