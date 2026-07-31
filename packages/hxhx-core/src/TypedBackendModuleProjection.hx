/**
	The temporary source-shaped backend view of one sealed typed module.

	The declaration keeps legacy target traversal working while `classes`
	retains the exact typed-local and bare field-read catalogs required by
	migrated targets.
**/
class TypedBackendModuleProjection {
	final declaration:HxModuleDecl;
	final classes:Array<TypedBackendClassProjection>;

	public function new(declaration:HxModuleDecl, classes:Array<TypedBackendClassProjection>) {
		if (declaration == null)
			throw "typed backend module projection requires a declaration";
		this.declaration = declaration;
		this.classes = classes == null ? [] : classes.copy();
		final projectedClasses = HxModuleDecl.getClasses(declaration);
		if (projectedClasses.length != this.classes.length)
			throw "typed backend module projection lost a class catalog";
		for (index in 0...projectedClasses.length)
			if (projectedClasses[index] != this.classes[index].getDeclaration())
				throw "typed backend module projection class order mismatch";
	}

	public function getDeclaration():HxModuleDecl
		return declaration;

	public function getClasses():Array<TypedBackendClassProjection>
		return classes.copy();
}
