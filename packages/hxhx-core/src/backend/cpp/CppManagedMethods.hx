package backend.cpp;

import backend.cpp.CppManagedCallContext.CppManagedEnclosingApplication;

/** A reachable allocation selects one exact implementation without changing receiver storage. */
typedef CppManagedInstanceDispatchCase = {
	final descriptor:String;
	final application:CppManagedFunctionApplication;
}

/** One lexical call can execute under several exact enclosing function or field applications. */
typedef CppManagedMethodUse = {
	final call:TypedBackendInstanceCallOccurrence;
	final context:Null<CppManagedEnclosingApplication>;
}

/** The executable owner remains attached to the lookup that revalidates its call. */
private typedef ManagedCallOwner = {
	final source:backend.cpp.CppManagedCallContext.CppManagedCallOwner;
	final find:Void->Null<TypedBackendInstanceCallOccurrence>;
}

/**
	Select authored methods and freeze virtual targets for one compilation.
	Each call retains its exact function or initializer owner. Validated constructor
	applications supply reachable allocations; sealing then rejects late allocations.
	Class storage remains the sole owner of physical layouts and public descriptors.
	For example, a Base<Int> call on a Child allocation selects Child's override
	while preserving Base<Int>'s checked parameter and result types.
 */
class CppManagedMethods {
	final program:CppTypedProgramProjection;
	final classes:CppManagedClassStorage;
	final instanceOwners = new haxe.ds.ObjectMap<TypedBackendInstanceCallOccurrence, ManagedCallOwner>();
	final allocations = new haxe.ds.StringMap<TyType>();
	var sealedDispatch:Null<haxe.ds.ObjectMap<TypedBackendInstanceCallOccurrence, haxe.ds.StringMap<Array<CppManagedInstanceDispatchCase>>>> = null;

	/** Class storage creates exactly one dispatch owner for its program and layouts. */
	@:allow(backend.cpp.CppManagedClassStorage)
	function new(program:CppTypedProgramProjection, classes:CppManagedClassStorage) {
		this.program = program;
		this.classes = classes;
	}

	/** Only a validated constructor application may add a reachable allocation. */
	@:allow(backend.cpp.CppManagedClassStorage)
	function registerAllocation(type:TyType):Void {
		final identity = type.getSemanticKey();
		final previous = allocations.get(identity);
		if (sealedDispatch != null && previous == null)
			throw "managed allocation discovered after dispatch was sealed";
		allocations.set(identity, type);
	}

	/** Register only a current function's exact call while computing its reachable method closure. */
	public function functionInstanceCall(projection:TypedBackendFunctionProjection, expression:HxExpr):Null<TypedBackendInstanceCallOccurrence> {
		if (TypedExactCallSource.decodeInstance(expression) == null)
			return null;
		classes.assertFunction(projection);
		final call = projection.findInstanceCall(expression);
		if (call != null)
			instanceOwners.set(call, {source: FunctionSource(projection), find: () -> projection.findInstanceCall(expression)});
		return call;
	}

	/** Initializer calls retain their own executable owner rather than borrowing a method catalog. */
	public function initializerInstanceCall(projection:TypedBackendFieldInitializerProjection, expression:HxExpr):Null<TypedBackendInstanceCallOccurrence> {
		if (TypedExactCallSource.decodeInstance(expression) == null)
			return null;
		classes.assertInitializer(projection);
		final call = projection.findInstanceCall(expression);
		if (call != null)
			instanceOwners.set(call, {source: FieldSource(projection), find: () -> projection.findInstanceCall(expression)});
		return call;
	}

	/** Every call uses its exact declaration; an interface contributes a signature without a body. */
	public function requireInstanceMethod(call:TypedBackendInstanceCallOccurrence, ?context:CppManagedEnclosingApplication):TypedBackendFunctionProjection {
		return instanceApplication(call, context).projection;
	}

