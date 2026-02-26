package hxhx;

/**
	OCaml runtime bridge for Stage3 native backend plugin registration capture.

	Why
	- Native `.cmxs` plugins register provider type names as a load-time side effect.
	- Stage3 needs a deterministic seam to:
	  - clear registration state before loading,
	  - receive plugin registration callbacks from OCaml,
	  - read captured registrations after load.

	How
	- Implemented in `packages/reflaxe.ocaml/std/runtime/HxHxBackendPluginHost.ml`.
	- `registerProviderType` is called by native plugin entry modules.
	- Stage3 reads encoded registration rows through `snapshot()` and validates them
	  in `NativeBackendPluginHostAbi`.

	Boundary rule
	- Keep this class as a thin FFI seam only.
	- Typed validation and conflict checks must live in Haxe code.
**/
#if reflaxe_ocaml
@:native("HxHxBackendPluginHost")
private extern class NativeBackendPluginHostRuntime {
	public static function clear():Void;

	@:native("register_provider_type")
	public static function registerProviderType(pluginId:String, providerType:String):Void;

	public static function snapshot():String;
}
#end

class NativeBackendPluginHost {
	#if reflaxe_ocaml
	public static inline function clear():Void {
		NativeBackendPluginHostRuntime.clear();
	}

	public static inline function registerProviderType(pluginId:String, providerType:String):Void {
		NativeBackendPluginHostRuntime.registerProviderType(pluginId, providerType);
	}

	public static inline function snapshot():String {
		return NativeBackendPluginHostRuntime.snapshot();
	}
	#else
	static final fallbackRows = new Array<String>();

	public static function clear():Void {
		fallbackRows.resize(0);
	}

	public static function registerProviderType(pluginId:String, providerType:String):Void {
		final plugin = pluginId == null ? "" : StringTools.trim(pluginId);
		final provider = providerType == null ? "" : StringTools.trim(providerType);
		if (plugin.length == 0 || provider.length == 0)
			throw "NativeBackendPluginHost fallback requires non-empty pluginId/providerType";
		fallbackRows.push(plugin + "\t" + provider);
	}

	public static function snapshot():String {
		return fallbackRows.length == 0 ? "v1\n" : ("v1\n" + fallbackRows.join("\n") + "\n");
	}
	#end
}
