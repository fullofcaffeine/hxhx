package backend.js;

/** Exact class identity paired with its selected JavaScript declaration reference. */
typedef JsClassInheritanceNode = {
	final identity:String;
	final superIdentity:Null<String>;
	final fullName:String;
	final reference:String;

	/** A host owns extern implementation and prototype links. */
	final isExtern:Bool;

	/** Direct host paths emit no declaration and may be shared by several extern types. */
	final usesHostPath:Bool;

	/** The admitted abstract wrapper stores the source-level receiver in its backing slot. */
	final abstractReceiver:Bool;
};

/**
	Bind typed superclass edges to generated classes or host-owned extern references.
	Names used for output cannot replace semantic identity. This plan rejects missing
	parents, unresolved edges, cycles, and presentation collisions instead of emitting
	a generated child whose prototype silently loses its parent. Extern declarations
	retain their type edges but do not require the compiler to generate host parents.
	It is owned by one typed program.
 */
class JsClassInheritancePlan {
	final program:MacroExpandedProgram;
	final nodes = new haxe.ds.ObjectMap<TypedBackendClassProjection, JsClassInheritanceNode>();
	final declarationRanks = new haxe.ds.StringMap<Int>();
	final byIdentity = new haxe.ds.StringMap<JsClassInheritanceNode>();
	final graph:TypedBackendClassGraph;

	public function new(program:MacroExpandedProgram) {
		program.assertTypedBodyRevisionsCurrent();
		this.program = program;
		final classFacts = new Array<TypedBackendClassSemanticFacts>();
		final byReference = new haxe.ds.StringMap<String>();
		final sourceOrder = new Array<JsClassInheritanceNode>();
		for (module in program.getTypedModules()) {
			final projection = module.getBackendProjection();
			final packagePath = HxModuleDecl.getPackagePath(projection.getDeclaration());
			for (owner in projection.getClasses()) {
				final facts = owner.requireSemanticFacts();
				classFacts.push(facts);
				final name = HxClassDecl.getName(owner.getDeclaration());
				final fullName = packagePath.length == 0 ? name : packagePath + "." + name;
				final nativeReference = JsExternBinding.reference(owner.getDeclaration());
				final hostReference = nativeReference != null ? nativeReference : JsExternBinding.defaultReference(owner.getDeclaration(), fullName);
				final reference = hostReference == null ? JsNameMangler.classVarName(fullName) : hostReference;
				final identity = facts.getClassIdentity();
				if (byIdentity.exists(identity))
					throw "JavaScript repeats an exact class provider: " + identity;
				// Distinct extern declarations can describe the same host value. Neither
				// emits a declaration, but generated class names must remain unique.
				final previous = byReference.exists(reference) ? byIdentity.get(byReference.get(reference)) : null;
				if (previous != null && !(hostReference != null && previous.usesHostPath))
					throw "JavaScript presentation name collides across exact classes: " + fullName;
				if (facts.getSuperType() != null && facts.getSuperClassIdentity() == null)
					throw "JavaScript superclass is unresolved for " + identity;
				final node:JsClassInheritanceNode = {
					identity: identity,
					superIdentity: facts.getSuperClassIdentity(),
					fullName: fullName,
					reference: reference,
					isExtern: facts.getIsExtern(),
					usesHostPath: hostReference != null,
					abstractReceiver: switch (facts.getNominalKind()) {
						case AbstractValue(_): true;
						case _: false;
					}
				};
				byReference.set(reference, identity);
				byIdentity.set(identity, node);
				nodes.set(owner, node);
				sourceOrder.push(node);
			}
		}
		final visiting = new haxe.ds.StringMap<Bool>();
		var nextRank = 0;
		function visit(node:JsClassInheritanceNode):Void {
			if (declarationRanks.exists(node.identity))
				return;
			if (visiting.exists(node.identity))
				throw "JavaScript superclass cycle at " + node.identity;
			visiting.set(node.identity, true);
			if (node.superIdentity != null) {
				final parent = byIdentity.get(node.superIdentity);
				if (parent == null && !node.isExtern)
					throw "JavaScript superclass has no emitted provider: " + node.superIdentity;
				if (parent != null)
					visit(parent);
			}
			visiting.remove(node.identity);
			declarationRanks.set(node.identity, nextRank++);
		}
		for (node in sourceOrder)
			visit(node);
		// Preserve superclass diagnostics before admitting the shared interface graph.
		graph = new TypedBackendClassGraph(program.getTypedProgramRevision().getCanonicalIdentity(), classFacts);
	}

	/** A type plan cannot borrow emitted references from another program or stale revision. */
	public function assertProgram(candidate:MacroExpandedProgram):Void {
		if (candidate != program)
			throw "JavaScript inheritance plan belongs to another typed program";
		candidate.assertTypedBodyRevisionsCurrent();
	}

	/** A renderer can consume only a projection admitted by this plan. */
	public function requireClass(owner:TypedBackendClassProjection):JsClassInheritanceNode {
		final node = nodes.get(owner);
		if (node == null)
			throw "JavaScript class projection is absent from its inheritance plan";
		return node;
	}

	/** Parent declarations must exist before a child installs its prototype link. */
	public function declarationRank(owner:TypedBackendClassProjection):Int {
		return declarationRanks.get(requireClass(owner).identity);
	}

	/** Runtime class values must name an admitted class, never an enum or abstract carrier. */
	public function requireRuntimeClass(identity:String):JsClassInheritanceNode {
		final node = byIdentity.get(identity);
		final facts = graph.findClassFacts(identity);
		if (node == null || facts == null || !facts.getNominalKind().match(ClassInstance))
			throw "JavaScript runtime type has no exact class provider: " + identity;
		if (facts.getIsExtern() && facts.getIsInterface())
			throw "JavaScript extern interface runtime type is unsupported: " + identity;
		return node;
	}

	/** The shared graph owns interface closure; JavaScript only chooses emitted references. */
	public function interfaceReferences(owner:TypedBackendClassProjection):Array<String> {
		final identity = requireClass(owner).identity;
		final facts = graph.findClassFacts(identity);
		if (!facts.getNominalKind().match(ClassInstance) || facts.getIsExtern())
			return [];
		return [
			for (node in graph.requireAssignableTypes(identity, fact -> !fact.getIsExtern()))
				if (node.isInterface) requireRuntimeClass(node.classIdentity).reference
		];
	}
}
