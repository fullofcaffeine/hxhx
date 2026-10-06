package backend.cpp;

/**
	Root incoming values before allocating any captured parameter cells.
	The exact root or closure plan supplies declaration identities and transport
	types. Parameter roots are established as one non-collecting phase. Conditional
	initializers then update those roots before captured parameters receive cells. Callers
	allocate unique temporary names and place the prologue before source effects.
 */
class CppManagedParameterEmitter {
	final plan:CppManagedCallableStorage;
	final owner:CppManagedFunctionOwner;
	final prefix:String;
	final inputs:Array<String>;

	public function new(plan:CppManagedCallableStorage, owner:CppManagedFunctionOwner, inputs:Array<String>, prefix:String) {
		if (plan == null || inputs == null || !identifier(prefix) || !StringTools.startsWith(prefix, "hxhx_parameters_"))
			throw "managed parameters require a plan and allocated temporary prefix";
		final closure = plan.requireFunction(owner);
		if (inputs.length != closure.getParameters().length)
			throw "managed parameter symbols disagree with source arity";
		final seen = new haxe.ds.StringMap<Bool>();
		for (input in inputs) {
			if (!identifier(input) || seen.exists(input))
				throw "managed parameters require distinct stable input symbols";
			seen.set(input, true);
		}
		this.plan = plan;
		this.owner = owner;
		this.inputs = inputs.copy();
		this.prefix = prefix;
	}

	/** The initializer can allocate after all roots exist; parameter cells are not readable until it completes. */
	public function render(heap:String, ?initialize:Int->String->Array<String>):String {
		final closure = plan.requireFunction(owner);
		if (!identifier(heap))
			throw "managed parameter ingress requires a stable heap symbol";
		final lines = new Array<String>();
		for (parameter in closure.abi.getParameters())
			if (parameter.storage == RootedParameter)
				lines.push("hxhx::managed::Root<hxhx::managed::Value> " + prefix + "value" + parameter.slot + "(" + heap + ", " + inputs[parameter.slot] +
					");");
		if (initialize != null)
			for (parameter in closure.abi.getParameters())
				if (parameter.storage == RootedParameter)
					for (line in initialize(parameter.slot, prefix + "value" + parameter.slot))
						lines.push(line);
		// A generic caller may supply null through the common function-value ABI.
		// Convert only a required concrete scalar, after rooting every operand and
		// before copying parameter values into captured cells. Optional values keep null.
		final declared = closure.abi.signature.getFunctionParameters();
		for (parameter in closure.abi.getParameters())
			if (parameter.storage == RootedParameter
				&& !declared[parameter.slot].isOptional
				&& CppManagedCallableRepresentation.scalar(parameter.type))
				for (line in CppManagedValueTransfer.convertRoot(parameter.type, TyType.nullable(parameter.type), prefix + "value" + parameter.slot, ""))
					lines.push(line);
		for (parameter in closure.getParameters()) {
			if (!promoted(parameter.binding))
				continue;
			final root = prefix + "cell" + parameter.slot;
			lines.push("hxhx::managed::Root<hxhx::managed::Ref<hxhx::managed::CellPayload>> " + root + "(" + heap + ");");
			lines.push(new CppManagedCellEmitter(plan, parameter.binding).renderAllocation(heap, root, parameter));
			lines.push(root + ".get()->write(" + incomingValue(parameter.slot) + ");");
		}
		return lines.join("\n");
	}

	/** Read the current shared cell when promoted; otherwise use this invocation's own input storage. */
	public function value(binding:TyLocalBinding):String {
		final slot = requireSlot(binding);
		return promoted(binding) ? prefix + "cell" + slot + ".get()->read()" : incomingValue(slot);
	}

	/** Forward the existing cell to a descendant environment instead of copying its current value. */
	public function cellReference(binding:TyLocalBinding):String {
		final slot = requireSlot(binding);
		if (!promoted(binding))
			throw "managed parameter is not captured by a descendant";
		return prefix + "cell" + slot + ".get()";
	}

	function requireSlot(binding:TyLocalBinding):Int {
		for (parameter in plan.requireFunction(owner).getParameters())
			if (binding != null && parameter.binding.getCanonicalIdentity() == binding.getCanonicalIdentity())
				return parameter.slot;
		throw "binding is not a parameter of this managed closure";
	}

	/** Managed parameters are mutable roots or promoted cells; direct leaves need their own write transport. */
	public function place(binding:TyLocalBinding):CppManagedPlace {
		final slot = requireSlot(binding);
		if (promoted(binding))
			return Cell(prefix + "cell" + slot + ".get()");
		if (plan.requireFunction(owner).abi.getParameters()[slot].storage != RootedParameter)
			throw "direct parameter assignment requires explicit leaf write transport";
		return LocalRoot(prefix + "value" + slot);
	}

	function promoted(binding:TyLocalBinding):Bool {
		for (cell in plan.getCells())
			if (cell.source.binding.getCanonicalIdentity() == binding.getCanonicalIdentity())
				return true;
		return false;
	}

	function incomingValue(slot:Int):String {
		final parameter = plan.requireFunction(owner).abi.getParameters()[slot];
		if (parameter.storage == RootedParameter)
			return prefix + "value" + slot + ".get()";
		return CppManagedLeaf.box(parameter.type, inputs[slot]);
	}

	static function identifier(value:Null<String>):Bool
		return value != null && ~/^[A-Za-z_][A-Za-z0-9_]*$/.match(value);
}