	/** The selected declaration may be inherited, but must belong to this exact receiver's ancestry. */
	@:allow(backend.cpp.CppManagedInstanceMethod)
	function assertInstanceReceiver(call:TypedBackendInstanceCallOccurrence, receiver:TyType):Void {
		final declaredOwner = call.getDeclaration().getOwner();
		if (receiver == null || receiver.getNominalIdentity() == null)
			throw "managed instance method requires an exact typed receiver";
		if (receiver.getNominalIdentity().equals(declaredOwner))
			return;
		if (program.getClassGraph()
			.requireAppliedAssignableTypes(receiver)
			.filter(type -> type.getNominalIdentity().equals(declaredOwner))
			.length == 0)
			throw "managed instance declaration does not belong to its receiver ancestry";
	}

	/** Ordinary entries use their declaring class view; the Value retains the actual allocated descriptor. */
	@:allow(backend.cpp.CppManagedStringMethods)
	function ordinaryMethodApplication(projection:TypedBackendFunctionProjection, receiver:TyType, ?validate:Void->Void):CppManagedFunctionApplication {
		assertInstanceMethod(projection);
		final declaration = projection.requireSemanticDeclaration();
		final ownerType = appliedMethodOwner(receiver, declaration.getOwner());
		final facts = program.requireClass(program.requireClassIdentity(declaration.getOwner().getCanonicalName())).requireSemanticFacts();
		if (!facts.getIsInterface())
			classes.requireType(ownerType);
		return new CppManagedFunctionApplication({
			projection: projection,
			receiverType: ownerType,
			parameters: facts.getTypeParameterIds(),
			backingType: null,
			casts: classes.casts,
			validate: () -> {
				classes.assertFunctionOwner(projection);
				if (validate != null)
					validate();
			}
		});
	}

	/** Implicit standard conversion can visit only constructor-validated allocations. */
	@:allow(backend.cpp.CppManagedStringMethods)
	function stringAllocations():Array<TyType> {
		final names = [for (name in allocations.keys()) name];
		names.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		return [for (name in names) allocations.get(name)];
	}

	/** Shared assignment views substitute class and interface edges before selecting the declaring owner. */
	function appliedMethodOwner(receiver:TyType, owner:TyNominalTypeId):TyType {
		final views = program.getClassGraph().requireAppliedAssignableTypes(receiver).filter(type -> type.getNominalIdentity().equals(owner));
		if (views.length != 1)
			throw "managed method owner requires one exact applied receiver ancestry view";
		return views[0];
	}

