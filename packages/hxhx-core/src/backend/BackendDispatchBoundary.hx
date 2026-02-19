package backend;

import backend.js.JsBackend;
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
	public static inline function requireJsBackend(value:Dynamic):JsBackend {
		return cast value;
	}

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
}
