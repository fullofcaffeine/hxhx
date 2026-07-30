package reflaxe.ocaml.artifacts;

#if (macro || reflaxe_runtime || eval)
import haxe.Json;
import haxe.crypto.Sha256;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestModel.OcamlArtifactAuthority;
import reflaxe.ocaml.artifacts.OcamlArtifactManifestSchema;
import reflaxe.ocaml.runtimegen.RuntimeSourceManifestModel.RuntimeSourceManifestSnapshot;
import reflaxe.ocaml.runtimegen.RuntimeSourceManifestModel.RuntimeSourceModule;

/** Plain generated-Dune inputs that participate in source replay identity. **/
typedef OcamlNativeSourceDeclaration = {
	final projectName:String;
	final exeName:String;
	final mainModuleId:Null<String>;
	final pluginMainModuleId:Null<String>;
	final pluginRegisterPluginId:Null<String>;
	final pluginRegisterProviderType:Null<String>;
	final pluginLoadMarker:Null<String>;
	final duneLibraries:Array<String>;
	final duneLayout:Null<String>;
	final executables:Null<Array<{name:String, mainModuleId:Null<String>}>>;
}

/**
	Builds complete authorities for replaying generated OCaml source.

	These authorities cover inputs that can change generated files. They do not
	cache or certify Dune products, installed OCaml package contents, native
	binaries, or the OCaml toolchain; those remain fresh build inputs after source
	publication.
**/
class OcamlSourceBundleAuthority {
	public static inline final SEMANTIC_RUNTIME_MODEL = "checked-runtime-source-selection-v1";
	public static inline final NATIVE_DECLARATION_MODEL = "normalized-native-source-declarations-v1";

	/**
		Builds the early native-source input revision used before Dune text exists.

		The final-program fingerprint owns main/declaration facts, while the source
		configuration revision owns every reviewed Dune/entrypoint define and project
		name. The final generated authority remains a separate postcondition.
	**/
	public static function nativeInputRevision(sourceConfigurationRevision:String):String {
		return "sha256:" + Sha256.encode(Json.stringify([
			NATIVE_DECLARATION_MODEL,
			requiredRevision(sourceConfigurationRevision, "source configuration")
		]));
	}

	/**
		Owns the checked runtime catalog and the exact selected closure.

		The runtime source manifest verifies every repository-owned source file
		before selection. Selected file digests are also recorded separately in
		the artifact manifest, so this revision owns why that exact closure was
		chosen rather than duplicating its bytes.
	**/
	public static function semanticRuntime(sourceManifest:RuntimeSourceManifestSnapshot, requirementRevision:String, profile:String, runtimeMode:String,
			selectionMode:String, allowTooling:Bool, selectedEntries:Array<RuntimeSourceModule>):OcamlArtifactAuthority {
		final selected:Array<Dynamic> = [
			for (entry in selectedEntries) [
				entry.module,
				entry.dependencies.copy(),
				entry.duneLibraries.copy(),
				[for (file in entry.files) [file.path, file.sha256, file.bytes]]
			]
		];
		return complete(SEMANTIC_RUNTIME_MODEL, [
			requiredRevision(sourceManifest.revision, "runtime source manifest"),
			requiredRevision(requirementRevision, "runtime requirement"),
			required(profile, "runtime profile"),
			required(runtimeMode, "runtime mode"),
			required(selectionMode, "runtime selection mode"),
			allowTooling,
			selected
		],
			"Every packaged runtime source is manifest-checked, and the selected runtime closure is revisioned for source replay.");
	}

	/** Records that the request intentionally emits no packaged runtime source. **/
	public static function semanticRuntimeDisabled():OcamlArtifactAuthority {
		return complete(SEMANTIC_RUNTIME_MODEL, ["disabled"],
			"The request disables packaged runtime source, so the empty runtime selection is complete for source replay.");
	}

	/**
		Owns declarations that determine generated Dune and entrypoint files.

		Library names and source-unit declarations are preserved in emission order
		because order can affect generated text. Installed package contents and
		toolchain identity are deliberately outside this source-replay authority
		and are checked by the fresh Dune build.
	**/
	public static function nativeDeclarations(config:OcamlNativeSourceDeclaration):OcamlArtifactAuthority {
		final executables:Null<Array<Dynamic>> = config.executables == null ? null : [
			for (entry in config.executables) [required(entry.name, "Dune executable name"), optional(entry.mainModuleId)]
		];
		return complete(NATIVE_DECLARATION_MODEL, [
			required(config.projectName, "Dune project name"),
			required(config.exeName, "Dune executable name"),
			optional(config.mainModuleId),
			optional(config.pluginMainModuleId),
			optional(config.pluginRegisterPluginId),
			optional(config.pluginRegisterProviderType),
			optional(config.pluginLoadMarker),
			normalizedOrderedValues(config.duneLibraries, "Dune library"),
			optional(config.duneLayout),
			executables
		],
			"Every declaration that changes generated Dune or entrypoint source is revisioned; external packages and build products remain fresh Dune inputs.");
	}

	/** Records that the request intentionally emits no Dune or entrypoint files. **/
	public static function nativeDeclarationsDisabled():OcamlArtifactAuthority {
		return complete(NATIVE_DECLARATION_MODEL, ["disabled"],
			"The request disables generated Dune scaffolding, so the empty native source declaration is complete for source replay.");
	}

	static function complete(model:String, values:Array<Dynamic>, message:String):OcamlArtifactAuthority {
		return {
			status: OcamlArtifactManifestSchema.AUTHORITY_COMPLETE,
			model: model,
			revision: "sha256:" + Sha256.encode(Json.stringify([model, values])),
			message: message
		};
	}

	static function normalizedOrderedValues(values:Array<String>, label:String):Array<String> {
		if (values == null)
			return [];
		return [for (value in values) required(value, label)];
	}

	static function optional(value:Null<String>):String {
		return value == null ? "" : StringTools.trim(value);
	}

	static function requiredRevision(value:String, label:String):String {
		return OcamlArtifactManifestSchema.normalizeRevision(value, label + " revision");
	}

	static function required(value:String, label:String):String {
		final normalized = value == null ? "" : StringTools.trim(value);
		if (normalized.length == 0)
			throw 'OCaml source-bundle $label must not be empty.';
		return normalized;
	}
}
#end
