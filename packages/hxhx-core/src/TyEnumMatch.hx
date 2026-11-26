/**
	`e.match(pattern)` on an enum value is a one-case switch.

	Why
	- Haxe 4.3.7 types `e.match(pattern)` as `switch e { case pattern: true; case _: false }` with
	  type Bool when `e`'s type follows to an enum, or to a `@:forward` abstract over one that is
	  not a `@:coreType` and declares no `match` of its own (typer.ml:1802-1814). Otherwise the
	  call is ordinary: `EReg.match(s)` stays a method call.
	- hxhx typed the pattern as a call argument, so a wildcard inside a constructor became an
	  unknown argument to the constructor and `c.match(CString(_, SingleQuotes))` failed
	  (haxe_ocaml-56lt0, haxe_ocaml-d592g).

	How
	- `switchFor` returns that switch, built from the subject and the converted pattern, or null.
	  The typer types the switch in place of the call, and the typed body holds only the switch,
	  so the subject is evaluated once, as the scrutinee, and every backend lowers an ordinary
	  switch.
	- An argument that `HxMatchPattern` cannot read keeps the ordinary call.
**/
final class TyEnumMatch {
	public static function switchFor(subject:HxExpr, argument:HxExpr, subjectType:TyType, context:TyperContext, position:HxPos):Null<HxExpr> {
		final pattern = HxMatchPattern.fromExpr(argument);
		if (pattern == null || !hasEnumMatch(subjectType, context.getIndex(), []))
			return null;
		if (HxMatchPattern.captures(pattern))
			throw new TyperError(context.getFilePath(), position, "Pattern variables are not allowed in .match patterns");
		return ESwitch(subject, [pattern, PWildcard], [EBool(true), EBool(false)]);
	}

	/** typer.ml:1804-1810: `has_enum_match`. */
	static function hasEnumMatch(type:TyType, index:Null<TyperIndex>, visited:Array<String>):Bool {
		if (type == null || index == null)
			return false;
		final value = TyAliasExpansion.revealNonNullable(type);
		final identity = value.getNominalIdentity();
		if (identity == null)
			return false;
		final name = identity.getCanonicalName();
		final nominal = index.getByFullName(name);
		if (nominal != null && nominal.getIsEnum())
			return true;
		final abstractInfo = index.getAbstractByFullName(name);
		if (abstractInfo == null || !abstractInfo.isForwarding() || abstractInfo.isCoreType() || visited.indexOf(name) >= 0)
			return false;
		if (abstractInfo.instanceMethod("match") != null)
			return false;
		if (abstractInfo.getTypeParameterIds().length != value.getTypeArguments().length)
			return false;
		final underlying = TyTypeSubstitution.apply(abstractInfo.getUnderlyingType(),
			TyTypeSubstitution.bind(abstractInfo.getTypeParameterIds(), value.getTypeArguments(), name));
		return hasEnumMatch(underlying, index, visited.concat([name]));
	}
}
