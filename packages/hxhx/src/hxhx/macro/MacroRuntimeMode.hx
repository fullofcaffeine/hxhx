package hxhx.macro;

#if !hxhx_stage0_no_external_macro_host
import hxhx.macro.MacroHostClient;
#end

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
				#if hxhx_stage0_no_external_macro_host
				throw "invalid macro runtime mode `" + mode + "` (external-host disabled in stage0 profiling lane; expected inproc)";
				#else
				return MacroHostClient.openSession();
				#end
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
				#if hxhx_stage0_no_external_macro_host
				throw "invalid macro runtime mode `" + raw + "` (external-host disabled in stage0 profiling lane; expected inproc)";
				#else
				EXTERNAL_HOST;
				#end
			case _:
				throw "invalid macro runtime mode `" + raw + "` (expected inproc|external-host)";
		};
	}
}
