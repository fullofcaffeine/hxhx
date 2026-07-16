package backend;

#if !hxhx_stage0_ocaml_only
import backend.js.JsBackend;
#end
import backend.ocaml.OcamlStage3Backend;

/**
	Centralized backend-dispatch boundary recovery helpers.

	Why
	- Reflaxe-generated OCaml can lose concrete backend type information when values flow through
	  interface-typed dispatch seams (`IBackend`).
	- Stage3 needs to recover concrete backend types only at this one seam so bridge calls stay
	  type-safe and backend internals remain strongly typed.

	Policy
	- Keep backend recovery casts in this class only.
	- Do not spread backend `Dynamic`/`cast` recovery through Stage3 compiler logic.
	- `Stage3EmitSupport` is the only production caller of this boundary.
	- See `docs/00-project/BOOTSTRAP_BRIDGE_RETIREMENT.md` for the proof required
	  before removing or expanding it.
**/
class BackendDispatchBoundary {
	static inline function traceEnabled():Bool {
		final raw = Sys.getEnv("HXHX_TRACE_STAGE3_DRIVER");
		if (raw == null)
			return false;
		final s = StringTools.trim(raw).toLowerCase();
		return s == "1" || s == "true" || s == "yes" || s == "on";
	}

	/**
		Expose an interface-typed backend as a runtime dispatch value.
	**/
	public static inline function asDispatchValue(backend:IBackend):Dynamic {
		return cast backend;
	}

	/**
		Recover `JsBackend` at the dispatch seam.
	**/
	#if !hxhx_stage0_ocaml_only
	public static inline function requireJsBackend(value:Dynamic):JsBackend {
		return cast value;
	}
	#end

	/**
		Recover `OcamlStage3Backend` at the dispatch seam.
	**/
	public static inline function requireOcamlBackend(value:Dynamic):OcamlStage3Backend {
		return cast value;
	}

	/**
		Recover `TargetCoreBackend` at the dispatch seam.
	**/
	public static inline function requireTargetCoreBackend(value:Dynamic):TargetCoreBackend {
		return cast value;
	}

	/**
		Reflective fallback for backend wrappers not known at compile time.

		Why
		- Reflaxe-generated OCaml can erase interface method tables for `IBackend`, so direct
		  interface dispatch is not always representable at this boundary.
		- Dynamic/plugin backends still need one escape hatch that does not hardcode every
		  concrete backend class in the core.

		How
		- Resolve `emit` reflectively from the runtime backend value and call it with the
		  standard `(program, context)` payload.
		- Keep this reflection confined to this boundary class.

		Exit
		- Remove this fallback only after a real native plugin and a builtin backend both
		  preserve typed `IBackend.emit` dispatch and pass the focused/plugin gates.
	**/
	public static function emitReflective(backend:Dynamic, program:GenIrProgram, context:BackendContext):EmitResult {
		final emitFn:Dynamic = Reflect.field(backend, "emit");
		if (emitFn == null)
			throw "stage3 backend dispatch: missing emit method on backend runtime value";
		return cast Reflect.callMethod(backend, emitFn, [program, context]);
	}

	/**
		Typed backend emit dispatch bridge.

		Why
		- Stage3 currently compiles through a bootstrap lane where interface-typed values
		  can lose concrete type information in generated OCaml.
		- Builtin backends have static bridge entrypoints that keep this boundary explicit.

		How
		- Fast-path known backend wrappers (`JsBackend`, `OcamlStage3Backend`,
		  `TargetCoreBackend`) through typed static bridges.
		- In Reflaxe-generated native output, custom plugin/bundled backends use the one
		  reflective fallback documented above. Other Haxe targets call `IBackend.emit`
		  directly.
	**/
	public static function emit(backend:IBackend, program:GenIrProgram, context:BackendContext):EmitResult {
		// A post-typing hook may have retained and changed a parsed declaration.
		// Recheck the shared semantic revision once here so every builtin and plugin
		// backend receives the same sealed typed bodies.
		program.assertTypedBodyRevisionsCurrent();
		#if reflaxe
		if (traceEnabled())
			Sys.println("stage3_driver=dispatch_before_asDispatchValue");
		final dispatchValue = asDispatchValue(backend);
		if (traceEnabled())
			Sys.println("stage3_driver=dispatch_after_asDispatchValue");
		#if !hxhx_stage0_ocaml_only
		if (Std.isOfType(dispatchValue, JsBackend)) {
			if (traceEnabled())
				Sys.println("stage3_driver=dispatch_branch_js");
			final jsBackend = requireJsBackend(dispatchValue);
			return JsBackend.emitBridge(jsBackend, program, context);
		}
		#end
		if (Std.isOfType(dispatchValue, OcamlStage3Backend)) {
			if (traceEnabled())
				Sys.println("stage3_driver=dispatch_branch_ocaml");
			final ocamlBackend = requireOcamlBackend(dispatchValue);
			return OcamlStage3Backend.emitBridge(ocamlBackend, program, context);
		}
		if (Std.isOfType(dispatchValue, TargetCoreBackend)) {
			if (traceEnabled())
				Sys.println("stage3_driver=dispatch_branch_target_core");
			final targetCoreBackend = requireTargetCoreBackend(dispatchValue);
			return TargetCoreBackend.emitBridge(targetCoreBackend, program, context);
		}
		if (traceEnabled())
			Sys.println("stage3_driver=dispatch_branch_reflective");
		return emitReflective(dispatchValue, program, context);
		#else
		return backend.emit(program, context);
		#end
	}
}
