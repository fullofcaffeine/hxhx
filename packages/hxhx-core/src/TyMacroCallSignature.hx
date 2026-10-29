/**
	The call-site contract of a `macro` function.

	What
	- A macro method declares `haxe.macro.Expr` parameters (or `ExprOf<T>`, an
	  alias of `Expr`), but its callers pass ordinary source expressions. Haxe
	  hands each such argument to the macro as syntax, so any expression is a
	  valid operand at that position.
	- A trailing `Array<Expr>` parameter collects every remaining argument, so it
	  is a rest position at the call site (for example
	  `python.Syntax.arrayAccess(x, rest:Array<Expr>)` accepts `arrayAccess(b, pos)`).
	- The value of the call is whatever the returned expression types to. The
	  declared `Expr` result describes the macro's output syntax, not the call's
	  value. Without that expansion the call is typed as `Dynamic`, so the
	  surrounding code is checked exactly as it would be around an expansion
	  of unknown static type (`ord(Syntax.arrayAccess(s, i))`).

	Why
	- Method selection otherwise compares a `python.Bytearray` operand with the
	  structural `Expr` type and rejects the only declaration of a valid call.

	How
	- The declaration and its stored signature stay unchanged: the macro body
	  still sees its declared `Expr` and `Array<Expr>` types. Only the signature
	  that call selection scores is rewritten. Parameters with other types, such
	  as `String` constants, keep their declared types and ordinary checks.
 */
final class TyMacroCallSignature {
	static inline final MACRO_METADATA = "macro";

	/** A declaration written with the `macro` modifier. */
	public static function isMacro(declaration:Null<TyDeclarationInfo>):Bool
		return declaration != null && declaration.getMetadata().indexOf(MACRO_METADATA) >= 0;

	/**
		Rewrite a resolved macro signature into the contract its callers satisfy.

		`expr` is the resolved `haxe.macro.Expr` type in the caller's index. Syntax
		positions become `Dynamic`; a trailing `Array<Expr>` becomes a rest position
		of `Dynamic` elements; the call result becomes `Dynamic`.
	**/
	public static function callSite(signature:TyFunSig, expr:TyType):TyFunSig {
		final exprKey = expr.getSemanticKey();
		final declared = signature.getArgs();
		final args = new Array<TyType>();
		final rest = signature.getArgRest().copy();
		for (index in 0...declared.length) {
			final type = declared[index];
			final isLast = index == declared.length - 1;
			if (type.getSemanticKey() == exprKey) {
				args.push(TyType.fromHintText("Dynamic"));
			} else if (isLast && isExprArray(type, exprKey) && !(index < rest.length && rest[index])) {
				args.push(TyType.fromHintText("Array<Dynamic>"));
				while (rest.length <= index)
					rest.push(false);
				rest[index] = true;
			} else {
				args.push(type);
			}
		}
		return new TyFunSig(signature.getName(), signature.getIsStatic(), signature.getArgNames(), args, signature.getArgOptional(), rest,
			TyType.fromHintText("Dynamic"), signature.getPos());
	}

	static function isExprArray(type:TyType, exprKey:String):Bool {
		final identity = type.getNominalIdentity();
		final arguments = type.getTypeArguments();
		return identity != null
			&& identity.getCanonicalName() == "Array"
			&& arguments.length == 1
			&& arguments[0].getSemanticKey() == exprKey;
	}
}
