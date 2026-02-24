package backend.plugin;

/**
	Supported backend plugin manifest runtime kinds.

	Why
	- Plugin manifests must declare how backend registrations are activated at runtime.
	- We intentionally keep kinds explicit so unsupported activation paths fail fast.

	Current kinds
	- `haxe-provider`: loads a Haxe provider class implementing
	  `backend.ITargetBackendProvider`.
	- `ocaml-cmxs`: points to a native OCaml plugin artifact; loading is validated at
	  manifest parse time and activated later by the native plugin loader.
**/
enum abstract BackendPluginManifestKind(String) to String {
	var HaxeProvider = "haxe-provider";
	var OcamlCmxs = "ocaml-cmxs";
}
