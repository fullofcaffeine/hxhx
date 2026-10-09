package backend.cpp;

/**
	Place ordinary local roots and captured cells at their source declarations.
	Captured locations are allocated before their initializer, so a recursive
	function can capture its own unassigned cell and initialize it once afterward.
	Uncaptured values stay in lexical RAII roots. Both forms survive collecting
	initializers; the shared control renderer owns when their scopes end.
	Compiler-created result slots remain unassigned until their completing branch
	writes them. Loop bindings create fresh storage at each iteration event.
	Ordinary declarations without initializers also retain a checked unassigned
	state. A later write can assign null; a read before any write must fail.
	Catch bindings create fresh storage when their selected handler is entered.
	Pattern bindings and static locals retain their separate entry contracts.
 */
class CppManagedLocalStorage {
	final plan:CppManagedBodyStorage;
	final owner:CppManagedFunctionOwner;
	final prefix:String;
	final declarations:Array<TypedCaptureBinding>;

	public function new(plan:CppManagedBodyStorage, owner:CppManagedFunctionOwner, prefix:String) {
		if (plan == null || !identifier(prefix) || !StringTools.startsWith(prefix, "hxhx_locals_"))
			throw "managed locals require a plan and allocated symbol prefix";
		this.plan = plan;
		this.owner = owner;
		this.prefix = prefix;
		declarations = plan.getDeclarations(owner);
	}

	public function owns(binding:TyLocalBinding):Bool {
		plan.requireFunction(owner);
		return indexOf(binding) >= 0;
	}

	function indexOf(binding:TyLocalBinding):Int {
		if (binding != null)
			for (index in 0...declarations.length)
				if (declarations[index].binding.getCanonicalIdentity() == binding.getCanonicalIdentity())
					return index;
		return -1;
	}

	function requireIndex(binding:TyLocalBinding):Int {
		plan.requireFunction(owner);
		final index = indexOf(binding);
		if (index < 0)
			throw "binding is not a declaration in this managed function";
		return index;
	}

	function promoted(binding:TyLocalBinding):Bool {
		for (cell in plan.getCells())
			if (cell.source.binding.getCanonicalIdentity() == binding.getCanonicalIdentity())
				return true;
		return false;
	}

	/** The shared lowering identity authorizes deferred assignment, never a source name. */
	function compilerResult(binding:TyLocalBinding):Bool
		return binding.getKind() == CompilerTemporary && binding.getIdentity().isCompilerTemporary();

	public function value(binding:TyLocalBinding):String {
		final root = prefix + requireIndex(binding);
		return root + (promoted(binding) ? ".get()->read()" : ".get()");
	}

	public function cellReference(binding:TyLocalBinding):String {
		final index = requireIndex(binding);
		if (!promoted(binding))
			throw "managed local is not captured by a descendant";
		return prefix + index + ".get()";
	}

	/** Preserve location identity separately from reading its current value. */
	public function place(binding:TyLocalBinding):CppManagedPlace {
		final root = prefix + requireIndex(binding);
		return promoted(binding) ? Cell(root + ".get()") : LocalRoot(root);
	}

	/** Initializer emission must publish into the supplied root before it can allocate again. */
	public function renderDeclaration(binding:TyLocalBinding, initializer:Null<HxExpr>, heap:String, indent:String,
			renderValue:(HxExpr, String, String) -> Array<String>):Array<String> {
		final index = requireIndex(binding);
		if (declarations[index].creation != Declaration)
			throw "managed declaration requires its declaration event";
		if (!identifier(heap) || renderValue == null)
			throw "managed declaration requires heap and rooted initializer emission";
		if (initializer == null && !compilerResult(binding))
			plan.assertUninitializedLocal(binding);
		return initialize(binding, heap, indent, initializer == null ? null : (root, at) -> renderValue(initializer, root, at));
	}

	/** The loop emitter roots the selected element before any captured-cell allocation. */
	public function renderIteration(binding:TyLocalBinding, selectedRoot:String, heap:String, indent:String):Array<String> {
		if (declarations[requireIndex(binding)].creation != LoopIteration || !identifier(selectedRoot) || !identifier(heap))
			throw "managed iteration requires its exact creation event and rooted value";
		return initialize(binding, heap, indent, (root, at) -> [at + root + ".set(" + selectedRoot + ".get());"]);
	}

	/**
		Publish an already selected, rooted handler value at its exact catch event.
		The handler planner owns matching and conversion. Keeping that value rooted
		through cell allocation preserves managed payloads during forced collection.
		Each dynamic entry allocates a fresh captured cell; escaping closures share
		that entry's cell rather than the native exception transport.
	 */
	public function renderCatch(binding:TyLocalBinding, selectedRoot:String, heap:String, indent:String):Array<String> {
		final declaration = declarations[requireIndex(binding)];
		if (declaration.binding != binding || declaration.creation != CatchEntry || binding.getKind() != CatchVariable || !identifier(selectedRoot)
			|| !identifier(heap))
			throw "managed catch requires its exact creation event and rooted value";
		return initialize(binding, heap, indent, (root, at) -> [at + root + ".set(" + selectedRoot + ".get());"]);
	}

	/** Allocate at the selected source event and publish only after the initializer succeeds. */
	function initialize(binding:TyLocalBinding, heap:String, indent:String, initializer:Null<(String, String) -> Array<String>>):Array<String> {
		final index = requireIndex(binding);
		final root = prefix + index;
		if (!promoted(binding)) {
			final storage = initializer == null
				|| compilerResult(binding) ? "hxhx::managed::LocalSlot" : "hxhx::managed::Root<hxhx::managed::Value>";
			final lines = [indent + storage + " " + root + "(" + heap + ");"];
			return initializer == null ? lines : lines.concat(initializer(root, indent));
		}
		if (initializer == null)
			return [
				indent + "hxhx::managed::Root<hxhx::managed::Ref<hxhx::managed::CellPayload>> " + root + "(" + heap + ");",
				indent + new CppManagedCellEmitter(plan, binding).renderAllocation(heap, root, declarations[index])
			];
		final initialized = root + "_initializer";
		final lines = [indent + "hxhx::managed::Root<hxhx::managed::Ref<hxhx::managed::CellPayload>> " + root + "(" + heap + ");",
			indent + new CppManagedCellEmitter(plan, binding).renderAllocation(heap, root, declarations[index]),
			indent + "{",
			indent
			+ "  hxhx::managed::Root<hxhx::managed::Value> "
			+ initialized
			+ "("
			+ heap
			+ ");"];
		for (line in initializer(initialized, indent + "  "))
			lines.push(line);
		lines.push(indent + "  " + root + ".get()->write(" + initialized + ".get());");
		lines.push(indent + "}");
		return lines;
	}

	static function identifier(value:Null<String>):Bool
		return value != null && ~/^[A-Za-z_][A-Za-z0-9_]*$/.match(value);
}
