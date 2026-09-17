/**
	A source-shaped field initializer paired with its exact typed catalogs.

	Field initializers execute outside ordinary methods, but a lambda or block
	inside one can still declare locals and read current-class fields. Keeping
	the projected declaration, stable initializer revision, exact local
	bindings, and exact field reads together lets a backend render that
	executable unit without borrowing mutable state from an unrelated function.
**/
class TypedBackendFieldInitializerProjection {
	final stableIdentity:String;
	final bodyRevision:String;
	final field:TyFieldInfo;
	final declaration:HxFieldDecl;
	final localCatalog:TypedBackendLocalCatalog;
	final fieldReadCatalog:TypedBackendFieldReadCatalog;
	final runtimeTypeCatalog:TypedBackendRuntimeTypeCatalog;

	public function new(stableIdentity:String, bodyRevision:String, field:TyFieldInfo, declaration:HxFieldDecl, localCatalog:TypedBackendLocalCatalog,
			?fieldReadCatalog:TypedBackendFieldReadCatalog, ?runtimeTypeCatalog:TypedBackendRuntimeTypeCatalog) {
		if (stableIdentity == null || stableIdentity.length == 0)
			throw "typed backend field initializer projection requires a stable identity";
		if (bodyRevision == null || bodyRevision.length == 0)
			throw "typed backend field initializer projection requires an exact body revision";
		if (field == null || declaration == null || localCatalog == null)
			throw "typed backend field initializer projection requires complete typed facts";
		if (field.getName() != HxFieldDecl.getName(declaration))
			throw "typed backend field initializer projection received a declaration for a different field";
		if (HxFieldDecl.getInit(declaration) == null)
			throw "typed backend field initializer projection requires a projected initializer";
		this.stableIdentity = stableIdentity;
		this.bodyRevision = bodyRevision;
		this.field = field;
		this.declaration = declaration;
		this.localCatalog = localCatalog;
		this.fieldReadCatalog = fieldReadCatalog == null ? new TypedBackendFieldReadCatalog([]) : fieldReadCatalog;
		this.runtimeTypeCatalog = runtimeTypeCatalog == null ? new TypedBackendRuntimeTypeCatalog(stableIdentity, bodyRevision, []) : runtimeTypeCatalog;
		this.runtimeTypeCatalog.assertOwner(stableIdentity, bodyRevision);
		this.runtimeTypeCatalog.assertMarkers(TypedRuntimeTypeSource.inExpression(HxFieldDecl.getInit(declaration)));
	}

	public function getStableIdentity():String
		return stableIdentity;

	public function getRuntimeTypeCatalog():TypedBackendRuntimeTypeCatalog
		return runtimeTypeCatalog;

	/** Select an operand only from this exact initializer projection and revision. */
	public function requireRuntimeType(expression:HxExpr):TypedBackendRuntimeTypeOccurrence {
		if (TypedRuntimeTypeSource.inExpression(getExpression()).indexOf(expression) < 0)
			throw "runtime type operand is absent from the current initializer projection";
		return runtimeTypeCatalog.require(expression, stableIdentity, bodyRevision);
	}

	public function getBodyRevision():String
		return bodyRevision;

	public function getField():TyFieldInfo
		return field;

	public function getDeclaration():HxFieldDecl
		return declaration;

	public function getExpression():HxExpr
		return HxFieldDecl.getInit(declaration);

	public function getLocalCatalog():TypedBackendLocalCatalog
		return localCatalog;

	public function getFieldReadCatalog():TypedBackendFieldReadCatalog
		return fieldReadCatalog;
}
