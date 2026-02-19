package backend;

/**
	Runtime backend provider contract.

	Why
	- Plugin/bundled backend layers need a way to register target backends at runtime
	  while reusing the canonical registry resolution logic.

	What
	- `registrations()`: returns backend registrations contributed by this provider.

	How
	- Providers should return deterministic descriptors and factories.
	- Registry precedence rules (`priority`, `implId` tie-break) still apply globally.
**/
interface ITargetBackendProvider {
	public function registrations():Array<BackendRegistrationSpec>;
}
