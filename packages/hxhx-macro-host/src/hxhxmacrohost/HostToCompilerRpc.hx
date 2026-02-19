package hxhxmacrohost;

/**
	Reverse (macro-host → compiler) RPC client for Stage 4 (Model A).

	Why
	- Stage 4’s macro host must be able to call back into the compiler while the compiler is
	  waiting for a response to its own request (duplex RPC).
	- Real macros need this: `haxe.macro.Compiler.*` and `haxe.macro.Context.*` are effectively
	  *compiler services* that macros call during compilation.
	- The fastest way to prove the duplex boundary exists is a tiny “define roundtrip”:
	  - macro host calls `Compiler.define(...)` (reverse RPC)
	  - macro host calls `Context.defined/definedValue(...)` (reverse RPC)
	  - the compiler responds based on compiler-owned state

	What
	- `call(method, tail)`:
	  - emits a `req` line to stdout
	  - blocks reading stdin until it receives a matching `res` line
	  - returns the decoded `v=<...>` payload

	How
	- Uses the same line-based protocol as the forward direction.
	- Uses **negative request IDs** to avoid collisions with the compiler’s (positive) IDs.
	- This is intentionally minimal: it assumes “one outstanding reverse call at a time” and does
	  not yet attempt to process compiler-initiated inbound requests while waiting.
**/
class HostToCompilerRpc {
	static var nextId:Int = -1;

	static inline function isTrueEnv(name:String):Bool {
		final v = Sys.getEnv(name);
		if (v == null) return false;
		final t = StringTools.trim(v).toLowerCase();
		return t == "1" || t == "true" || t == "yes";
	}

	/**
		Write a single diagnostic line to stderr.

		Why
		- We want optional bring-up tracing that can be enabled in CI/debug logs.

		Gotchas
		- Do not name this `trace`. Haxe treats `trace(...)` as a builtin that can be compiled out
		  under `-D no-traces`, even if a local function named `trace` exists.
	**/
	static function writeTraceLine(msg:String):Void {
		try {
			Sys.stderr().writeString(msg + "\n");
			Sys.stderr().flush();
		} catch (_:Dynamic) {}
	}

	static function traceEnabled():Bool {
		return isTrueEnv("HXHX_MACRO_HOST_TRACE");
	}

	static function summarizeTail(tail:String):String {
		if (tail == null || tail.length == 0) return "";
		// Avoid dumping user payloads; only surface keys to show which ABI shape is being used.
		try {
			final m = Protocol.kvParse(tail);
			final keys = new Array<String>();
			for (k in m.keys()) keys.push(k);
			return "keys=" + keys.join(",");
		} catch (_:Dynamic) {
			return "len=" + tail.length;
		}
	}

	public static function call(method:String, tail:String):String {
		final id = nextId--;
		if (traceEnabled()) writeTraceLine("[hxhx macro host rpc] -> " + method + (tail == null || tail.length == 0 ? "" : (" " + summarizeTail(tail))));
		final msg = (tail == null || tail.length == 0)
			? ("req " + id + " " + method + "\n")
			: ("req " + id + " " + method + " " + tail + "\n");
		Sys.print(msg);
		Sys.stdout().flush();

		var out:String = "";
		while (true) {
			final line = safeReadLine();
			if (line == null) throw "macro host: unexpected EOF while waiting for compiler response";
			final trimmed = StringTools.trim(line);
			if (trimmed.length == 0) continue;
			if (StringTools.startsWith(trimmed, "req ")) {
				// Not expected in the current rung (no concurrent compiler requests while we are inside a handler).
				throw "macro host: received unexpected compiler request while waiting for reverse response: " + trimmed;
			}
			if (!StringTools.startsWith(trimmed, "res ")) {
				throw "macro host: malformed reverse response: " + trimmed;
			}

			final parts = Protocol.splitN(trimmed, 3);
			final rid = Std.parseInt(parts[1]);
			if (rid == null || rid != id) throw "macro host: reverse response id mismatch: " + trimmed;

			final status = parts[2];
			final respTail = parts[3];
			if (status == "ok") {
				if (traceEnabled()) writeTraceLine("[hxhx macro host rpc] <- " + method + " ok");
				out = Protocol.kvGet(respTail, "v");
				break;
			}

			final msg = Protocol.kvGet(respTail, "m");
			final pos = Protocol.kvGet(respTail, "p");
			if (traceEnabled()) writeTraceLine("[hxhx macro host rpc] <- " + method + " err");
			throw (pos != null && pos.length > 0) ? ("compiler: " + msg + " (" + pos + ")") : ("compiler: " + msg);
		}

		return out;
	}

	static function safeReadLine():Null<String> {
		try {
			return cast (untyped __ocaml__("(try input_line stdin with End_of_file -> Obj.magic (HxRuntime.hx_null))"));
		} catch (_:Dynamic) {
			return null;
		}
	}
}
