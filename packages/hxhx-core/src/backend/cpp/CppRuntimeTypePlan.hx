package backend.cpp;

/** A class value needs descriptor storage; an instance test produces a Boolean. */
enum CppRuntimeTypeOperationKind {
	ClassValue;
	InstanceTest;
}

/** Exact occurrence and shared descriptor requirement owned by this compilation. */
typedef CppRuntimeTypeOperation = {
	final kind:CppRuntimeTypeOperationKind;
	final occurrence:TypedBackendRuntimeTypeOccurrence;
	final descriptor:CppRuntimeTypeDescriptor;
};

/**
	One semantic runtime target and its real declaration, before storage selection.

	This record does not invent a public reflection name or admit native execution.
	Primitive type objects have no declaration. Array and String use their indexed
	providers, while nominal targets keep their exact class or interface owner.
 */
class CppRuntimeTypeDescriptor {
	final target:TypedRuntimeTypeTarget;
	final declaration:Null<TypedBackendClassSemanticFacts>;

	public function new(target:TypedRuntimeTypeTarget, program:CppTypedProgramProjection) {
		this.target = target;
		final identity = target.getDeclarationIdentity();
		declaration = identity == null ? null : program.requireClass(program.requireClassIdentity(identity.getCanonicalName())).requireSemanticFacts();
	}

	public function getTarget():TypedRuntimeTypeTarget
		return target;

	public function getDeclaration():Null<TypedBackendClassSemanticFacts>
		return declaration;
}

/**
	Collect cataloged descriptor requirements before C++ checks their support.

	All loaded function and initializer catalogs participate, including provider
	bodies that are not called by Main. Repeated targets share one descriptor by
	shared semantic identity, never by source spelling or native carrier shape.
	Class-value planning is independent of erased instance storage; neither this
	inventory nor a declaration's presence authorizes unsupported execution.
	Ordinary calls with a dynamically selected target and reflection calls need
	separate selected-call planning; this catalog is not their admission proof.

	The plan stays bound to the source program and exact projected marker objects.
	Consumers cannot reuse it after typed bodies or marker argument arrays change.
 */
class CppRuntimeTypePlan {
	final program:CppTypedProgramProjection;
	final descriptors:Array<CppRuntimeTypeDescriptor>;
	final operations:Array<CppRuntimeTypeOperation> = [];

	public function new(program:CppTypedProgramProjection) {
		if (program == null)
			throw "C++ runtime type plan requires an exact program";
		program.assertCurrent();
		this.program = program;
		final byIdentity = new haxe.ds.StringMap<CppRuntimeTypeDescriptor>();
		function add(occurrence:TypedBackendRuntimeTypeOccurrence):Void {
			occurrence.assertCurrent();
			final target = occurrence.getTarget();
			final identity = target.getSemanticKey();
			var descriptor = byIdentity.get(identity);
			if (descriptor == null) {
				descriptor = new CppRuntimeTypeDescriptor(target, program);
				byIdentity.set(identity, descriptor);
			}
			operations.push({
				kind: occurrence.getValue() == null ? ClassValue : InstanceTest,
				occurrence: occurrence,
				descriptor: descriptor
			});
		}
		for (module in program.getModules())
			for (cls in module.projection.getClasses()) {
				for (fn in cls.getFunctions())
					for (entry in fn.getRuntimeTypeCatalog().getEntries())
						add(fn.requireRuntimeType(entry.getExpression()));
				for (initializer in cls.getFieldInitializers())
					for (entry in initializer.getRuntimeTypeCatalog().getEntries())
						add(initializer.requireRuntimeType(entry.getExpression()));
			}
		final identities = [for (identity in byIdentity.keys()) identity];
		identities.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		descriptors = [for (identity in identities) byIdentity.get(identity)];
	}

	/** Source revisions and projected occurrences both remain part of validity. */
	public function assertCurrent():Void {
		program.assertCurrent();
		for (operation in operations)
			operation.occurrence.assertCurrent();
	}

	/** Deterministic descriptor order is independent of the first source alias encountered. */
	public function getDescriptors():Array<CppRuntimeTypeDescriptor> {
		assertCurrent();
		return descriptors.copy();
	}

	/** Keep original executable traversal order for diagnostics and admission checks. */
	public function getOperations():Array<CppRuntimeTypeOperation> {
		assertCurrent();
		return operations.copy();
	}
}
