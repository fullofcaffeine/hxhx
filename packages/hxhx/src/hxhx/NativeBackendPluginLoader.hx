package hxhx;

import backend.BackendRegistrationSpec;
import backend.plugin.BackendPluginManifest;
import backend.plugin.BackendPluginManifestKind;

/**
	Typed native plugin load adapter (`ocaml-cmxs` manifest kind).

	Why
	- `BackendPluginManifestResolver` needs one place to activate native plugin manifests
	  without leaking runtime-boundary concerns.
	- We keep stage3 deterministic by validating registration conflicts immediately after
	  load and before registry registration.

	How
	- Call the OCaml Dynlink runtime bridge to load plugin + capture registration snapshot.
	- Decode provider types via `NativeBackendPluginHostAbi`.
	- Resolve provider registration specs and fail fast on conflicts (`implId`, target ID).
**/
class NativeBackendPluginLoader {
	static inline function trim(value:String):String {
		return value == null ? "" : StringTools.trim(value);
	}

	static function fail(sourceLabel:String, message:String):Void {
		final source = trim(sourceLabel);
		final label = source.length == 0 ? "<unknown-manifest>" : source;
		throw "backend plugin manifest (" + label + "): " + message;
	}

	static function resolvedSpecsForProviders(providerTypes:Array<String>):Array<BackendRegistrationSpec> {
		final specs = new Array<BackendRegistrationSpec>();
		for (providerType in providerTypes) {
			final providerSpecs = BackendProviderResolver.registrationsForType(providerType);
			for (spec in providerSpecs)
				specs.push(spec);
		}
		return specs;
	}

	public static function providerTypeNamesForNativeManifest(manifest:BackendPluginManifest, manifestPath:String):Array<String> {
		if (manifest == null || manifest.backend == null)
			fail(manifestPath, "manifest backend section is required");
		if (manifest.backend.kind != BackendPluginManifestKind.OcamlCmxs)
			fail(manifestPath, "native loader expects backend.kind=ocaml-cmxs");

		final snapshot = try {
			NativeBackendPluginDynlink.loadAndCapture(manifestPath, manifest.backend.entry, manifest.pluginId);
		} catch (error:haxe.Exception) {
			fail(manifestPath, "native plugin load failed: " + error.message);
			return [];
		}
		final providerTypes = NativeBackendPluginHostAbi.providerTypesForPluginAllowEmpty(snapshot, manifest.pluginId, manifestPath);
		if (providerTypes.length == 0)
			return [];
		final specs = resolvedSpecsForProviders(providerTypes);
		NativeBackendPluginHostAbi.assertNoDescriptorConflicts(manifest.pluginId, specs, manifestPath);
		return providerTypes;
	}
}
