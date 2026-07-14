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
#if ocaml
@:native("HxHxMacroModuleHost")
private extern class NativeMacroModuleHostRuntime {
	public static function clear():Void;
	public static function snapshot():String;

	@:native("run_expr")
	public static function runExpr(expr:String):String;
}
#end

class NativeMacroModuleHost {
	public static function clear():Void {
		#if !ocaml
		throw "native macro module state requires an OCaml-native hxhx artifact";
		#else
		NativeMacroModuleHostRuntime.clear();
		#end
	}

	public static function snapshot():String {
		#if !ocaml
		throw "native macro module state requires an OCaml-native hxhx artifact";
		#else
		return NativeMacroModuleHostRuntime.snapshot();
		#end
	}

	public static function runExpr(expr:String):String {
		#if !ocaml
		throw "native macro module execution requires an OCaml-native hxhx artifact";
		#else
		return NativeMacroModuleHostRuntime.runExpr(expr);
		#end
	}
}
