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

	/**
		Return a snapshot of all compiler defines.

		Why
		- Real macro libraries commonly enumerate defines to enable/disable features.
		- This is a cheap bring-up rung that unlocks a lot of upstream-ish macro patterns.

		What
		- Returns a `Map<String,String>` that contains all known defines at the time of the call.
		- Modifying the returned map has no effect on the compiler.

		How
		- Implemented as a reverse RPC (`context.getDefines`) that returns a JSON-encoded list of
		  `[key, value]` pairs in the `v=` payload.
	**/
	public static function getDefines():Map<String, String> {
		final out:Map<String, String> = [];
		final payload = HostToCompilerRpc.call("context.getDefines", "");
		if (payload == null || payload.length == 0) return out;

		final m = Protocol.kvParse(payload);
		final countStr = m.exists("c") ? m.get("c") : "";
		final count = Std.parseInt(countStr);
		if (count == null || count <= 0) return out;

		for (i in 0...count) {
			final kKey = "k" + i;
			final vKey = "v" + i;
			if (!m.exists(kKey)) continue;
			out.set(m.get(kKey), m.exists(vKey) ? m.get(vKey) : "");
		}
		return out;
	}

	public static function getType(name:String):String {
		if (name == null || name.length == 0) return "missing";
		return MacroRuntime.builtinTypeDesc(name);
	}
}
