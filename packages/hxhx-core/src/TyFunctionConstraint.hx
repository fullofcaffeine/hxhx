/**
	Haxe's `haxe.Constraints.Function` accepts any function value.

	`Function` is declared as `@:callable abstract Function(Dynamic) {}` with
	no `@:from` conversion. Upstream Haxe 4.3.7 still lets every function type
	unify with it: a method, a static function or a local function can be passed
	where a `Function` is expected, as in
	`Reflect.callMethod(holder, holder.add, [7])`.
	The rule is directional. A `Function` value is not accepted where a
	concrete function signature is expected, and a non-callable value is never
	a `Function`. A nullable destination (`Null<Function>`, `?f:Function`)
	follows the same rule.
**/
class TyFunctionConstraint {
	public static inline final CANONICAL_NAME = "haxe.Constraints.Function";

	/** Whether `type` is `haxe.Constraints.Function`, or `Null` of it. */
	public static function isFunctionConstraint(type:Null<TyType>):Bool {
		if (type == null)
			return false;
		final identity = type.unwrapNull().getNominalIdentity();
		return identity != null && identity.getCanonicalName() == CANONICAL_NAME;
	}

	/** Whether a value of type `actual` may be assigned to `expected` by this rule. */
	public static function accepts(expected:Null<TyType>, actual:Null<TyType>):Bool
		return isFunctionConstraint(expected) && actual != null && actual.isFunction();

	/** Whether `type` mentions `Function` directly, as a type argument, or as a structure field. */
	public static function mentions(type:Null<TyType>):Bool {
		if (type == null)
			return false;
		if (isFunctionConstraint(type))
			return true;
		final concrete = type.unwrapNull();
		for (component in concrete.getTypeArguments().concat(concrete.getAnonymousFieldTypes()))
			if (mentions(component))
				return true;
		return false;
	}

	/**
		Whether storing a `value` in a `destination` puts a function value in a
		`Function` slot, either directly or inside a structure field or a type
		argument of the same type constructor.
	**/
	public static function reaches(destination:Null<TyType>, value:Null<TyType>):Bool {
		if (destination == null || value == null)
			return false;
		if (accepts(destination, value))
			return true;
		final target = destination.unwrapNull();
		final source = value.unwrapNull();
		if (target.isAnonymous() && source.isAnonymous()) {
			final names = source.getAnonymousFieldNames();
			final types = source.getAnonymousFieldTypes();
			final targetNames = target.getAnonymousFieldNames();
			final targetTypes = target.getAnonymousFieldTypes();
			for (index in 0...targetNames.length) {
				final at = names.indexOf(targetNames[index]);
				if (at >= 0 && reaches(targetTypes[index], types[at]))
					return true;
			}
			return false;
		}
		final targets = target.getTypeArguments();
		final sources = source.getTypeArguments();
		if (targets.length == 0 || targets.length != sources.length)
			return false;
		for (index in 0...targets.length)
			if (reaches(targets[index], sources[index]))
				return true;
		return false;
	}
}
