package backend.cpp;

/**
	Storage for real closures nested in one field initializer. The shared capture
	planner owns cell and parameter identity. This owner supplies declaration
	events and revision checks without inventing a callable initializer root.
	A field application resolves its own class binders without borrowing
	the constructor's executable identity or changing shared capture facts.
 */
class CppManagedInitializerStorage extends CppManagedCaptureStorage {
	public final abstractReceiverType:Null<TyType> = null;

	final projection:TypedBackendFieldInitializerProjection;
	final application:Null<CppManagedInitializerApplication>;

	public function new(projection:TypedBackendFieldInitializerProjection, ?application:CppManagedInitializerApplication) {
		if (application != null && application.projection != projection)
			throw "initializer storage application belongs to another field";
		super(projection.requireCaptureCatalog(), application == null ? type->type : application.resolveStorageType);
		this.projection = projection;
		this.application = application;
	}

	public function assertCurrent():Void {
		projection.assertCurrent();
		if (application != null)
			application.assertCurrent();
	}

	public function resolveType(type:TyType):TyType
		return application == null ? type : application.resolveStorageType(type);

	public function resolveSemanticType(type:TyType):TyType
		return application == null ? type : application.resolveType(type);

	public function getDeclarations(owner:CppManagedFunctionOwner):Array<TypedCaptureBinding> {
		final identity = requireFunction(owner).facts.identity;
		return [
			for (binding in projection.requireCaptureCatalog().getPlan().getBindings())
				if (binding.functionIdentity == identity
					&& (binding.creation == Declaration || binding.creation == LoopIteration || binding.creation == CatchEntry)) binding
		];
	}

	public function assertUninitializedLocal(binding:TyLocalBinding):Void
		projection.assertUninitializedLocal(binding);

	public function requireAscribedClosure(expression:HxExpr):HxExpr
		return projection.requireCaptureCatalog().requireAscribedClosure(expression);
}
