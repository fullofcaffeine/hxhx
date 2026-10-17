/**
	The Neko core String's reserved backing read exposes neko.NativeString.
	Resolve that real declaration before control lowering stores an operand in
	a temporary. This boundary does not change ordinary object fields, foreign
	String classes, Dynamic receivers, or another target's string representation.
 */
function resolve(receiver:TyType, field:String, context:TyperContext):Null<TyType> {
	if (field != "__s" || !context.hasDefine("neko"))
		return null;
	final actual = receiver.unwrapNull();
	final identity = actual.getNominalIdentity();
	if (actual.getSemanticKey() != "primitive:String" && (identity == null || identity.getCanonicalName() != "String"))
		return null;
	final provider = context.resolveType("neko.NativeString");
	if (provider == null || provider.getIdentity().getCanonicalName() != "neko.NativeString")
		return null;
	return TyType.nominal(provider.getIdentity(), []);
}
