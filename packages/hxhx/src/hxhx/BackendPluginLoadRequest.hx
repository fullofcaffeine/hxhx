package hxhx;

/**
	Request-scoped plugin provider load declaration.

	Fields
	- `source`: precedence tier (`bundled` or `explicit`).
	- `providerType`: provider class type path (`ITargetBackendProvider` implementation).
	- `origin`: diagnostics label (declaration source, manifest path, etc.).
**/
typedef BackendPluginLoadRequest = {
	final source:BackendPluginSource;
	final providerType:String;
	final origin:String;
}
