package backend;

/**
	Generic `IBackend` adapter that delegates emission to an `ITargetCore`.

	Why
	- Builtin and plugin wrappers should be thin activation layers around shared
	  target-core codegen logic.
	- This avoids repeating backend boilerplate for every target wrapper.

	What
	- Binds one `TargetDescriptor` with one `ITargetCore`.
	- Implements `IBackend` by forwarding identity/capability metadata from the descriptor
	  and `emit(...)` to the target core.

	How
	- Use this as the base adapter for wrapper backends (`ocaml-stage3`, `js-native`,
	  and future plugin wrappers).
**/
class TargetCoreBackend implements IBackend {
	final backendDescriptor:TargetDescriptor;
	final targetCore:ITargetCore;

	public function new(backendDescriptor:TargetDescriptor, targetCore:ITargetCore) {
		this.backendDescriptor = backendDescriptor;
		this.targetCore = targetCore;
	}

	public function id():String {
		return backendDescriptor.id;
	}

	public function describe():String {
		return backendDescriptor.description;
	}

	public function capabilities():BackendCapabilities {
		return backendDescriptor.capabilities;
	}

	public function emit(program:GenIrProgram, context:BackendContext):EmitResult {
		return targetCore.emit(program, context);
	}
}