	/**
		Resolve overrides only for allocations discovered by the reachable program.
		The program repeats this query as newly selected bodies expose more allocations.
		Explicit super calls and abstract backing methods keep their direct target.
	 */
	public function instanceDispatch(call:TypedBackendInstanceCallOccurrence,
			?context:CppManagedEnclosingApplication):Null<Array<CppManagedInstanceDispatchCase>> {
		final selected = instanceApplication(call, context);
		if (selected.backingType != null || call.getCall().receiver.match(ESuper))
			return null;
		if (sealedDispatch != null) {
			final uses = sealedDispatch.get(call);
			final entries = uses == null ? null : uses.get(CppManagedCallContext.identity(context));
			if (entries == null)
				throw "managed instance call is absent from sealed dispatch";
			for (entry in entries)
				entry.application.assertCurrent();
			return [
				for (entry in entries)
					{descriptor: entry.descriptor, application: entry.application}
			];
		}
		final receiverType = appliedCallType(call.getReceiverType(), context);
		final names = [for (name in allocations.keys()) name];
		names.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		final cases = new Array<CppManagedInstanceDispatchCase>();
		for (name in names) {
			final allocation = allocations.get(name);
			final lineage = program.getClassGraph().requireLineage(allocation.getNominalIdentity().getCanonicalName());
			// Public descriptors erase arguments. The typed call still selects only
			// allocations whose receiver view has these exact applied arguments.
			if (program.getClassGraph()
				.requireAppliedAssignableTypes(allocation)
				.filter(view -> view.getSemanticKey() == receiverType.getSemanticKey())
				.length == 0)
				continue;
			var implementation:Null<TypedBackendFunctionProjection> = null;
			for (node in lineage) {
				final owner = program.requireClass(program.requireClassIdentity(node.classIdentity));
				final matches = owner.getFunctions()
					.filter(fn -> !fn.requireSemanticDeclaration().getIsStatic()
						&& fn.requireSemanticDeclaration()
							.getSignature()
							.getName() == call.getDeclaration()
							.getSignature()
							.getName());
				if (matches.length > 1)
					throw "managed virtual overloads require an exact slot plan";
				if (matches.length == 1) {
					implementation = matches[0];
					break;
				}
			}
			if (implementation == null)
				throw "managed allocated class lacks its selected virtual method";
			final application = ordinaryMethodApplication(implementation, allocation);
			if (application.resultType().getSemanticKey() != selected.resultType().getSemanticKey()
				|| CompilerCacheIdentity.encode(application.parameterTypes()
					.map(type -> type.getSemanticKey())) != CompilerCacheIdentity.encode(selected.parameterTypes().map(type -> type.getSemanticKey())))
				throw "managed virtual override requires an explicit signature adaptation";
			final descriptor = classes.requireType(allocation).symbol;
			final existing = cases.filter(entry -> entry.descriptor == descriptor);
			if (existing.length != 0) {
				if (existing[0].application.identity != application.identity)
					throw "managed erased receiver descriptor selects conflicting method applications";
				continue;
			}
			cases.push({descriptor: descriptor, application: application});
		}
		return cases;
	}

	/**
		Freeze targets only after reachable bodies and allocations converge. Lookup
		still validates the whole source program and exact call through instanceApplication,
		then checks each selected implementation's projected body before returning it.
		No new allocation may enter the plan afterward, so rendering cannot reuse an
		incomplete target set or repeatedly rediscover every implementation.
	 */
	public function sealInstanceDispatch(calls:Array<CppManagedMethodUse>):Void {
		program.assertCurrent();
		if (sealedDispatch != null)
			throw "managed instance dispatch was already sealed";
		final entries = new haxe.ds.ObjectMap<TypedBackendInstanceCallOccurrence, haxe.ds.StringMap<Array<CppManagedInstanceDispatchCase>>>();
		for (use in calls) {
			final cases = instanceDispatch(use.call, use.context);
			if (cases != null) {
				var uses = entries.get(use.call);
				if (uses == null) {
					uses = new haxe.ds.StringMap();
					entries.set(use.call, uses);
				}
				uses.set(CppManagedCallContext.identity(use.context), cases);
			}
		}
		sealedDispatch = entries;
	}

	/** A super-method call borrows the enclosing receiver and invokes an ancestor's selected body directly. */
	public function assertSuperMethod(projection:TypedBackendFunctionProjection, call:TypedBackendInstanceCallOccurrence):Void {
		classes.assertFunction(projection);
		if (projection.findInstanceCall(call.getExpression()) != call
			|| !call.getCall().receiver.match(ESuper)
			|| projection.requireSemanticDeclaration().getIsStatic())
			throw "super method requires its exact enclosing instance call";
		final ancestors = program.getClassGraph().requireLineage(projection.requireSemanticDeclaration().getOwner().getCanonicalName()).slice(1);
		if (ancestors.filter(node -> node.classIdentity == call.getDeclaration().getOwner().getCanonicalName()).length == 0)
			throw "super method selected a non-ancestor declaration";
	}

