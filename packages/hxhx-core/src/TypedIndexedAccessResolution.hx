/** Replay one exact indexed selection using the same call plan as an ordinary method invocation. */
typedef TypedIndexedAccessResolution = {
	final binding:TyIndexedAccessBinding;
	final call:Null<TypedCallResolution>;

	/**
		The selected helper's own result type. It differs from the authored
		expression's type only for `untyped b[i] = v`, whose untyped wrapper
		leaves the assignment result unconstrained while the setter call keeps
		its declared result.
	**/
	final ?result:TyType;
}
