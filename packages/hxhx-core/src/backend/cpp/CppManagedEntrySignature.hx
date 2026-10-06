package backend.cpp;

/** Render the selected callable ABI without consuming hidden operands as source argument slots. */
function render(abi:CppManagedClosureAbi, symbol:String):String {
	final parameters = [
		for (hidden in abi.getHiddenParameters())
			switch hidden {
				case HeapContext:
					"hxhx::managed::Heap& hxhx_heap";
				case EnvironmentPointer:
					"hxhx::managed::ErasedRef hxhx_environment";
				case ReceiverValue:
					"hxhx::managed::Value hxhx_receiver";
				case ReceiverCell:
					"hxhx::managed::Ref<hxhx::managed::CellPayload> hxhx_receiver";
				case ResultRoot:
					"hxhx::managed::Root<hxhx::managed::Value>& hxhx_result";
			}
	];
	for (parameter in abi.getParameters())
		parameters.push((parameter.storage == RootedParameter ? "hxhx::managed::Value" : CppManagedLeaf.nativeType(parameter.type))
			+ " hxhx_arg"
			+ parameter.slot);
	return abi.nativeReturnType() + " " + symbol + "(" + parameters.join(", ") + ")";
}
