package backend.cpp;

import backend.cpp.CppManagedClosureAbi.CppManagedHiddenParameter;

/** Named function storage is initialized once; ordinary captures share a binding location. */
enum CppManagedCellMode {
	InitializeOnce;
	SharedBinding;
}

/**
	One promoted declaration and its exact allocation event.
	The event executes once per invocation, declaration, iteration, match, or catch,
	not once per compilation. SharedBinding does not grant source write permission;
	the typer still owns source mutability checks.
 */
class CppManagedCellPlan {
	public final source:TypedCaptureBinding;
	public final mode:CppManagedCellMode;

	public function new(source:TypedCaptureBinding) {
		this.source = source;
		mode = source.binding.getKind() == NamedFunction ? InitializeOnce : SharedBinding;
	}
}

/**
	One root or nested function owns its parameters, return transport, and captures.
	Nested environment edges refer to shared cells, including forwarded captures;
	ordinary roots have no enclosing closure environment. Receiver requirements
	remain explicit in facts and use separate target storage. A consumer
	must revalidate its parent plan before using this immutable record.
 */
class CppManagedFunctionPlan {
	public final facts:TypedCaptureFunction;
	public final abi:CppManagedClosureAbi;

	final cells:Array<CppManagedCellPlan>;
	final parameters:Array<TypedCaptureBinding>;

	public function new(facts:TypedCaptureFunction, cells:Array<CppManagedCellPlan>, signature:TyType, parameters:Array<TypedCaptureBinding>,
			?receiver:CppManagedHiddenParameter, ?resolveType:TyType->TyType) {
		this.facts = facts;
		abi = new CppManagedClosureAbi(signature, facts.parentIdentity != null, receiver);
		this.cells = cells.copy();
		this.parameters = parameters.copy();
		if (parameters.length != abi.getParameters().length)
			throw "managed closure parameters disagree with its signature";
		for (index in 0...parameters.length)
			if (parameters[index].slot != index
				|| parameters[index].functionIdentity != facts.identity
				|| parameters[index].creation != FunctionEntry
				|| (resolveType == null ? parameters[index].binding.getType() : resolveType(parameters[index].binding.getType()))
					.getSemanticKey() != abi.getParameters()[index].type.getSemanticKey())
				throw "managed closure lacks exact ordered parameter identities";
	}

	/** Source parameter identities retain signature order and their function-entry allocation events. */
	public function getParameters():Array<TypedCaptureBinding>
		return parameters.copy();

	public function getCells():Array<CppManagedCellPlan>
		return cells.copy();
}

/**
	Select conservative managed cells from the shared, revision-bound capture facts.

	Every captured binding receives one cell plan. Creators and descendants must
	use the same dynamic cell, while the recorded source event creates fresh cells
	for distinct invocations or loop iterations. Names never choose ownership.
	This first storage slice does not authorize emission: payload layouts, temporary
	roots, parameter ingress, receiver storage, and rooted return slots still need
	complete call/storage planning before the legacy C++ carriers can be removed.
 */
class CppManagedStoragePlan {
	/** A constructor cell stores the exact backing type, distinct from its abstract result. */
	public final abstractReceiverType:Null<TyType>;

	final projection:TypedBackendFunctionProjection;
	final catalog:TypedBackendCaptureCatalog;
	final captures:CppManagedCaptureStorage;
	final root:CppManagedFunctionPlan;
	final application:Null<CppManagedFunctionApplication>;

	public function new(projection:TypedBackendFunctionProjection, ?classes:CppManagedClassStorage, ?application:CppManagedFunctionApplication) {
		if (projection == null)
			throw "managed storage requires an exact function projection";
		this.projection = projection;
		this.application = application;
		if (application != null) {
			application.assertCurrent();
			if (application.projection != projection)
				throw "managed storage application belongs to another function";
		}
		abstractReceiverType = application != null ? (projection.requireSemanticDeclaration()
			.getSignature()
			.getName() == "new" ? application.storedBackingType : null) : classes == null ? null : classes.abstractConstructorUnderlying(projection);
		catalog = projection.requireCaptureCatalog();
		final facts = catalog.getPlan();
		captures = new CppManagedCaptureStorage(catalog, resolveType);
		final rootFacts = facts.getFunctions()[0];
		if (rootFacts.parentIdentity != null || rootFacts.getCaptures().length != 0)
			throw "managed root function cannot borrow a closure environment";
		final rootParameters = [
			for (binding in facts.getBindings())
				if (binding.functionIdentity == rootFacts.identity && binding.creation == FunctionEntry) binding
		];
		rootParameters.sort((left, right) -> left.slot - right.slot);
		final sourceParameters = projection.getParameters();
		if (rootParameters.length != sourceParameters.length)
			throw "managed root parameters differ from the exact projection";
		for (index in 0...rootParameters.length)
			if (rootParameters[index].binding.getCanonicalIdentity() != sourceParameters[index].getBinding().getCanonicalIdentity())
				throw "managed root parameter identity differs from the exact projection";
		final callable = CppManagedFunctionSignature.resolve(projection, resolveType);
		root = new CppManagedFunctionPlan(rootFacts, [], callable, rootParameters,
			projection.requireSemanticDeclaration().getIsStatic() ? null : abstractReceiverType == null ? ReceiverValue : ReceiverCell, resolveType);
	}

	/** Revalidate the source revision and exact root/closure occurrence before selecting storage. */
	public function requireFunction(owner:CppManagedFunctionOwner):CppManagedFunctionPlan {
		assertCurrent();
		return switch owner {
			case Root(selected):
				if (selected != projection)
					throw "managed root requires its exact projection object";
				root;
			case Closure(expression): requireClosure(expression);
		};
	}

	/** Recheck both typed revisions and the exact projected closure objects. */
	/** Retain the shared declaration proof before selecting checked unassigned storage. */
	public function assertUninitializedLocal(binding:TyLocalBinding):Void {
		assertCurrent();
		projection.assertUninitializedLocal(binding);
	}

	public function assertCurrent():Void {
		catalog.assertCurrent();
		if (application != null)
			application.assertCurrent();
	}

	/** Applied storage never changes the binding objects used for captures and ownership. */
	public function resolveType(type:TyType):TyType
		return application == null ? type : application.resolveStorageType(type);

	/** Declaration checks use semantic substitution before target storage adds null-preserving transport. */
	public function resolveSemanticType(type:TyType):TyType
		return application == null ? type : application.resolveType(type);

	public function getCells():Array<CppManagedCellPlan> {
		assertCurrent();
		return captures.getCells();
	}

	/** Local storage events belong to one lexical function, including fresh loop and catch entries. */
	public function getDeclarations(functionOwner:CppManagedFunctionOwner):Array<TypedCaptureBinding> {
		final owner = requireFunction(functionOwner).facts.identity;
		return [
			for (binding in catalog.getPlan().getBindings())
				if (binding.functionIdentity == owner
					&& (binding.creation == Declaration || binding.creation == LoopIteration || binding.creation == CatchEntry)) binding
		];
	}

	/** Resolve promoted storage by declaration identity after checking the owning revision. */
	public function requireCell(binding:TyLocalBinding):CppManagedCellPlan {
		assertCurrent();
		return captures.requireCell(binding);
	}

	/** Resolve compiler-added type transport without granting authored casts implicit conversion. */
	public function requireAscribedClosure(expression:HxExpr):HxExpr
		return catalog.requireAscribedClosure(expression);

	/** Only a cataloged expression can select an environment; equal source text is insufficient. */
	public function requireClosure(expression:HxExpr):CppManagedFunctionPlan {
		return captures.requireClosure(expression);
	}
}
