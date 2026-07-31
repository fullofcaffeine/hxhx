/**
	A projected class declaration whose function bodies remain paired with their
	exact typed-local and bare field-read catalogs.
**/
class TypedBackendClassProjection {
	final declaration:HxClassDecl;
	final functions:Array<TypedBackendFunctionProjection>;
	final fieldInitializers:Array<TypedBackendFieldInitializerProjection>;
	final semanticFacts:Null<TypedBackendClassSemanticFacts>;

	public function new(declaration:HxClassDecl, functions:Array<TypedBackendFunctionProjection>,
			?fieldInitializers:Array<TypedBackendFieldInitializerProjection>, ?semanticFacts:TypedBackendClassSemanticFacts) {
		if (declaration == null)
			throw "typed backend class projection requires a declaration";
		this.declaration = declaration;
		this.functions = functions == null ? [] : functions.copy();
		this.fieldInitializers = fieldInitializers == null ? [] : fieldInitializers.copy();
		this.semanticFacts = semanticFacts;
		final projectedFunctions = HxClassDecl.getFunctions(declaration);
		if (projectedFunctions.length != this.functions.length)
			throw "typed backend class projection lost a function catalog";
		for (index in 0...projectedFunctions.length)
			if (projectedFunctions[index] != this.functions[index].getDeclaration())
				throw "typed backend class projection function order mismatch";
		final projectedFields = HxClassDecl.getFields(declaration);
		for (initializer in this.fieldInitializers) {
			if (initializer == null)
				throw "typed backend class projection cannot contain a null field initializer";
			var found = false;
			for (field in projectedFields)
				if (field == initializer.getDeclaration()) {
					found = true;
					break;
				}
			if (!found)
				throw "typed backend class projection lost field initializer " + initializer.getStableIdentity();
		}
	}

	public function getDeclaration():HxClassDecl
		return declaration;

	public function getFunctions():Array<TypedBackendFunctionProjection>
		return functions.copy();

	public function getFieldInitializers():Array<TypedBackendFieldInitializerProjection>
		return fieldInitializers.copy();

	/**
		Return the exact semantic class and declared-member record supplied by typing.

		Bring-up modules created without a program semantic index do not have this
		record. A backend migrating to exact class facts must fail at this accessor
		instead of reconstructing member ownership from source-shaped declarations.
	**/
	public function requireSemanticFacts():TypedBackendClassSemanticFacts {
		if (semanticFacts == null)
			throw "typed backend class projection has no exact semantic facts for " + HxClassDecl.getName(declaration);
		return semanticFacts;
	}

	public function findFunction(declaration:HxFunctionDecl):Null<TypedBackendFunctionProjection> {
		for (projection in functions)
			if (projection.getDeclaration() == declaration)
				return projection;
		return null;
	}
}
