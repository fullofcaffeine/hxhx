package hxhx;

import backend.BackendContext;
import backend.BackendDispatchBoundary;
import backend.EmitResult;
import backend.GenIrBoundary;
import backend.IBackend;

/**
	Stage3 backend emission dispatch helpers.

	Why
	- `Stage3Compiler` should decide when to emit, but the details of backend
	  context construction and ABI boundary dispatch are
	  backend execution plumbing.

	What
	- Builds the `BackendContext` consumed by target backends.
	- Converts the expanded program through the GenIR boundary and dispatches to
	  the selected backend.

	How
	- Receive already-resolved working paths so direct commands can write normally
	  and server requests can use request-owned staging without backend knowledge.
	- Keep private staging paths out of trace output.
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

	public static function emitWithBackend(backend:IBackend, expanded:MacroExpandedProgram, backendId:String, typedModuleCount:Int, outputDirAbs:String,
			outputFileHint:Null<String>, reportedOutputDir:String, parsedMain:Null<String>, emitFullBodies:Bool, supportsCustomOutputFile:Bool,
			supportsBuildExecutable:Bool, definesMap:haxe.ds.StringMap<String>, resources:Array<backend.BackendResource>, ?nativeLibraryPaths:Array<String>,
			?output:CompilationRequestOutput):EmitResult {
		if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
			CompilationRequestOutput.writeStdoutLine(output, "stage3_driver=before_output_file_hint");
		}
		final admittedOutputFileHint = supportsCustomOutputFile ? outputFileHint : null;
		if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
			CompilationRequestOutput.writeStdoutLine(output, "stage3_driver=after_output_file_hint");
			CompilationRequestOutput.writeStdoutLine(output, "stage3_driver=before_backend_context");
		}
		final context = new BackendContext(outputDirAbs, admittedOutputFileHint, parsedMain, emitFullBodies, supportsBuildExecutable, definesMap, resources,
			nativeLibraryPaths);
		if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
			CompilationRequestOutput.writeStdoutLine(output, "stage3_driver=after_backend_context");
			CompilationRequestOutput.writeStdoutLine(output, "stage3_driver=before_emit_trace_backend_id");
		}
		if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
			CompilationRequestOutput.writeStdoutLine(output, "stage3_driver=after_emit_trace_backend_id");
			CompilationRequestOutput.writeStdoutLine(output,
				"stage3_driver=before_emit backend="
				+ backendId
				+ " typed_modules="
				+ typedModuleCount
				+ " out="
				+ reportedOutputDir);
		}
		if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
			CompilationRequestOutput.writeStdoutLine(output, "stage3_driver=emitWithBackend_before_genir_boundary");
		}
		final expandedProgram = GenIrBoundary.fromDynamic(cast expanded);
		if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
			CompilationRequestOutput.writeStdoutLine(output, "stage3_driver=emitWithBackend_after_genir_boundary");
			CompilationRequestOutput.writeStdoutLine(output, "stage3_driver=emitWithBackend_before_dispatch_boundary");
		}
		final emitted = BackendDispatchBoundary.emit(backend, expandedProgram, context);
		if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
			CompilationRequestOutput.writeStdoutLine(output, "stage3_driver=emitWithBackend_after_dispatch_boundary");
		}
		if (isTrueEnv("HXHX_TRACE_STAGE3_DRIVER")) {
			CompilationRequestOutput.writeStdoutLine(output,
				"stage3_driver=after_emit artifacts="
				+ emitted.artifacts.length
				+ " built_executable="
				+ bool01(emitted.builtExecutable));
		}
		return emitted;
	}
}
