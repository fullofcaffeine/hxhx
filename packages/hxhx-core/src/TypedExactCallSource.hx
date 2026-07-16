typedef TypedExactInstanceCall = {
	final owner:String;
	final declaration:String;
	final method:String;
	final resultType:String;
	final receiver:HxExpr;
	final arguments:Array<HxExpr>;
};

/**
	Carries an exact typed instance call through the temporary source-shaped
	backend adapter.

	The typed tree remains authoritative. This intrinsic is a structural encoding
	of its selected declaration, not a lookup request: source-style backends unwrap
	it to the original receiver call, while representation backends can invoke the
	exact owner ABI without rediscovering an abstract from a carrier type or method
	name. Keeping the declaration key in the payload also makes semantic dumps and
	invariant failures deterministic during the typed-body migration.
**/
class TypedExactCallSource {
	public static inline final INSTANCE_INTRINSIC = "__hxhx_exact_instance_call";

	public static function encodeInstance(owner:String, declaration:String, method:String, resultType:String, receiver:HxExpr, arguments:Array<HxExpr>):HxExpr {
		final payload:Array<HxExpr> = [
			HxExpr.EString(owner == null ? "" : owner),
			HxExpr.EString(declaration == null ? "" : declaration),
			HxExpr.EString(method == null ? "" : method),
			HxExpr.EString(resultType == null ? "" : resultType),
			receiver
		];
		return HxExpr.ECall(HxExpr.EIdent(INSTANCE_INTRINSIC), payload.concat(arguments == null ? [] : arguments));
	}

	public static function decodeInstance(expression:HxExpr):Null<TypedExactInstanceCall> {
		return switch (expression) {
			case ECall(EIdent(INSTANCE_INTRINSIC), payload) if (payload.length >= 5):
				switch (payload) {
					case [
						EString(owner),
						EString(declaration),
						EString(method),
						EString(resultType),
						receiver
					]:
						{
							owner: owner,
							declaration: declaration,
							method: method,
							resultType: resultType,
							receiver: receiver,
							arguments: []
						};
					case _:
						switch (payload[0]) {
							case EString(owner):
								switch (payload[1]) {
									case EString(declaration):
										switch (payload[2]) {
											case EString(method):
												switch (payload[3]) {
													case EString(resultType):
														{
															owner: owner,
															declaration: declaration,
															method: method,
															resultType: resultType,
															receiver: payload[4],
															arguments: payload.slice(5)
														};
													case _:
														null;
												}
											case _:
												null;
										}
									case _:
										null;
								}
							case _:
								null;
						}
				}
			case _:
				null;
		};
	}

	/** Rebuild the ordinary receiver call used by source-shaped target emitters. **/
	public static function ordinaryInstanceCall(exact:TypedExactInstanceCall):HxExpr
		return ECall(EField(exact.receiver, exact.method), exact.arguments.copy());
}
