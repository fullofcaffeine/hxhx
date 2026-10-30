package hxhxmacrohost;

/**
	OCaml runtime bridge for native macro-module registration state.

	Why
	- Native macro modules register one callback per project macro declaration as a load-time
	  side effect.
	- The compiler needs a deterministic boundary to:
	  - clear state before each dynlink activation,
	  - capture registration snapshot rows for typed validation,
	  - call the registered declaration with an encoded argument payload.

	How
	- Implemented in `packages/reflaxe.ocaml/std/runtime/HxHxMacroModuleHost.ml`.
	- Typed decoding/validation is owned by `NativeMacroModuleHostAbi`; payloads are produced and
	  read only by `MacroSyntaxWire`. The native side passes them through unchanged.
**/
#if ocaml
@:native("HxHxMacroModuleHost")
private extern class NativeMacroModuleHostRuntime {
	public static function clear():Void;
	public static function snapshot():String;

	@:native("run_declaration")
	public static function runDeclaration(declaration:String, payload:String):String;
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

	/**
		Call the callback registered for `declaration` (`pack.Type.method`) with an encoded
		argument payload and return its encoded response. A missing registration or a native
		exception raised by the callback is thrown as a String.
	**/
	public static function runDeclaration(declaration:String, payload:String):String {
		#if !ocaml
		throw "native macro module execution requires an OCaml-native hxhx artifact";
		#else
		final response = NativeMacroModuleHostRuntime.runDeclaration(declaration, payload);
		if (response == null)
			throw "native macro module host returned no response";
		if (StringTools.startsWith(response, "ok\n"))
			return response.substr(3);
		if (StringTools.startsWith(response, "err\n"))
			throw response.substr(4);
		throw "native macro module host returned a malformed response";
		#end
	}
}
