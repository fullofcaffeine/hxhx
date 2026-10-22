/** A concrete enum value can supply EnumValue without changing its stored representation. */
function accepts(index:TyperIndex, expected:TyType, actual:TyType):Bool {
	if (index == null || expected == null || actual == null)
		return false;
	final target = expected.unwrapNull();
	final source = actual.unwrapNull();
	final targetIdentity = target.getNominalIdentity();
	if (targetIdentity == null
		|| targetIdentity.getCanonicalName() != "EnumValue"
		|| target.getTypeArguments().length != 0
		|| index.getAbstractByFullName("EnumValue") == null)
		return false;
	return TyCallerConstraintProof.accepts(target, source, index.getParameterBounds, (_, concrete) -> {
		final identity = concrete.getNominalIdentity();
		final provider = identity == null ? null : index.getByFullName(identity.getCanonicalName());
		return provider != null && provider.getIsEnum();
	});
}
