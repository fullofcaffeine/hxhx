package hxhx;

import backend.BackendRegistrationSpec;
import backend.ITargetBackendProvider;
import backend.js.JsBackend;

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
	  - `ITargetBackendProvider.registrations()`

	Gotchas
	- `Type.createInstance` returns an untyped runtime value. We keep one guarded cast
	  at this boundary after `Std.isOfType(..., ITargetBackendProvider)` succeeds.
**/
class BackendProviderResolver {
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
		} catch (error:Dynamic) {
			throw "backend provider construction failed for " + normalized + ": " + Std.string(error);
		}

		if (!Std.isOfType(instance, ITargetBackendProvider)) {
			throw "backend provider type must implement ITargetBackendProvider: " + normalized;
		}

		final registrationsFn = Reflect.field(instance, "registrations");
		if (registrationsFn == null) {
			throw "backend provider type must expose registrations(): " + normalized;
		}
		return cast Reflect.callMethod(instance, registrationsFn, []);
	}
}
