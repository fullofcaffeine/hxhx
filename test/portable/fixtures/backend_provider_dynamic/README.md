# Dynamic backend provider

Run `PORTABLE_FIXTURE_ALLOWLIST=backend_provider_dynamic bash scripts/test-portable.sh`
from the repository root.

This fixture calls the real BackendProviderResolver with a custom provider.
The resolver must load its class by name, construct it, narrow it to the provider
interface, and invoke registrations through the structural method view.
Constructor and method counters prove the dynamic path ran exactly once.
A stored string checks that the method receives the original provider object.

The provider returns an empty registration array. This proves dispatch and the
array result carrier; it does not claim that a backend factory or emission ran.
The same observer runs with upstream Haxe and with native OCaml output.

Full dead-code elimination excludes unused compiler functions reached through
backend contract types. The custom provider is explicitly retained for class
lookup. The build also retains its interface declaration: the explicit cast to
a structural view does not make that declaration reachable to upstream DCE.
Both compilers receive the same retention configuration. Missing source method
declarations remain a compiler error, rather than authorizing unchecked dispatch.
Constructor and method counters still prove the real resolver path ran.
Coarse progress logging makes long native compilation phases visible.
