package backend.cpp;

/**
	Keep an instance entry's receiver live before parameter cells can allocate.
	A descendant closure needs one traced cell shared by all of its receiver
	captures. Create that cell only after ordinary parameters have been rooted.
	Abstract constructors instead receive an already allocated writable cell.
	Their root and descendants retain that cell, so writes survive capture and
	final result publication cannot empty or replace the captured location.
	This boundary does not select class layout, allocate instances, or dispatch methods.
 */
class CppManagedReceiverStorage {
	final plan:CppManagedBodyStorage;
	final input:String;
	final prefix:String;
	final captured:Bool;
	final writable:Bool;

	public function new(projection:TypedBackendFunctionProjection, plan:CppManagedBodyStorage, input:String, prefix:String) {
		if (projection == null || plan == null || !identifier(input) || !identifier(prefix))
			throw "managed receiver requires an exact entry and allocated symbols";
		final hidden = plan.requireFunction(Root(projection)).abi.getHiddenParameters();
		writable = hidden.contains(ReceiverCell);
		if (!hidden.contains(ReceiverValue) && !writable)
			throw "managed receiver storage requires an instance entry";
		this.plan = plan;
		this.input = input;
		this.prefix = prefix;
		captured = projection.requireCaptureCatalog()
			.getPlan()
			.getFunctions()
			.filter(fn -> fn.capturesReceiver)
			.length != 0;
	}

	/** Register before any parameter cell allocation; this phase cannot collect. */
	public function renderRoot(heap:String):String {
		plan.assertCurrent();
		if (!identifier(heap))
			throw "managed receiver ingress requires a stable heap symbol";
		return writable ? "hxhx::managed::Root<hxhx::managed::Ref<hxhx::managed::CellPayload>> "
			+ prefix
			+ "cell("
			+ heap
			+ ", "
			+ input
			+ ");" : "hxhx::managed::Root<hxhx::managed::Value> "
			+ prefix
			+ "value("
			+ heap
			+ ", "
			+ input
			+ ");";
	}

	/** Parameters and the receiver are already rooted before this possible allocation. */
	public function renderCapture(heap:String):String {
		plan.assertCurrent();
		if (!identifier(heap))
			throw "managed receiver capture requires a stable heap symbol";
		return writable
			|| !captured ? "" : "hxhx::managed::Root<hxhx::managed::Ref<hxhx::managed::CellPayload>> "
			+ prefix
			+ "cell("
			+ heap
			+ ");\n"
			+ heap
			+ ".allocateInto("
			+ prefix
			+ "cell, hxhx::managed::CellWriteMode::Once);\n"
			+ prefix
			+ "cell.get()->write("
			+ prefix
			+ "value.get());";
	}

	public function value():String {
		plan.assertCurrent();
		return writable || captured ? reference() + "->read()" : prefix + "value.get()";
	}

	/** All sibling and descendant environments retain the same receiver location. */
	public function reference():String {
		plan.assertCurrent();
		if (!captured && !writable)
			throw "managed receiver has no captured binding cell";
		return prefix + "cell.get()";
	}

	static function identifier(value:Null<String>):Bool
		return value != null && ~/^[A-Za-z_][A-Za-z0-9_]*$/.match(value);
}
