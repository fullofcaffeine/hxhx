/**
	Haxe's `haxe.Constraints.Function` accepts any function value.

	`Function` is declared as `abstract Function(Dynamic) {}` with no `@:from`
	conversion. Upstream Haxe 4.3.7 still lets every function type unify with
	it: a method, a static function or a local function can be passed where a
	`Function` is expected, as in `Reflect.callMethod(holder, holder.add, [7])`.
	The rule is directional. A `Function` value is not accepted where a
	concrete function signature is expected, and a non-callable value is never
	a `Function`.
**/
class TyFunctionConstraint {
	public static inline final CANONICAL_NAME = "haxe.Constraints.Function";

	/** Whether `type` is exactly `haxe.Constraints.Function`. */
	public static function isFunctionConstraint(type:Null<TyType>):Bool {
		if (type == null)
			return false;
		final identity = type.getNominalIdentity();
		return identity != null && identity.getCanonicalName() == CANONICAL_NAME;
	}

	/** Whether a value of type `actual` may be assigned to `expected` by this rule. */
	public static function accepts(expected:Null<TyType>, actual:Null<TyType>):Bool
		return isFunctionConstraint(expected) && actual != null && actual.isFunction();
}
