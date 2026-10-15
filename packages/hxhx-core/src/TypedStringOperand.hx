/**
	Expose a declared integer view for an abstract's default String concatenation.
	For example, Int32 declares an Int backing and an identity-preserving `to Int`
	conversion. Keeping that proof in the typed expression lets each backend use
	its existing integer formatter without guessing from a nominal type name.

	An authored toString or String conversion takes precedence. Those operands
	retain their original type until their own conversion path is selected; this
	function never replaces their behavior with the backing integer's spelling.
 */
function lower(value:TypedExpr, index:TyperIndex):TypedExpr {
	final actual = value.getType();
	final identity = actual.getNominalIdentity();
	final owner = identity == null ? null : index.getAbstractByFullName(identity.getCanonicalName());
	if (owner == null || owner.instanceMethodCandidates("toString").length != 0)
		return value;
	final stringType = TyType.fromHintText("String");
	if (TyImplicitConversionPlan.select(index, stringType, actual) != null
		|| TyAbstractMethodConversion.select(index, stringType, actual) != null)
		return value;
	final conversion = TyImplicitConversionPlan.select(index, TyType.fromHintText("Int"), actual);
	return conversion != null
		&& conversion.isAbstractTo()
		&& conversion.isRepresentationPreservingAbstractConversion() ? conversion.apply(value) : value;
}
