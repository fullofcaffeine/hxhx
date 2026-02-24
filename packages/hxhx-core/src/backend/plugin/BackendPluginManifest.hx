package backend.plugin;

/**
	Native backend plugin manifest v1.

	Why
	- Dynamic backend loading needs a deterministic metadata envelope independent from
	  provider implementation details.
	- Manifest metadata enables load-time compatibility checks before backend code is
	  instantiated.

	Schema summary
	- `schemaVersion`: manifest schema version (`1`).
	- `pluginId`: stable plugin identifier.
	- `pluginVersion`: plugin release/version string.
	- `backend`: activation metadata (`kind`, `entry`, `targetIds`).
	- `requires`: runtime compatibility requirements (`abiVersion`, `genIrVersion`,
	  `macroApiVersion`).
**/
typedef BackendPluginManifest = {
	final schemaVersion:Int;
	final pluginId:String;
	final pluginVersion:String;
	final backend:BackendPluginManifestBackend;
	final requires:BackendPluginManifestRequires;
}

/**
	Backend activation details from a plugin manifest.
**/
typedef BackendPluginManifestBackend = {
	final kind:BackendPluginManifestKind;
	final entry:String;
	final targetIds:Array<String>;
}

/**
	Runtime compatibility requirements declared in the plugin manifest.
**/
typedef BackendPluginManifestRequires = {
	final abiVersion:Int;
	final genIrVersion:Int;
	final macroApiVersion:Int;
}
