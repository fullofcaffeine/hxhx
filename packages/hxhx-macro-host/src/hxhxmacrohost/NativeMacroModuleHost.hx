package hxhxmacrohost;

/**
	OCaml runtime bridge for native macro-module registration state.

	Why
	- Native macro modules register macro expression handlers as load-time side
	  effects.
	- The macro host needs a deterministic boundary to:
	  - clear state before each dynlink activation,
	  - capture registration snapshot rows for typed validation,
	  - run registered expression handlers by exact key.

	How
	- Implemented in `packages/reflaxe.ocaml/std/runtime/HxHxMacroModuleHost.ml`.
	- Typed decoding/validation is owned by `NativeMacroModuleHostAbi`.
**/
@:native("HxHxMacroModuleHost")
private extern class NativeMacroModuleHostRuntime {
	public static function clear():Void;
	public static function snapshot():String;

	@:native("run_expr")
	public static function runExpr(expr:String):String;
}

class NativeMacroModuleHost {
	public static inline function clear():Void {
		NativeMacroModuleHostRuntime.clear();
	}

	public static inline function snapshot():String {
		return NativeMacroModuleHostRuntime.snapshot();
	}

	public static inline function runExpr(expr:String):String {
		return NativeMacroModuleHostRuntime.runExpr(expr);
	}
}
