package reflaxe.ocaml;

#if (macro || reflaxe_runtime)
import haxe.macro.Context;
#end

/**
	Resolved Stage0 OCaml build context for runtime planning.

	Why:
	- Runtime planning previously re-parsed multiple defines ad hoc.
	- A single resolved context keeps profile/capability policy deterministic and testable.

	What:
	- Resolves the profile contract (`portable|metal`) and runtime planning capabilities.
	- Keeps default behavior unchanged unless explicit runtime capability defines are set.
**/
class OcamlBuildContext {
	public static inline final PROFILE_DEFINE = "ocaml_profile";
	public static inline final METAL_ALLOW_FALLBACK_DEFINE = "ocaml_metal_allow_fallback";
	public static inline final STRICT_DEFINE = "ocaml_strict";
	public static inline final PORTABLE_NATIVE_SURFACE_DEFINE = "ocaml_portable_native_surface";
	public static inline final RUNTIME_MODE_DEFINE = "ocaml_runtime_mode";
	public static inline final RUNTIME_MODULES_DEFINE = "ocaml_runtime_modules";
	public static inline final RUNTIME_NO_INFER_DEFINE = "ocaml_runtime_no_infer";
	public static inline final RUNTIME_TOKEN_SCAN_FALLBACK_DEFINE = "ocaml_runtime_token_scan_fallback";

	public final profile:OcamlProfileContract;
	public final metalFallbackAllowed:Bool;
	public final metalContractHardError:Bool;
	public final strictUserBoundaries:Bool;
	public final portableNativeSurfacePolicy:OcamlPortableNativeSurfacePolicy;
	public final runtimeMode:OcamlRuntimeMode;
	public final runtimeManualModules:Array<String>;
	public final runtimeInferenceDisabled:Bool;
	public final runtimeTokenScanFallbackEnabled:Bool;

	public function new(profile:OcamlProfileContract, metalFallbackAllowed:Bool, strictUserBoundaries:Bool,
			portableNativeSurfacePolicy:OcamlPortableNativeSurfacePolicy, runtimeMode:OcamlRuntimeMode, runtimeManualModules:Array<String>,
			runtimeInferenceDisabled:Bool, runtimeTokenScanFallbackEnabled:Bool) {
		this.profile = profile;
		this.metalFallbackAllowed = metalFallbackAllowed;
		this.metalContractHardError = profile == OcamlProfileContract.Metal && !metalFallbackAllowed;
		this.strictUserBoundaries = strictUserBoundaries;
		this.portableNativeSurfacePolicy = portableNativeSurfacePolicy;
		this.runtimeMode = runtimeMode;
		this.runtimeManualModules = runtimeManualModules == null ? [] : runtimeManualModules.copy();
		this.runtimeInferenceDisabled = runtimeInferenceDisabled;
		this.runtimeTokenScanFallbackEnabled = runtimeTokenScanFallbackEnabled;
	}

	static function defaultRuntimeMode(profile:OcamlProfileContract):OcamlRuntimeMode {
		return profile == OcamlProfileContract.Metal ? OcamlRuntimeMode.Selective : OcamlRuntimeMode.Full;
	}

	static function parseRuntimeModules(raw:Null<String>):Array<String> {
		if (raw == null)
			return [];
		final out:Array<String> = [];
		final seen:Map<String, Bool> = [];
		for (part in raw.split(",")) {
			final token = StringTools.trim(part);
			if (token.length == 0 || seen.exists(token))
				continue;
			seen.set(token, true);
			out.push(token);
		}
		out.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		return out;
	}

	#if (macro || reflaxe_runtime)
	static function resolveProfile(rawProfile:Null<String>):OcamlProfileContract {
		try {
			return OcamlProfileContract.fromDefineValue(rawProfile);
		} catch (e:String) {
			Context.error(e, Context.currentPos());
			return OcamlProfileContract.Portable;
		}
	}

	public static function resolve():OcamlBuildContext {
		final rawProfile = Context.definedValue(PROFILE_DEFINE);
		final profile = resolveProfile(rawProfile);

		final metalFallbackAllowed = Context.defined(METAL_ALLOW_FALLBACK_DEFINE);
		final strictUserBoundaries = Context.defined(STRICT_DEFINE) || (profile == OcamlProfileContract.Metal && !metalFallbackAllowed);
		final portableNativeSurfacePolicy = try {
			OcamlPortableNativeSurfacePolicy.fromDefineValue(Context.definedValue(PORTABLE_NATIVE_SURFACE_DEFINE));
		} catch (e:String) {
			Context.error(e, Context.currentPos());
			OcamlPortableNativeSurfacePolicy.Warn;
		}

		final runtimeModeDefault = defaultRuntimeMode(profile);
		final runtimeMode = try {
			OcamlRuntimeMode.fromDefineValue(Context.definedValue(RUNTIME_MODE_DEFINE), runtimeModeDefault);
		} catch (e:String) {
			Context.error(e, Context.currentPos());
			runtimeModeDefault;
		}

		final runtimeManualModules = parseRuntimeModules(Context.definedValue(RUNTIME_MODULES_DEFINE));
		final runtimeInferenceDisabled = Context.defined(RUNTIME_NO_INFER_DEFINE);
		final tokenScanFallbackRequested = Context.defined(RUNTIME_TOKEN_SCAN_FALLBACK_DEFINE);
		final runtimeTokenScanFallbackEnabled = tokenScanFallbackRequested
			&& runtimeMode == OcamlRuntimeMode.Selective
			&& !runtimeInferenceDisabled;
		if (tokenScanFallbackRequested && !runtimeTokenScanFallbackEnabled) {
			Context.warning("ocaml_runtime_token_scan_fallback ignored unless runtime mode is selective and inference is enabled.", Context.currentPos());
		}

		return new OcamlBuildContext(profile, metalFallbackAllowed, strictUserBoundaries, portableNativeSurfacePolicy, runtimeMode, runtimeManualModules,
			runtimeInferenceDisabled, runtimeTokenScanFallbackEnabled);
	}
	#else
	public static function resolve():OcamlBuildContext {
		return new OcamlBuildContext(OcamlProfileContract.Portable, false, false, OcamlPortableNativeSurfacePolicy.Warn, OcamlRuntimeMode.Full, [], false,
			false);
	}
	#end
}
