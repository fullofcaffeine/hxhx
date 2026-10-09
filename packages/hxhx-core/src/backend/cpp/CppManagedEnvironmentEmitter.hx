package backend.cpp;

/** Exact closure lookup shared by callable bodies and field initializer capture storage. */
typedef CppManagedEnvironmentOwner = {
	function requireClosure(expression:HxExpr):backend.cpp.CppManagedStoragePlan.CppManagedFunctionPlan;
}

/** An exact captured binding and a pure native expression for its existing cell reference. */
typedef CppManagedEnvironmentCapture = {
	final binding:TyLocalBinding;
	final reference:String;
}

/** Existing destination root and input references; allocation never executes source initialization. */
typedef CppManagedEnvironmentConstruction = {
	final heap:String;
	final destination:String;
	final entry:String;
	final captures:Array<CppManagedEnvironmentCapture>;
	final ?receiver:String;
	final temporaryPrefix:String;
}

/**
	Render one immutable native environment from exact shared capture identities.
	Every field is an edge to the same cell used by the creator and its other
	closures. Receiver binding storage is separate from source local declarations.
	The caller must root all input cells before allocating this environment and
	publish the environment into a root before allocating its callable payload.
	This emitter supplies layout and tracing only; it does not emit function bodies
	or infer capture membership from source names or C++ text.
 */
class CppManagedEnvironmentEmitter {
	final plan:CppManagedEnvironmentOwner;
	final expression:HxExpr;

	public final nativeName:String;

	public function new(plan:CppManagedEnvironmentOwner, expression:HxExpr, nativeName:String) {
		if (plan == null || expression == null)
			throw "managed environment requires an exact closure plan";
		if (nativeName == null || !~/^hxhx_env_[A-Za-z0-9_]+$/.match(nativeName))
			throw "managed environment requires a generated C++ identifier";
		this.plan = plan;
		this.expression = expression;
		this.nativeName = nativeName;
		plan.requireClosure(expression);
	}

	/** Select storage by declaration identity, never by a same-spelled shadowed name. */
	public function cellField(binding:TyLocalBinding):String {
		final cells = plan.requireClosure(expression).getCells();
		for (index in 0...cells.length)
			if (binding != null && cells[index].source.binding.getCanonicalIdentity() == binding.getCanonicalIdentity())
				return "captured.cell" + index;
		throw "binding is not captured by this managed environment";
	}

	/** Receiver capture uses a binding cell, preserving constructor assignment and null presence. */
	public function receiverField():String {
		if (!plan.requireClosure(expression).facts.capturesReceiver)
			throw "managed environment does not capture a receiver";
		return "captured.receiver";
	}

	/**
		Snapshot exact cell edges into roots before either collecting allocation.
		References must be pure reads from already live cells, including forwarded
		environment fields. Entry is a stable typed function-pointer symbol. The
		caller allocates the unique temporary prefix and owns the destination root.
		Failed allocation leaves its previous callable intact; the temporary
		environment becomes collectible when this block unwinds.
	 */
	public function renderConstruction(input:CppManagedEnvironmentConstruction):String {
		final closure = plan.requireClosure(expression);
		if (input == null || input.captures == null || input.captures.length != closure.getCells().length)
			throw "managed construction requires exactly its captured cells";
		for (name in [input.heap, input.destination, input.entry, input.temporaryPrefix])
			if (name == null || !~/^[A-Za-z_][A-Za-z0-9_]*$/.match(name))
				throw "managed construction requires stable native symbols";
		if (!StringTools.startsWith(input.temporaryPrefix, "hxhx_construct_"))
			throw "managed construction requires an allocated temporary prefix";
		if (closure.facts.capturesReceiver ? input.receiver == null || input.receiver.length == 0 : input.receiver != null)
			throw "managed construction receiver disagrees with capture facts";
		final supplied = new haxe.ds.StringMap<String>();
		for (capture in input.captures) {
			if (capture == null || capture.binding == null || capture.reference == null || capture.reference.length == 0)
				throw "managed construction lacks a captured cell reference";
			cellField(capture.binding);
			final identity = capture.binding.getCanonicalIdentity();
			if (supplied.exists(identity))
				throw "managed construction repeats a captured binding";
			supplied.set(identity, capture.reference);
		}
		final references = [
			for (cell in closure.getCells())
				supplied.get(cell.source.binding.getCanonicalIdentity())
		];
		if (closure.facts.capturesReceiver)
			references.push(input.receiver);
		final prefix = input.temporaryPrefix;
		final lines = ["{"];
		final fields = new Array<String>();
		for (index in 0...references.length) {
			final root = prefix + "cell" + index;
			lines.push("  hxhx::managed::Root<hxhx::managed::Ref<hxhx::managed::CellPayload>> "
				+ root
				+ "("
				+ input.heap
				+ ", ("
				+ references[index]
				+ "));");
			fields.push(root + ".get()");
		}
		final environment = prefix + "environment";
		lines.push("  hxhx::managed::Root<hxhx::managed::Ref<" + nativeName + ">> " + environment + "(" + input.heap + ");");
		lines.push("  " + input.heap + ".allocateInto(" + environment + ", " + nativeName + "::Captures{" + fields.join(", ") + "});");
		lines.push("  "
			+ input.heap
			+ ".allocateInto("
			+ input.destination
			+ ", "
			+ input.entry
			+ ", hxhx::managed::ErasedRef("
			+ environment
			+ ".get()));");
		lines.push("}");
		return lines.join("\n");
	}

	/** The runtime header must precede this global-scope declaration and trace specialization. */
	public function render():String {
		final closure = plan.requireClosure(expression);
		final fields = [for (index in 0...closure.getCells().length) "cell" + index];
		if (closure.facts.capturesReceiver)
			fields.push("receiver");
		final lines = ["struct " + nativeName + " {", "  struct Captures {"];
		for (field in fields)
			lines.push("    hxhx::managed::Ref<hxhx::managed::CellPayload> " + field + ";");
		lines.push("  };");
		lines.push("  const Captures captured;");
		lines.push("  explicit " + nativeName + "(Captures input) noexcept : captured(input) {}");
		lines.push("};");
		lines.push("namespace hxhx::managed {");
		lines.push("template<> struct Trace<::" + nativeName + "> {");
		lines.push("  static void visit(const ::" + nativeName + "& value, Visitor& visitor) noexcept {");
		if (fields.length == 0) {
			lines.push("    (void)value;");
			lines.push("    (void)visitor;");
		}
		for (field in fields)
			lines.push("    visitor.mark(value.captured." + field + ");");
		lines.push("  }");
		lines.push("};");
		lines.push("}");
		return lines.join("\n");
	}
}
