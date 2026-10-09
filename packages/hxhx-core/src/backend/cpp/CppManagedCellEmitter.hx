package backend.cpp;

/** Both method and initializer catalogs authorize allocation through the same exact cell fact. */
typedef CppManagedCellOwner = {
	function requireCell(binding:TyLocalBinding):backend.cpp.CppManagedStoragePlan.CppManagedCellPlan;
}

/** Assignment operands already use common Value transport; the caller owns the result root. */
typedef CppManagedCellWrite = {
	final heap:String;
	final cell:String;
	final value:String;
	final ?destination:String;
	final temporaryPrefix:String;
}

/**
	Emit storage operations for one exact promoted declaration.
	The shared capture facts own its allocation event and initialize-once policy.
	The enclosing function emitter must place allocation at that event and declare
	a scoped destination root. Reads copy values, and writes root the selected cell
	before evaluating their right-hand side. This preserves aliases and protects
	assignment through a closure whose last external reference disappears there.
	Source write permission and value conversions remain typing/lowering duties.
 */
class CppManagedCellEmitter {
	final plan:CppManagedCellOwner;
	final binding:TyLocalBinding;

	public function new(plan:CppManagedCellOwner, binding:TyLocalBinding) {
		if (plan == null)
			throw "managed cell requires an exact storage plan";
		this.plan = plan;
		this.binding = binding;
		plan.requireCell(binding);
	}

	/** Require the exact cataloged execution event, not just a matching event kind. */
	public function renderAllocation(heap:String, destination:String, event:TypedCaptureBinding):String {
		final cell = plan.requireCell(binding);
		if (event != cell.source)
			throw "managed cell allocation requires its exact source event";
		if (!identifier(heap) || !identifier(destination))
			throw "managed cell allocation requires stable heap and root symbols";
		final mode = cell.mode == InitializeOnce ? "Once" : "Replaceable";
		return heap + ".allocateInto(" + destination + ", hxhx::managed::CellWriteMode::" + mode + ");";
	}

	/** Copy into an existing root before any subsequent source expression can collect. */
	public function renderRead(cell:String, destination:String):String {
		plan.requireCell(binding);
		if (cell == null || cell.length == 0 || !identifier(destination))
			throw "managed cell read requires a cell and destination root";
		return destination + ".set((" + cell + ")->read());";
	}

	/** A failed right-hand side or rejected write preserves both the cell and result destination. */
	public function renderWrite(input:CppManagedCellWrite):String {
		plan.requireCell(binding);
		if (input == null
			|| !identifier(input.heap)
			|| !identifier(input.temporaryPrefix)
			|| !StringTools.startsWith(input.temporaryPrefix, "hxhx_cell_")
			|| (input.destination != null && !identifier(input.destination)))
			throw "managed cell write requires stable symbols and an allocated temporary prefix";
		if (input.cell == null || input.cell.length == 0 || input.value == null || input.value.length == 0)
			throw "managed cell write requires its selected place and value";
		final selected = input.temporaryPrefix + "selected";
		final value = input.temporaryPrefix + "value";
		final lines = ["{",
			"  hxhx::managed::Root<hxhx::managed::Ref<hxhx::managed::CellPayload>> "
			+ selected
			+ "("
			+ input.heap
			+ ", ("
			+ input.cell
			+ "));",
			"  hxhx::managed::Root<hxhx::managed::Value> " + value + "(" + input.heap + ", (" + input.value + "));",
			"  " + selected + ".get()->write(" + value + ".get());"
		];
		if (input.destination != null)
			lines.push("  " + input.destination + ".set(" + value + ".get());");
		lines.push("}");
		return lines.join("\n");
	}

	static function identifier(value:Null<String>):Bool
		return value != null && ~/^[A-Za-z_][A-Za-z0-9_]*$/.match(value);
}
