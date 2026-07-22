package hxhx;

import backend.BackendRegistry;
import backend.IBackend;
import backend.TargetDescriptor;
import hxhx.runtime.NullableRuntimeString;

typedef Stage3BackendSelection = {
	final backend:IBackend;
	final descriptor:TargetDescriptor;
	final supportsCustomOutputFile:Bool;
	final supportsBuildExecutable:Bool;
}

/**
	Stage3 backend plugin/provider declaration and registration helpers.

	Why
	- `Stage3Compiler` still owned the parsing and normalization of backend provider
	  declarations from defines and environment variables.
	- That logic is registry support glue, not compile orchestration.

	What
	- Parses provider and manifest declarations from defines and env vars.
	- Normalizes plugin load requests across bundled and explicit sources.
	- Shapes the define list passed into backend provider discovery.
	- Loads the resulting dynamic registrations into `BackendRegistry`.
	- Resolves the selected backend implementation and capability flags.

	How
	- Keep the current source precedence and tracing behavior intact.
	- Restrict the helper surface to the one entrypoint `Stage3Compiler` already needs.
**/
class Stage3BackendPluginSupport {
	static inline function trim(value:String):String {
		return NullableRuntimeString.trimToEmpty(value);
	}

	static function isTrueEnv(name:String):Bool {
		final value = trim(Sys.getEnv(name));
		return value == "1" || value == "true" || value == "yes";
	}

	static function parseDelimitedList(raw:String):Array<String> {
		final out = new Array<String>();
		final normalized = NullableRuntimeString.normalize(raw);
		if (normalized == null)
			return out;
		final value = StringTools.trim(normalized);
		if (value.length == 0)
			return out;

		final parts = value.indexOf(";") != -1 ? value.split(";") : value.split(",");
		for (part in parts) {
			if (part == null)
				continue;
			final trimmed = StringTools.trim(part);
			if (trimmed.length == 0)
				continue;
			if (out.indexOf(trimmed) == -1)
				out.push(trimmed);
		}
		return out;
	}

	static function collectDeclarationValues(rawDefines:Array<String>, envName:String, defineNames:Array<String>):Array<String> {
		final out = parseDelimitedList(Sys.getEnv(envName));
		if (rawDefines == null || defineNames == null || defineNames.length == 0)
			return out;

		inline function pushUnique(values:Array<String>):Void {
			for (value in values)
				if (out.indexOf(value) == -1)
					out.push(value);
		}

		for (raw in rawDefines) {
			final define = trim(raw);
			if (define.length == 0)
				continue;
			final eq = define.indexOf("=");
			if (eq == -1 || eq + 1 >= define.length)
				continue;
			final name = trim(define.substr(0, eq));
			if (defineNames.indexOf(name) == -1)
				continue;
			pushUnique(parseDelimitedList(define.substr(eq + 1)));
		}

		return out;
	}

	static function collectExplicitBackendProviderTypeNames(rawDefines:Array<String>):Array<String> {
		return collectDeclarationValues(rawDefines, "HXHX_BACKEND_PROVIDERS", ["hxhx_backend_provider", "hxhx_backend_providers", "hxhx.backend.provider"]);
	}

	static function collectBundledBackendProviderTypeNames(rawDefines:Array<String>):Array<String> {
		return collectDeclarationValues(rawDefines, "HXHX_BACKEND_BUNDLED_PROVIDERS", [
			"hxhx_backend_bundled_provider",
			"hxhx_backend_bundled_providers",
			"hxhx.backend.bundled.provider"
		]);
	}

	static function collectExplicitBackendPluginManifestPaths(rawDefines:Array<String>):Array<String> {
		return collectDeclarationValues(rawDefines, "HXHX_BACKEND_PLUGIN_MANIFESTS", [
			"hxhx_backend_plugin_manifest",
			"hxhx_backend_plugin_manifests",
			"hxhx.backend.plugin.manifest"
		]);
	}

	static function collectBundledBackendPluginManifestPaths(rawDefines:Array<String>):Array<String> {
		return collectDeclarationValues(rawDefines, "HXHX_BACKEND_BUNDLED_PLUGIN_MANIFESTS", [
			"hxhx_backend_bundled_plugin_manifest",
			"hxhx_backend_bundled_plugin_manifests",
			"hxhx.backend.bundled.plugin.manifest"
		]);
	}

	static function appendPluginLoadRequest(out:Array<BackendPluginLoadRequest>, source:BackendPluginSource, providerType:String, origin:String):Void {
		final normalizedProvider = trim(providerType);
		if (normalizedProvider.length == 0)
			return;
		final normalizedOrigin = trim(origin);
		for (existing in out) {
			if (existing.source == source && existing.providerType == normalizedProvider)
				return;
		}
		out.push({
			source: source,
			providerType: normalizedProvider,
			origin: normalizedOrigin.length == 0 ? normalizedProvider : normalizedOrigin
		});
	}

