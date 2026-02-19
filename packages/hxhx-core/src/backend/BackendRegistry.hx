package backend;

import backend.js.JsBackend;
import backend.ocaml.OcamlStage3Backend;

/**
	Canonical registry for builtin Stage3 backend implementations.

	Why
	- Backend selection currently exists in multiple places (target presets, Stage3 switches,
	  and docs), which increases drift risk.
	- A single registry gives us one source of truth for target IDs, implementation metadata,
	  and precedence behavior.

	What
	- Stores builtin backend registrations (`descriptor` + factory).
	- Resolves the active implementation for a target ID using deterministic precedence:
	  highest `priority`, then stable `implId` tie-break.
	- Exposes descriptor listings for diagnostics and docs.

	How
	- Keep registration static and explicit for now (linked builtin targets only).
	- Plugin discovery can extend this model later by appending runtime registrations
	  without changing Stage3 call sites.
**/
class BackendRegistry {
	static final builtinRegistrations:Array<BackendRegistrationSpec> = [
		{
			descriptor: OcamlStage3Backend.descriptor(),
			create: function() return new OcamlStage3Backend()
		},
		{
			descriptor: JsBackend.descriptor(),
			create: function() return new JsBackend()
		}
	];

	static final dynamicRegistrations:Array<BackendRegistrationSpec> = [];

	static function allRegistrations():Array<BackendRegistrationSpec> {
		return builtinRegistrations.concat(dynamicRegistrations);
	}

	static function sortedForTarget(targetId:String):Array<BackendRegistrationSpec> {
		final normalized = targetId == null ? "" : targetId;
		final candidates = allRegistrations().filter(function(r) return r.descriptor.id == normalized);
		candidates.sort(function(a, b) {
			if (a.descriptor.priority != b.descriptor.priority) {
				return b.descriptor.priority - a.descriptor.priority;
			}
			return a.descriptor.implId < b.descriptor.implId ? -1 : (a.descriptor.implId > b.descriptor.implId ? 1 : 0);
		});
		return candidates;
	}

	public static function listDescriptors():Array<TargetDescriptor> {
		return allRegistrations().map(function(r) return r.descriptor);
	}

	public static function supportedTargetIds():Array<String> {
		final seen = new haxe.ds.StringMap<Bool>();
		final ids = new Array<String>();
		for (r in allRegistrations()) {
			final id = r.descriptor.id;
			if (seen.exists(id))
				continue;
			seen.set(id, true);
			ids.push(id);
		}
		return ids;
	}

	public static function register(spec:BackendRegistrationSpec):Void {
		if (spec == null || spec.descriptor == null || spec.create == null) {
			throw "invalid backend registration (descriptor/create required)";
		}
		final d = spec.descriptor;
		if (d.id == null || d.id.length == 0)
			throw "invalid backend registration: descriptor.id is required";
		if (d.implId == null || d.implId.length == 0)
			throw "invalid backend registration: descriptor.implId is required";
		dynamicRegistrations.push(spec);
	}

	public static function registerProvider(regs:Array<BackendRegistrationSpec>):Int {
		if (regs == null || regs.length == 0)
			return 0;
		for (reg in regs)
			register(reg);
		return regs.length;
	}

	public static function clearDynamicRegistrations():Void {
		dynamicRegistrations.splice(0, dynamicRegistrations.length);
	}

	public static function descriptorForTarget(targetId:String):Null<TargetDescriptor> {
		final candidates = sortedForTarget(targetId);
		return candidates.length == 0 ? null : candidates[0].descriptor;
	}

	public static function createForTarget(targetId:String):Null<IBackend> {
		final candidates = sortedForTarget(targetId);
		return candidates.length == 0 ? null : candidates[0].create();
	}

	public static function requireForTarget(targetId:String):IBackend {
		final backend = createForTarget(targetId);
		if (backend != null)
			return backend;
		final supported = supportedTargetIds();
		supported.sort(function(a, b) return a < b ? -1 : (a > b ? 1 : 0));
		throw "unknown Stage3 backend: " + targetId + " (supported: " + supported.join(", ") + ")";
	}
}
