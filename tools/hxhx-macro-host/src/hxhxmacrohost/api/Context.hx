package hxhxmacrohost.api;

import hxhxmacrohost.HostToCompilerRpc;
import hxhxmacrohost.MacroRuntime;
import hxhxmacrohost.Protocol;

/**
	Minimal “Context-like” API surface for Stage 4 macro bring-up.

	Why
	- Real-world macro libraries rely heavily on `haxe.macro.Context.*`.
	- For the first non-stage0 rung, we want to demonstrate that:
	  - macro code can call into a Context-like API,
	  - the API can query compiler/macro-host state,
	  - and we can return deterministic results over RPC.

	What
	- `defined(name)` / `definedValue(name)` query the compiler’s define store (reverse RPC).
	- `getType(name)` is a deliberately small allowlist-backed lookup used to prove the request path.

	How
	- Backed by the compiler define store for `defined*` and `MacroRuntime.builtinTypes` for `getType`.
	- Later stages will replace the allowlist with real typed representations and a macro<->compiler ABI.
**/
class Context {
	public static function defined(name:String):Bool {
		if (name == null) return false;
		final v = HostToCompilerRpc.call("context.defined", Protocol.encodeLen("n", name));
		return v == "1";
	}

	public static function definedValue(name:String):String {
		if (name == null) return "";
		return HostToCompilerRpc.call("context.definedValue", Protocol.encodeLen("n", name));
	}

	public static function getType(name:String):String {
		if (name == null || name.length == 0) return "missing";
		return MacroRuntime.builtinTypeDesc(name);
	}
}
