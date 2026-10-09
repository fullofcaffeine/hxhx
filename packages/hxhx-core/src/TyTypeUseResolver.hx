import TyTypeDeclaration.TyTypeResolutionContext;

/**
	Resolve named type uses with one isolated finite graph per operation.
	Alias bodies use their defining module and exact parameters. Recursive edges
	retain references, while ordinary aliases remain transparent to consumers.
	An unsuccessful resolution cannot leave partly bound definitions in this
	shared facade or affect the next request.
 */
class TyTypeUseResolver {
	final catalog:TyTypeDeclarationCatalog;

	public function new(catalog:TyTypeDeclarationCatalog) {
		this.catalog = catalog;
	}

	public function resolve(type:TyType, context:TyTypeResolutionContext):TyResolvedTypeUse {
		return new TyTypeUseResolution(catalog).resolve(type, context);
	}

	/** Resolve parsed bounds without reconstructing type-hint text. */
	public function resolveParsed(syntax:HxTypeSyntax, context:TyTypeResolutionContext, scopeIdentity:String):TyResolvedTypeUse {
		return new TyTypeUseResolution(catalog).resolveParsed(syntax, context, scopeIdentity);
	}

	/** Validate unused alias bodies and default names before publishing declarations. */
	public function validateDeclaration(declaration:TyTypeDeclaration):Void {
		new TyTypeUseResolution(catalog).validateDeclaration(declaration);
	}
}