	/** Apply the exact caller's receiver arguments without changing the authored method. */
	public function instanceApplication(call:TypedBackendInstanceCallOccurrence, ?context:CppManagedEnclosingApplication):CppManagedFunctionApplication {
		program.assertCurrent();
		assertContext(call, context);
		final find = instanceOwners.get(call).find;
		final receiver = appliedCallType(call.getReceiverType(), context);
		final result = appliedCallType(call.getResultType(), context);
		final projection = CppManagedInstanceMethod.select(program, call, this, receiver);
		final declaration = projection.requireSemanticDeclaration();
		final facts = program.requireClass(program.requireClassIdentity(declaration.getOwner().getCanonicalName())).requireSemanticFacts();
		final backing = switch facts.getNominalKind() {
			case AbstractValue(type): type;
			case ClassInstance: null;
			case _: throw 'managed ordinary instance dispatch requires an explicit target plan';
		};
		final validate = () -> {
			if (find() != call)
				throw 'managed instance occurrence changed';
			if (context != null)
				CppManagedCallContext.assertCurrent(context);
			classes.assertFunctionOwner(projection);
		};
		final selected = backing == null ? ordinaryMethodApplication(projection, receiver, validate) : new CppManagedFunctionApplication({
			projection: projection,
			receiverType: receiver,
			parameters: facts.getTypeParameterIds(),
			backingType: backing,
			casts: classes.casts,
			validate: validate
		});
		final parameters = CppManagedFunctionSignature.resolve(projection, selected.resolveType).getFunctionParameters();
		final supplied = call.getProjectedArgumentTypes().length;
		if (supplied > parameters.length
			|| supplied != call.getCall().arguments.length
			|| selected.resultType().getSemanticKey() != result.getSemanticKey())
			throw 'managed instance method requires exact applied argument and result facts';
		for (slot in supplied...parameters.length)
			if (!parameters[slot].isOptional || parameters[slot].isRest)
				throw 'managed instance method requires exact applied argument and result facts';
		return selected;
	}

	/** Context ownership is already checked; concrete call types have no binders to substitute. */
	function appliedCallType(type:TyType, context:Null<CppManagedEnclosingApplication>):TyType {
		return context == null
			|| TyTypeSubstitution.parameterIdentities(type).length == 0 ? type : CppManagedCallContext.resolveType(context, type);
	}

	/** A caller application may substitute only calls owned by that exact field or function. */
	function assertContext(call:TypedBackendInstanceCallOccurrence, context:Null<CppManagedEnclosingApplication>):Void {
		final owner = instanceOwners.get(call);
		if (owner == null || owner.find() != call)
			throw "managed instance call belongs to another program or occurrence";
		CppManagedCallContext.assertOwner(context, owner.source);
	}

	/**
		Validate a callable declaration. Interfaces supply bodyless signatures; only
		ordinary class and abstract implementations may supply executable bodies.
		Application planning separately checks complete owner arguments and layouts.
	 */
	public function assertInstanceMethod(projection:TypedBackendFunctionProjection):Void {
		classes.assertFunction(projection);
		final declaration = projection.requireSemanticDeclaration();
		final owner = program.requireClass(program.requireClassIdentity(declaration.getOwner().getCanonicalName()));
		final facts = owner.requireSemanticFacts();
		if (declaration.getIsStatic()
			|| declaration.getIsDynamic()
			|| (declaration.getHasBody() == facts.getIsInterface())
			|| declaration.getSignature().getName() == 'new'
			|| declaration.getTypeParameters().length != 0
			|| facts.getIsExtern())
			throw 'managed instance method requires an exact authored entry without method type parameters: ' + declaration.getIdentity().getCanonicalKey();
		switch facts.getNominalKind() {
			case AbstractValue(underlying):
				CppManagedClosureAbi.assertComplete(underlying);
			case ClassInstance:
				if (!facts.getIsInterface() && facts.getTypeParameterIds().length == 0)
					classes.requireType(TyType.nominal(declaration.getOwner(), []));
			case _:
				throw 'managed ordinary instance dispatch requires an explicit target plan';
		}
	}
}
