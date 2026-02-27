package hxhxmacrohost;

/**
	OCaml Dynlink bridge for native macro-module loading.

	Why
	- Stage 4 Model-A runs macros out-of-process; dynlinked native modules are a
	  fast-path for promoted macro entrypoints.
	- Loading is an OCaml runtime concern and must stay isolated behind one seam.

	What
	- `loadAndCapture(modulePath, pluginId)`:
	  - clears runtime registration state,
	  - loads native module artifact via Dynlink,
	  - returns encoded registration snapshot.
**/
@:native("HxHxMacroModuleDynlink")
private extern class NativeMacroModuleDynlinkRuntime {
	@:native("load_and_capture_safe")
	public static function loadAndCapture(modulePath:String, pluginId:String):String;
}

class NativeMacroModuleDynlink {
	public static inline function loadAndCapture(modulePath:String, pluginId:String):String {
		final response = NativeMacroModuleDynlinkRuntime.loadAndCapture(modulePath, pluginId);
		if (response == null)
			throw "native macro module loader returned no response";
		if (StringTools.startsWith(response, "ok\n"))
			return response.substr(3);
		if (StringTools.startsWith(response, "err\n"))
			throw response.substr(4);
		throw "native macro module loader returned malformed response";
	}
}
