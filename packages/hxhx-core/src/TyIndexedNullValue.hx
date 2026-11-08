/**
	Whether a `null` literal may be passed as the value of a declared indexed setter
	(`b[i] = null`) whose value parameter cannot ordinarily hold null, such as `Int`.

	Why: Haxe 4.3.7 accepts `b[i] = null` through `set(i:Int, v:Int)` on JavaScript,
	C++, HashLink, Java and the other targets it was checked on, even where an
	ordinary call `f(null)` to an `Int` parameter is rejected. Only C# rejects the
	write, with "On static platforms, null can't be used as basic type Int".

	What: `admits` returns true when `actual` is the null literal and the parameter
	is a known type that `TyNullArgument.acceptsLiteral` does not already admit. The
	caller then scores the value as `Null<parameter>`, so setter selection and the
	generated call keep the declared parameter. After selection, `checkTarget`
	applies the C# rule to the specialized value parameter, so a generic setter
	`write<T>(s:S<T>, i:Int, v:T)` on `S<Int>` is rejected there too. This rule is
	for indexed setters only; ordinary call arguments keep their own selection rules.
**/
function admits(actual:TyType, parameter:Null<TyType>, index:TyperIndex):Bool {
	return actual.isNullLiteral()
		&& parameter != null
		&& !parameter.hasUnknownComponent()
		&& !TyNullArgument.acceptsLiteral(parameter, index);
}

/** Throw the upstream C# diagnostic when a null literal reaches a basic-type setter parameter. */
function checkTarget(actual:TyType, parameter:Null<TyType>, hint:Null<String>, ctx:TyperContext, pos:HxPos):Void {
	if (!admits(actual, parameter, ctx.getIndex()))
		return;
	if (ctx.hasDefine("cs"))
		throw new TyperError(ctx.getFilePath(), pos, "On static platforms, null can't be used as basic type " + parameter.getDisplay());
	// The native setter call reads the same written parameter type as an ordinary call.
	if (TyBasicNullArgument.nativeUnsupported(parameter, hint, ctx))
		throw TyBasicNullArgument.nativeUnsupportedError(parameter, ctx, pos);
}
