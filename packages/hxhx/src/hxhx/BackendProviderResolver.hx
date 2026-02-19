package hxhx;

import backend.BackendRegistrationSpec;
import backend.ITargetBackendProvider;
import backend.js.JsBackend;

private typedef ProviderDispatch = {
	function registrations():Array<BackendRegistrationSpec>;
}

/**
	Resolves Stage3 backend provider registrations by type path.

	Why
	- Stage3 needs deterministic provider loading with minimal runtime reflection.
	- Known builtin providers should be compile-time registered to avoid reflective
	  method invocation.
	- Custom providers still need a dynamic entrypoint, but with a typed contract.

		What
		- Fast-path known providers (currently `backend.js.JsBackend`) through a static table.
		- Fallback to typed instance loading for custom providers:
		  - `Type.resolveClass`
		  - `Type.createInstance`
		  - `Std.downcast(..., ITargetBackendProvider)`
		  - dispatch through `ProviderDispatch` structural view (`registrations()`)

		Gotchas
		- `Type.createInstance` returns an untyped runtime value.
		- Interface method dispatch on `ITargetBackendProvider` is not yet representable
		  as direct OCaml record-field access in this bootstrap lane.
		- `requireProvider` keeps contract validation typed via `Std.downcast(..., ITargetBackendProvider)`,
		  then returns a structural `ProviderDispatch` view for compile-safe invocation.
**/
class BackendProviderResolver {
	static inline function providerRegistrations(provider:ProviderDispatch):Array<BackendRegistrationSpec> {
		return provider.registrations();
	}

	static function requireProvider(instance:Dynamic, typePath:String):ProviderDispatch {
		final providerContract:Null<ITargetBackendProvider> = Std.downcast(instance, ITargetBackendProvider);
		if (providerContract == null) {
			throw "backend provider type must implement ITargetBackendProvider: " + typePath;
		}
		return cast providerContract;
	}

	static function knownProviderRegistrations(typePath:String):Null<Array<BackendRegistrationSpec>> {
		return switch (typePath) {
			case "backend.js.JsBackend":
				JsBackend.providerRegistrations();
			case _:
				null;
		}
	}

	public static function registrationsForType(typePath:String):Array<BackendRegistrationSpec> {
		final normalized = StringTools.trim(typePath == null ? "" : typePath);
		if (normalized.length == 0) throw "backend provider type path is required";

		final known = knownProviderRegistrations(normalized);
		if (known != null) return known;

		final cls = Type.resolveClass(normalized);
		if (cls == null) throw "backend provider type not found: " + normalized;

		final instance = try {
			Type.createInstance(cls, []);
		} catch (error:haxe.Exception) {
			throw "backend provider construction failed for " + normalized + ": " + error.message;
		}

		final provider = requireProvider(instance, normalized);
		return providerRegistrations(provider);
	}
}
