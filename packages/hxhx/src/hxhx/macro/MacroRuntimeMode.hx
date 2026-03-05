package hxhx.macro;

/**
	Macro runtime mode selector and factory.

	Supported modes:
	- `external-host`: existing out-of-process macro host RPC model.
	- `inproc`: in-process bring-up runtime (no spawned macro host process).
**/
class MacroRuntimeMode {
	public static inline var EXTERNAL_HOST:String = "external-host";
	public static inline var INPROC:String = "inproc";
	public static inline var DEFAULT:String = INPROC;

	public static function resolve(explicitMode:Null<String>):String {
		final fromFlag = normalize(explicitMode);
		if (fromFlag != null)
			return fromFlag;
		final fromEnv = normalize(Sys.getEnv("HXHX_MACRO_RUNTIME_MODE"));
		return fromEnv == null ? DEFAULT : fromEnv;
	}

	public static function openSession(mode:String):MacroRuntimeSession {
		switch (mode) {
			case INPROC:
				return InProcMacroRuntime.openSession();
			case EXTERNAL_HOST:
				return MacroHostClient.openSession();
			case _:
				throw "invalid macro runtime mode `" + mode + "` (expected inproc|external-host)";
		}
	}

	public static function emitMarker(mode:String):Void {
		Sys.println("hxhx_macro_runtime_mode=" + mode);
	}

	static function normalize(raw:Null<String>):Null<String> {
		if (raw == null)
			return null;
		final trimmed = StringTools.trim(raw);
		if (trimmed.length == 0)
			return null;
		final lower = trimmed.toLowerCase();
		return switch (lower) {
			case INPROC:
				INPROC;
			case EXTERNAL_HOST:
				EXTERNAL_HOST;
			case _:
				throw "invalid macro runtime mode `" + raw + "` (expected inproc|external-host)";
		};
	}
}
