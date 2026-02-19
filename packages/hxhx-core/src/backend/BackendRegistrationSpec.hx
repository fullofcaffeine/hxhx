package backend;

/**
	Public backend registration payload used by registry providers.

	Why
	- We need a stable contract for dynamic registrations (for example plugin-provided
	  backend wrappers) without exposing registry internals.

	What
	- `descriptor`: backend identity/capability metadata.
	- `create`: factory for producing an `IBackend` instance.
**/
typedef BackendRegistrationSpec = {
	final descriptor:TargetDescriptor;
	final create:Void->IBackend;
}

