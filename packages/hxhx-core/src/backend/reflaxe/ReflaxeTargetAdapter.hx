package backend.reflaxe;

import backend.BackendRegistrationSpec;
import backend.ITargetCore;
import backend.TargetCoreBackend;
import backend.TargetDescriptor;

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
	public static function backend(descriptor:TargetDescriptor, coreFactory:Void->ITargetCore):TargetCoreBackend {
		final core = coreFactory();
		return new TargetCoreBackend(descriptor, function(program, context) return core.emit(program, context));
	}

	public static function registration(descriptor:TargetDescriptor, coreFactory:Void->ITargetCore):BackendRegistrationSpec {
		return {
			descriptor: descriptor,
			create: function() return backend(descriptor, coreFactory)
		};
	}

	public static function registrations(descriptor:TargetDescriptor, coreFactory:Void->ITargetCore):Array<BackendRegistrationSpec> {
		return [registration(descriptor, coreFactory)];
	}
}
