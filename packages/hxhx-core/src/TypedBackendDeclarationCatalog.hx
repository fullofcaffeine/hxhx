/**
	Own the legacy backend declaration together with exact function identities.

	`TypedBodySource` creates both the source-shaped declaration objects and
	their stable typed identities in one operation. A migrated backend can hand
	an exact class/function object back to `TypedModule`, which resolves it
	without source positions, names, sanitized spellings, or traversal indexes.
**/
class TypedBackendDeclarationCatalog {
	final declaration:HxModuleDecl;
	final functions:Array<{
		backendClass:HxClassDecl,
		backendFunction:HxFunctionDecl,
		stableIdentity:String
	}>;

	public function new(declaration:HxModuleDecl, functions:Array<{
		backendClass:HxClassDecl,
		backendFunction:HxFunctionDecl,
		stableIdentity:String
	}>) {
		if (declaration == null)
			throw "typed backend declaration catalog requires a module declaration";
		this.declaration = declaration;
		this.functions = functions == null ? [] : functions.copy();
	}

	public function getDeclaration():HxModuleDecl
		return declaration;

	/** Resolve one exact declaration pair to the stable typed function identity created with it. **/
	public function findFunctionIdentity(backendClass:HxClassDecl, backendFunction:HxFunctionDecl):Null<String> {
		for (entry in functions)
			if (entry.backendClass == backendClass && entry.backendFunction == backendFunction)
				return entry.stableIdentity;
		return null;
	}
}
