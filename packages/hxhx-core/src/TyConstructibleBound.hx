/**
	Whether a class satisfies a `haxe.Constraints.Constructible<F>` bound.

	Haxe 4.3.7 (tUnification.ml:824-838) accepts a class instance type when the class has a
	public constructor, its own or the nearest inherited one, whose type unifies with F. Without
	a constructor the bound fails ("has no field new"), and a non-public one fails too ("The field
	new is not public"). A type parameter instead needs an equal Constructible bound of its own;
	the caller's parameter-bound proof already compares those (haxe_ocaml-g3l8y).

	`fits(expected, actual)` is the caller's function-type acceptance for the constructor type
	against F.
**/
function accepts(index:TyperIndex, target:TyType, actual:TyType, fits:(TyType, TyType) -> Bool):Null<Bool> {
	final identity = target.getNominalIdentity();
	if (identity == null || identity.getCanonicalName() != "haxe.Constraints.Constructible" || target.getTypeArguments().length != 1)
		return null;
	final expected = target.getTypeArguments()[0];
	if (actual.getTypeParameterIdentity() != null || actual.getNominalIdentity() == null)
		return false;
	final path = TypedConstructorPath.select(index, actual);
	if (path == null || !Std.isOfType(path.getOwner(), TyClassInfo))
		return false;
	final owner = path.getOwner();
	final ownerType = path.getOwnerType();
	final bindings = TyTypeSubstitution.bind(TyNominalApplication.parameterIds(owner), ownerType.getTypeArguments(), owner.getIdentity().getCanonicalName());
	for (signature in owner.instanceMethodCandidates("new")) {
		final declaration = owner.declarationForSignature(signature);
		if (declaration == null || !declaration.getIsPublic())
			continue;
		final callable = TyTypeSubstitution.apply(TyCallableSignature.fromDeclaration(declaration, signature).getFunctionType(), bindings);
		// Upstream's constructor field type returns Void, not the allocated instance.
		final constructor = callable.withFunctionTypes(callable.getFunctionArguments(), TyType.fromHintText("Void"));
		if (fits(expected, constructor))
			return true;
	}
	return false;
}
