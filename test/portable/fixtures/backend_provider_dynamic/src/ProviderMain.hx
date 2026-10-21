import hxhx.BackendProviderResolver;

/** Exercises the real resolver after the built-in-provider table declines the name. */
class ProviderMain {
	static function main():Void {
		final path = Type.getClassName(NativeProvider);
		final registrations = BackendProviderResolver.registrationsForType(path);
		if (NativeProvider.constructions != 1 || NativeProvider.calls != 1 || registrations.length != 0)
			throw "dynamic provider fallback did not execute exactly once";
		Sys.println("dynamic-provider:executed");
	}
}
