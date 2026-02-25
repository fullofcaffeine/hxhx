package backend.reflaxe;

import backend.BackendContext;
import backend.BackendRegistrationSpec;
import backend.EmitResult;
import backend.GenIrProgram;
import backend.TargetCoreBackend;
import backend.TargetDescriptor;

private typedef TargetCoreEmit = GenIrProgram->BackendContext->EmitResult;

/**
	Reusable adapter for reflaxe-style backend promotion.

	Why
	- Reflaxe targets should keep one shared target-core implementation and expose it
	  through thin wrappers (builtin and provider/plugin) without duplicating boilerplate.
	- Promotion from plugin mode to builtin mode should be a packaging decision, not a
	  codegen rewrite.

	What
	- Builds `TargetCoreBackend` wrappers from a `TargetDescriptor` + target-core factory.
	- Produces deterministic provider registration payloads (`BackendRegistrationSpec`).

	How
	- `backend(...)` creates one wrapper instance for builtin usage.
	- `registration(...)` and `registrations(...)` expose the same core behind provider
	  factories for runtime plugin loading.

	Adapter constraints (migration guardrails)
	- Target core must be pure codegen logic (`ITargetCore.emit`) and must not depend on
	  wrapper/runtime registration state.
	- Descriptor compatibility remains enforced by `BackendRegistry` / `BackendAbi`; the
	  adapter does not bypass ABI checks.
	- Wrapper paths must keep behavior identical across activation modes for the same
	  target core + descriptor pair.
**/
class ReflaxeTargetAdapter {
	public static function backend(descriptor:TargetDescriptor, coreEmitFactory:Void->TargetCoreEmit):TargetCoreBackend {
		return new TargetCoreBackend(descriptor, coreEmitFactory());
	}

	public static function registration(descriptor:TargetDescriptor, coreEmitFactory:Void->TargetCoreEmit):BackendRegistrationSpec {
		return {
			descriptor: descriptor,
			create: function() return backend(descriptor, coreEmitFactory)
		};
	}

	public static function registrations(descriptor:TargetDescriptor, coreEmitFactory:Void->TargetCoreEmit):Array<BackendRegistrationSpec> {
		return [registration(descriptor, coreEmitFactory)];
	}
}
