package hxhx;

/**
	OCaml Dynlink bridge for Stage3 native backend plugin loading.

	Why
	- Stage3 manifest support includes `backend.kind = "ocaml-cmxs"`.
	- Activating that kind requires OCaml runtime loading (`Dynlink.loadfile`) and
	  deterministic registration capture.

	What
	- `loadAndCapture(manifestPath, entryPath, pluginId)`:
	  - resolves relative plugin entry paths against the manifest directory,
	  - clears host registration capture,
	  - loads the `.cmxs` artifact,
	  - returns encoded registration snapshot.

	Boundary rule
	- This class is a runtime seam only.
	- Typed decoding/validation must happen in `NativeBackendPluginHostAbi`.
**/
#if reflaxe_ocaml
@:native("HxHxBackendPluginDynlink")
private extern class NativeBackendPluginDynlinkRuntime {
	@:native("load_and_capture")
	public static function loadAndCapture(manifestPath:String, entryPath:String, pluginId:String):String;
}
#end

class NativeBackendPluginDynlink {
	#if reflaxe_ocaml
	public static inline function loadAndCapture(manifestPath:String, entryPath:String, pluginId:String):String {
		return NativeBackendPluginDynlinkRuntime.loadAndCapture(manifestPath, entryPath, pluginId);
	}
	#else
	public static function loadAndCapture(manifestPath:String, entryPath:String, pluginId:String):String {
		throw "native `.cmxs` loading requires an OCaml runtime build of hxhx";
	}
	#end
}
