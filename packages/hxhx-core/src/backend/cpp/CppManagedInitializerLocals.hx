package backend.cpp;

/**
	Root initializer locals at their exact declaration or handler-entry events.
	These bindings belong to the field body, not the surrounding constructor.
	Captured bindings use shared cells selected by the initializer's capture catalog.
	Closure entry emission remains a separate responsibility.
 */
class CppManagedInitializerLocals {
	final projection:TypedBackendFieldInitializerProjection;
	final declarations:Array<TypedCaptureBinding>;
	final prefix:String;

	public final captures:CppManagedInitializerStorage;

	public function new(projection:TypedBackendFieldInitializerProjection, prefix:String, ?application:CppManagedInitializerApplication) {
		if (projection == null || !~/^[A-Za-z_][A-Za-z0-9_]*$/.match(prefix))
			throw "initializer locals require an exact owner and allocated symbols";
		this.projection = projection;
		this.prefix = prefix;
		final catalog = projection.requireCaptureCatalog();
		captures = new CppManagedInitializerStorage(projection, application);
		final facts = catalog.getPlan();
		final root = facts.getFunctions()[0];
		declarations = [
			for (entry in facts.getBindings())
				if (entry.functionIdentity == root.identity && (entry.creation == Declaration || entry.creation == CatchEntry)) entry
		];
	}

	public function binding(name:String):TyLocalBinding {
		projection.assertCurrent();
		final entry = projection.getLocalCatalog().findByProjectedName(name);
		if (entry == null)
			throw "initializer local is absent from its exact catalog";
		root(entry.getBinding());
		return entry.getBinding();
	}

	public function root(binding:TyLocalBinding):String {
		projection.assertCurrent();
		for (index in 0...declarations.length)
			if (declarations[index].binding == binding)
				return prefix + index;
		throw "initializer local lacks its exact root declaration event";
	}

	function promoted(binding:TyLocalBinding):Bool {
		for (cell in captures.getCells())
			if (cell.source.binding == binding)
				return true;
		return false;
	}

	public function value(binding:TyLocalBinding):String {
		final selected = root(binding);
		return selected + (promoted(binding) ? ".get()->read()" : ".get()");
	}

	public function place(binding:TyLocalBinding):CppManagedPlace {
		final selected = root(binding);
		return promoted(binding) ? Cell(selected + ".get()") : LocalRoot(selected);
	}

	/** Descendant environments receive the same mutable location, never a copy of its value. */
	public function cellReference(binding:TyLocalBinding):String {
		final selected = root(binding);
		captures.requireCell(binding);
		return selected + ".get()";
	}

	/** A compiler result slot starts unassigned and is written by shared control lowering. */
	public function declare(binding:TyLocalBinding, initializer:Null<HxExpr>, heap:String, indent:String,
			render:(HxExpr, String, String) -> Array<String>):Array<String> {
		requireEvent(binding, Declaration);
		if (initializer == null && !(binding.getKind() == CompilerTemporary && binding.getIdentity().isCompilerTemporary()))
			throw "initializer unassigned source local requires definite-assignment evidence";
		return initialize(binding, heap, indent, initializer == null ? null : (root, at) -> render(initializer, root, at));
	}

	/** The handler owns matching; keep its selected value rooted while this field allocates a fresh cell. */
	public function renderCatch(binding:TyLocalBinding, selectedRoot:String, heap:String, indent:String):Array<String> {
		requireEvent(binding, CatchEntry);
		if (binding.getKind() != CatchVariable
			|| selectedRoot == null
			|| heap == null
			|| !~/^[A-Za-z_][A-Za-z0-9_]*$/.match(selectedRoot)
			|| !~/^[A-Za-z_][A-Za-z0-9_]*$/.match(heap))
			throw "initializer catch requires its exact creation event and rooted value";
		return initialize(binding, heap, indent, (root, at) -> [at + root + ".set(" + selectedRoot + ".get());"]);
	}

	function requireEvent(binding:TyLocalBinding, event:TypedCaptureBinding.TypedCaptureCreation):Void {
		root(binding);
		for (entry in declarations)
			if (entry.binding == binding && entry.creation == event)
				return;
		throw "initializer local requires its exact creation event";
	}

	/** Declaration and catch entry share the same rooted allocation and publication path. */
	function initialize(binding:TyLocalBinding, heap:String, indent:String, fill:Null<(String, String) -> Array<String>>):Array<String> {
		final selected = root(binding);
		if (promoted(binding)) {
			final cell = captures.requireCell(binding);
			final lines = [
				indent + "hxhx::managed::Root<hxhx::managed::Ref<hxhx::managed::CellPayload>> " + selected + "(" + heap + ");",
				indent + new CppManagedCellEmitter(captures, binding).renderAllocation(heap, selected, cell.source)
			];
			if (fill != null) {
				final temporary = selected + "_initializer";
				lines.push(indent + "{");
				lines.push(indent + "  hxhx::managed::Root<hxhx::managed::Value> " + temporary + "(" + heap + ");");
				for (line in fill(temporary, indent + "  "))
					lines.push(line);
				lines.push(indent + "  " + selected + ".get()->write(" + temporary + ".get());");
				lines.push(indent + "}");
			}
			return lines;
		}
		final lines = [indent + "hxhx::managed::LocalSlot " + selected + "(" + heap + ");"];
		return fill == null ? lines : lines.concat(fill(selected, indent));
	}
}
