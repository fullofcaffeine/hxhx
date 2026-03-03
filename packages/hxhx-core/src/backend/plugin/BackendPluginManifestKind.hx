package backend.plugin;

/**
	Supported backend plugin manifest runtime kinds.

	Why
	- Plugin manifests must declare how backend registrations are activated at runtime.
	- We intentionally keep kinds explicit so unsupported activation paths fail fast.

	Current kinds
	- `linked-provider`: resolves a provider class already linked into the current
	  `hxhx` build (not dynlinked) and implementing
	  `backend.ITargetBackendProvider`.
	- `ocaml-dynlink`: points to a native OCaml plugin artifact; loading is validated at
	  manifest parse time and activated later by the native plugin loader.
**/
enum abstract BackendPluginManifestKind(String) to String {
	var LinkedProvider = "linked-provider";
	var OcamlDynlink = "ocaml-dynlink";
}
