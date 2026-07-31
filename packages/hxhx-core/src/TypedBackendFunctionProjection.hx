/**
	A source-shaped function body paired with the exact typed-local and bare
	field-read catalogs that gave projected values their transport names. The
	body revision comes from the same sealed typed tree and lets target plans bind
	their decisions without hashing this projected source-shaped view.

	Existing emitters may consume the declaration while they migrate, but a
	backend that makes local-identity or local-type decisions must also consume
	`localCatalog`. A backend that interprets a bare field must consume
	`fieldReadCatalog` rather than rediscovering field ownership from text.
**/
class TypedBackendFunctionProjection {
	final stableIdentity:String;
	final bodyRevision:String;
	final declaration:HxFunctionDecl;
	final localCatalog:TypedBackendLocalCatalog;
	final fieldReadCatalog:TypedBackendFieldReadCatalog;
	final parameterBindingIdentities:Array<String>;

	public function new(stableIdentity:String, bodyRevision:String, declaration:HxFunctionDecl, localCatalog:TypedBackendLocalCatalog,
			?fieldReadCatalog:TypedBackendFieldReadCatalog, ?parameterBindingIdentities:Array<String>) {
		if (stableIdentity == null || stableIdentity.length == 0)
			throw "typed backend function projection requires a stable identity";
		if (bodyRevision == null || bodyRevision.length == 0)
			throw "typed backend function projection requires an exact body revision";
		if (declaration == null)
			throw "typed backend function projection requires a declaration";
		if (localCatalog == null)
			throw "typed backend function projection requires a local catalog";
		this.stableIdentity = stableIdentity;
		this.bodyRevision = bodyRevision;
		this.declaration = declaration;
		this.localCatalog = localCatalog;
		this.fieldReadCatalog = fieldReadCatalog == null ? new TypedBackendFieldReadCatalog([]) : fieldReadCatalog;
		this.parameterBindingIdentities = parameterBindingIdentities == null ? [] : parameterBindingIdentities.copy();
		final seenParameters = new haxe.ds.StringMap<Bool>();
		for (identity in this.parameterBindingIdentities) {
			if (identity == null || identity.length == 0)
				throw "typed backend function projection contains an empty parameter binding identity";
			if (seenParameters.exists(identity))
				throw "typed backend function projection contains duplicate parameter binding " + identity;
			final local = localCatalog.findByIdentity(identity);
			if (local == null || !local.getBinding().getKind().match(Parameter))
				throw "typed backend function projection cannot find exact parameter binding " + identity;
			seenParameters.set(identity, true);
		}
	}

	public function getDeclaration():HxFunctionDecl
		return declaration;

	/**
		Return the source-shaped body rebuilt from this projection's sealed typed
		body.

		Migrating backends should use this accessor after selecting a strict
		projection. It makes the typed record—not a parsed declaration—the visible
		owner of the body they render.
	**/
	public function getBody():Array<HxStmt>
		return HxFunctionDecl.getBody(declaration);

	public function getStableIdentity():String
		return stableIdentity;

	/** Return the exact semantic body revision supplied by the sealed typed owner. **/
	public function getBodyRevision():String
		return bodyRevision;

	public function getLocalCatalog():TypedBackendLocalCatalog
		return localCatalog;

	public function getFieldReadCatalog():TypedBackendFieldReadCatalog
		return fieldReadCatalog;

	/** Return exact parameter bindings in source signature order. **/
	public function getParameterBindingIdentities():Array<String>
		return parameterBindingIdentities.copy();
}
