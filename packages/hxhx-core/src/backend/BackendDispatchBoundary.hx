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
**/
class BackendDispatchBoundary {
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
		- Fallback for custom plugin/bundled backends uses the typed `IBackend.emit`
		  interface call (no reflection).
	**/
	public static function emit(backend:IBackend, program:GenIrProgram, context:BackendContext):EmitResult {
		#if reflaxe
		final dispatchValue = asDispatchValue(backend);
		#if !hxhx_stage0_ocaml_only
		if (Std.isOfType(dispatchValue, JsBackend)) {
			final jsBackend = requireJsBackend(dispatchValue);
			return JsBackend.emitBridge(jsBackend, program, context);
		}
		#end
		if (Std.isOfType(dispatchValue, OcamlStage3Backend)) {
			final ocamlBackend = requireOcamlBackend(dispatchValue);
			return OcamlStage3Backend.emitBridge(ocamlBackend, program, context);
		}
		if (Std.isOfType(dispatchValue, TargetCoreBackend)) {
			final targetCoreBackend = requireTargetCoreBackend(dispatchValue);
			return TargetCoreBackend.emitBridge(targetCoreBackend, program, context);
		}
		return emitReflective(dispatchValue, program, context);
		#else
		return backend.emit(program, context);
		#end
	}
}
