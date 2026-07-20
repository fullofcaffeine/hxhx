package reflaxe.ocaml.artifacts;

#if (macro || reflaxe_runtime || eval)
import haxe.Json;
import haxe.crypto.Sha256;

using StringTools;

/**
	Builds a path-free revision for settings that can change generated sources.

	Timing, tracing, output paths, and whether the compiler invokes Dune are
	deliberately absent. Those settings may add volatile evidence or build cache
	files, but must not change the reproducible source-bundle identity.
**/
class OcamlArtifactConfigurationRevision {
	public static inline final MODEL = "reflaxe-ocaml-source-configuration-v1";

	public static final SOURCE_DEFINE_NAMES = [
		"ocaml_atomic_semantics",
		"ocaml_dune_exes",
		"ocaml_dune_layout",
		"ocaml_dune_libraries",
		"ocaml_emit_exclude_packages",
		"ocaml_emit_exclude_paths",
		"ocaml_emit_package_aliases",
		"ocaml_metal_allow_fallback",
		"ocaml_mli",
		"ocaml_mli_best_effort",
		"ocaml_module_prefix",
		"ocaml_no_dune",
		"ocaml_no_line_directives",
		"ocaml_no_runtime",
		"ocaml_plugin_load_marker",
		"ocaml_plugin_mode",
		"ocaml_plugin_register_provider",
		"ocaml_plugin_run_main",
		"ocaml_portable_native_surface",
		"ocaml_profile",
		"ocaml_runtime_debug_lane",
		"ocaml_runtime_mode",
		"ocaml_runtime_modules",
		"ocaml_runtime_no_infer",
		"ocaml_runtime_token_scan_fallback",
		"ocaml_sourcemap",
		"ocaml_strict",
		"reflaxe_ocaml_disable_expression_preprocessors",
		"reflaxe_ocaml_full_type_registry"
	];

	/** Captures the reviewed define set from the active Haxe macro request. **/
	public static function fromMacroContext(targetPipelineRevision:String, outputProjectName:String):String {
		#if macro
		final values:Map<String, String> = [];
		for (name in SOURCE_DEFINE_NAMES) {
			if (!haxe.macro.Context.defined(name))
				continue;
			final value = haxe.macro.Context.definedValue(name);
			values.set(name, value == null ? "1" : value);
		}
		return fromValues(targetPipelineRevision, outputProjectName, values);
		#else
		return fromValues(targetPipelineRevision, outputProjectName, []);
		#end
	}

	/** Computes the same revision from explicit values for tests and host adapters. **/
	public static function fromValues(targetPipelineRevision:String, outputProjectName:String, values:Map<String, String>):String {
		final allowed:Map<String, Bool> = [for (name in SOURCE_DEFINE_NAMES) name => true];
		for (name in values.keys()) {
			if (!allowed.exists(name))
				throw 'Unknown OCaml source-configuration setting "$name".';
		}
		final normalized:Array<Array<String>> = [];
		for (name in SOURCE_DEFINE_NAMES) {
			final raw = values.get(name);
			if (raw == null)
				continue;
			normalized.push([name, normalizeValue(name, raw)]);
		}
		final canonical:Array<Dynamic> = [
			MODEL,
			requireValue(targetPipelineRevision, "target pipeline revision"),
			requireValue(outputProjectName, "output project name"),
			normalized
		];
		return "sha256:" + Sha256.encode(Json.stringify(canonical));
	}

	static function normalizeValue(name:String, value:String):String {
		final trimmed = value == null ? "" : value.trim();
		return switch (name) {
			case "ocaml_profile":
				trimmed.length == 0 ? "portable" : trimmed.toLowerCase();
			case "ocaml_dune_layout":
				trimmed.length == 0 ? "exe" : trimmed.toLowerCase();
			case "ocaml_mli": trimmed.length == 0 || trimmed == "1" ? "infer" : trimmed.toLowerCase();
			case "ocaml_atomic_semantics" | "ocaml_portable_native_surface" | "ocaml_runtime_mode":
				trimmed.toLowerCase();
			case "ocaml_emit_exclude_packages" | "ocaml_emit_exclude_paths" | "ocaml_runtime_modules":
				normalizeSet(trimmed);
			case _:
				trimmed.length == 0 ? "<empty>" : trimmed;
		};
	}

	static function normalizeSet(value:String):String {
		final seen:Map<String, Bool> = [];
		final values = new Array<String>();
		for (part in value.split(",")) {
			final token = part.trim();
			if (token.length == 0 || seen.exists(token))
				continue;
			seen.set(token, true);
			values.push(token);
		}
		values.sort(compareStrings);
		return values.join(",");
	}

	static function requireValue(value:String, label:String):String {
		final trimmed = value == null ? "" : value.trim();
		if (trimmed.length == 0)
			throw 'OCaml artifact $label must not be empty.';
		return trimmed;
	}

	static function compareStrings(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}
}
#end
