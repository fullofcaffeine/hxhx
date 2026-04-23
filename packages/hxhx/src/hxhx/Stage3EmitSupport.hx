package hxhx;

import backend.BackendContext;
import backend.BackendDispatchBoundary;
import backend.EmitResult;
import backend.GenIrBoundary;
import backend.IBackend;
import haxe.io.Path;

/**
	Stage3 backend emission dispatch helpers.

	Why
	- `Stage3Compiler` should decide when to emit, but the details of output hint
	  normalization, backend context construction, and ABI boundary dispatch are
	  backend execution plumbing.

	What
	- Normalizes target output file/directory hints.
	- Builds the `BackendContext` consumed by target backends.
	- Converts the expanded program through the GenIR boundary and dispatches to
	  the selected backend.

	How
	- Preserve the existing Stage3 trace markers and output path behavior.
	- Let callers keep ownership of macro-session cleanup and user-facing error
	  prefixes by throwing through backend failures unchanged.
**/
class Stage3EmitSupport {
	static function bool01(v:Bool):String {
		return v ? "1" : "0";
	}

	static function isTrueEnv(name:String):Bool {
		final value = hxhx.runtime.NullableRuntimeString.trimToEmpty(Sys.getEnv(name));
		return value == "1" || value == "true" || value == "yes";
	}

	public static function emitWithBackend(backend:IBackend, expanded:MacroExpandedProgram, backendId:String, typedModuleCount:Int, cwd:String, outAbs:String,
			targetOutputHintRaw:Null<String>, targetOutputDirHintRaw:Null<String>, parsedMain:Null<String>, emitFullBodies:Bool,
			supportsCustomOutputFile:Bool, supportsBuildExecutable:Bool, definesMap:haxe.ds.StringMap<String>):EmitResult {
		if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
			Sys.println("stage3_driver=before_output_file_hint");
		}
		final outputFileHint = if (supportsCustomOutputFile && targetOutputHintRaw != null && targetOutputHintRaw.length > 0) {
			Path.isAbsolute(targetOutputHintRaw) ? Path.normalize(targetOutputHintRaw) : Stage3PathSupport.absFromCwd(cwd, targetOutputHintRaw);
		} else {
			null;
		}
		if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
			Sys.println("stage3_driver=after_output_file_hint");
			Sys.println("stage3_driver=before_backend_context");
		}
		final outputDirAbs = if (targetOutputDirHintRaw != null && targetOutputDirHintRaw.length > 0) {
			Path.isAbsolute(targetOutputDirHintRaw) ? Path.normalize(targetOutputDirHintRaw) : Stage3PathSupport.absFromCwd(cwd, targetOutputDirHintRaw);
		} else {
			outAbs;
		}
		final context = new BackendContext(outputDirAbs, outputFileHint, parsedMain, emitFullBodies, supportsBuildExecutable, definesMap);
		if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
			Sys.println("stage3_driver=after_backend_context");
			Sys.println("stage3_driver=before_emit_trace_backend_id");
		}
		if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
			Sys.println("stage3_driver=after_emit_trace_backend_id");
			Sys.println("stage3_driver=before_emit backend=" + backendId + " typed_modules=" + typedModuleCount + " out=" + outputDirAbs);
		}
		if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
			Sys.println("stage3_driver=emitWithBackend_before_genir_boundary");
		}
		final expandedProgram = GenIrBoundary.fromDynamic(cast expanded);
		if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
			Sys.println("stage3_driver=emitWithBackend_after_genir_boundary");
			Sys.println("stage3_driver=emitWithBackend_before_dispatch_boundary");
		}
		final emitted = BackendDispatchBoundary.emit(backend, expandedProgram, context);
		if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
			Sys.println("stage3_driver=emitWithBackend_after_dispatch_boundary");
		}
		if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
			Sys.println("stage3_driver=after_emit entry=" + emitted.entryPath + " built_executable=" + bool01(emitted.builtExecutable));
		}
		return emitted;
	}
}
