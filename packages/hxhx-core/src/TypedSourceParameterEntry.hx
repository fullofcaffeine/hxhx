/**
 * Give a concrete defaulted parameter nullable incoming storage without changing
 * the authored body binding. Defaults run before that binding is initialized;
 * mutations and escaping closures continue to share the authored declaration.
 */
function binding(source:TyLocalBinding, hasDefault:Bool):TyLocalBinding {
	if (!hasDefault || source.getType().isNullable())
		return source;
	final identity = TyLocalId.forCompilerTemporary(source.getIdentity().getOwnerIdentity(),
		"source-parameter-entry-v1:" + source.getIdentity().getCanonicalKey(), 0, source.getSourceName());
	return new TyLocalBinding(identity, source.getSourceName(), TyType.nullable(source.getType()), CompilerTemporary);
}