	static function appendProviderRequests(out:Array<BackendPluginLoadRequest>, source:BackendPluginSource, providerTypes:Array<String>,
			originPrefix:String):Void {
		for (providerType in providerTypes)
			appendPluginLoadRequest(out, source, providerType, originPrefix + ":" + providerType);
	}

	static function appendManifestRequests(out:Array<BackendPluginLoadRequest>, source:BackendPluginSource, manifestPaths:Array<String>, trace:Bool,
			output:Null<CompilationRequestOutput>):Void {
		for (manifestPath in manifestPaths) {
			final providers = BackendPluginManifestResolver.providerTypeNamesForManifestPath(manifestPath);
			for (providerType in providers)
				appendPluginLoadRequest(out, source, providerType, "manifest:" + manifestPath);
			if (trace)
				CompilationRequestOutput.writeStdoutLine(output, "backend_plugin_manifest[" + source + "][" + manifestPath + "]=" + providers.length);
		}
	}

	/**
		Load request-scoped dynamic backend providers into the canonical Stage3 registry.

		Source precedence
		- `explicit` providers/manifests override `bundled` providers/manifests.
		- plugin sources override builtin registrations through source priority bands.
	**/
	public static function loadDynamicBackendProviders(rawDefines:Array<String>, ?output:CompilationRequestOutput):Void {
		BackendRegistry.clearDynamicRegistrations();
		final trace = isTrueEnv("HXHX_TRACE_BACKEND_PROVIDERS");
		final requests = new Array<BackendPluginLoadRequest>();

		appendProviderRequests(requests, BackendPluginSource.Bundled, collectBundledBackendProviderTypeNames(rawDefines), "bundled-provider");
		appendManifestRequests(requests, BackendPluginSource.Bundled, collectBundledBackendPluginManifestPaths(rawDefines), trace, output);
		appendProviderRequests(requests, BackendPluginSource.Explicit, collectExplicitBackendProviderTypeNames(rawDefines), "explicit-provider");
		appendManifestRequests(requests, BackendPluginSource.Explicit, collectExplicitBackendPluginManifestPaths(rawDefines), trace, output);

		if (requests.length == 0)
			return;

		final registrations = BackendPluginLoader.registrationsForRequests(requests);
		final registered = BackendRegistry.registerProvider(registrations);
		if (trace) {
			CompilationRequestOutput.writeStdoutLine(output, "backend_provider_requests=" + requests.length);
			CompilationRequestOutput.writeStdoutLine(output, "backend_provider_total=" + registered);
		}
	}

	public static function buildProviderDefines(allDefines:Array<String>):Array<String> {
		final providerDefines = allDefines.copy();
		for (name in hxhx.macro.MacroState.listDefineNames()) {
			final value = hxhx.macro.MacroState.definedValue(name);
			if (value == null || value.length == 0 || value == "1") {
				providerDefines.push(name);
			} else {
				providerDefines.push(name + "=" + value);
			}
		}
		return providerDefines;
	}

	public static function selectBackend(backendId:String, providerDefines:Array<String>, ?output:CompilationRequestOutput):Stage3BackendSelection {
		try {
			if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
				CompilationRequestOutput.writeStdoutLine(output, "stage3_driver=before_load_dynamic_backend_providers");
			}
			loadDynamicBackendProviders(providerDefines, output);
			if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
				CompilationRequestOutput.writeStdoutLine(output, "stage3_driver=after_load_dynamic_backend_providers");
			}
		} catch (e:String) {
			throw "backend provider setup failed: " + e;
		}

		final backend = try {
			if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
				CompilationRequestOutput.writeStdoutLine(output, "stage3_driver=before_resolve_builtin_backend id=" + backendId);
			}
			BackendRegistry.requireForTarget(backendId);
		} catch (e:String) {
			throw "backend setup failed: " + e;
		}
		if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
			CompilationRequestOutput.writeStdoutLine(output, "stage3_driver=after_resolve_builtin_backend");
		}

		final selected = BackendRegistry.descriptorForTarget(backendId);
		if (isTrueEnv("HXHX_TRACE_BACKEND_SELECTION")) {
			if (selected == null) {
				CompilationRequestOutput.writeStdoutLine(output, "backend_selected_impl=<unknown>");
			} else {
				CompilationRequestOutput.writeStdoutLine(output, "backend_selected_impl=" + selected.implId);
			}
		}
		if (selected == null)
			throw "backend descriptor not found after selection: " + backendId;

		final backendCaps = selected.capabilities;
		return {
			backend: backend,
			descriptor: selected,
			supportsCustomOutputFile: backendCaps.supportsCustomOutputFile == true,
			supportsBuildExecutable: backendCaps.supportsBuildExecutable == true
		};
	}
}
