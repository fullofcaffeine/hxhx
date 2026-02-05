package hxhxmacrohost;

/**
	`hxhx-macro-host` (Stage 4) — a minimal out-of-process macro host.

	Why
	- Stage 4’s initial macro execution model (“Model A”) runs macros in a
	  separate process and communicates via a versioned protocol.
	- This is the *first rung*: we do not execute user macros yet; we only prove
	  that we can:
	  - spawn a host
	  - complete a handshake
	  - call a small subset of stubbed `haxe.macro.*`-like APIs over RPC

	What
	- Reads line-based `req` messages from stdin and writes `res` messages to
	  stdout.
	- Implements a tiny “define store” to model:
	  - `Compiler.define(name, value)`
	  - `Context.defined(name)`
	  - `Context.definedValue(name)`

	How
	- Protocol details live in `hxhxmacrohost.Protocol`.
	- This binary is built to native OCaml via `reflaxe.ocaml` and is launched
	  by `hxhx` during `--hxhx-macro-selftest` and later macro stages.
**/
class Main {
	static function main() {
		final defines:Map<String, String> = [];

		// Handshake banner: printed first so the client can verify protocol version.
		Sys.println(Protocol.SERVER_BANNER);
		flushStdout();

		// Expect `hello proto=1` then reply `ok`.
		final hello = safeReadLine();
		if (hello == null || hello.indexOf("hello") != 0) {
			Sys.println("err " + Protocol.encodeLen("m", "missing hello"));
			return;
		}
		if (hello.indexOf("proto=" + Protocol.VERSION) == -1) {
			Sys.println("err " + Protocol.encodeLen("m", "unsupported proto"));
			return;
		}
		Sys.println("ok");
		flushStdout();

		while (true) {
			final line = safeReadLine();
			if (line == null) return;
			final trimmed = StringTools.trim(line);
			if (trimmed.length == 0) continue;
				if (trimmed == "quit") return;

				if (StringTools.startsWith(trimmed, "req ")) {
					handleReq(trimmed, defines);
					continue;
				}

			// Unknown line; respond with an error if it looks structured.
			Sys.println("res 0 err " + Protocol.encodeLen("m", "unknown message"));
			flushStdout();
		}
	}

	static function safeReadLine():Null<String> {
		try {
			return cast (untyped __ocaml__("(try input_line stdin with End_of_file -> Obj.magic (HxRuntime.hx_null))"));
		} catch (_:Dynamic) {
			return null;
		}
	}

	static function handleReq(line:String, defines:Map<String, String>):Void {
		final parts = Protocol.splitN(line, 3); // ["req", id, method, tail]
		final id = parts.length > 1 ? parseDecInt(parts[1]) : -1;
		final method = parts.length > 2 ? parts[2] : "";
		final tail = parts.length > 3 ? parts[3] : "";

		if (id < 0) {
			Sys.println("res 0 err " + Protocol.encodeLen("m", "missing id"));
			flushStdout();
			return;
		}

		switch (method) {
			case "ping":
				replyOk(id, Protocol.encodeLen("v", "pong"));
			case "compiler.define":
				final parsed = parseKV(tail);
				final name = parsed.exists("n") ? parsed.get("n") : "";
				final value = parsed.exists("v") ? parsed.get("v") : "";
				if (name.length == 0) {
					replyErr(id, "missing name");
					return;
				}
				defines.set(name, value);
				replyOk(id, Protocol.encodeLen("v", "ok"));
			case "context.defined":
				final parsed = parseKV(tail);
				final name = parsed.exists("n") ? parsed.get("n") : "";
				replyOk(id, Protocol.encodeLen("v", defines.exists(name) ? "1" : "0"));
			case "context.definedValue":
				final parsed = parseKV(tail);
				final name = parsed.exists("n") ? parsed.get("n") : "";
				replyOk(id, Protocol.encodeLen("v", defines.exists(name) ? defines.get(name) : ""));
			case "macro.run":
				// Stage 4 bring-up rung: invoke a builtin macro “entrypoint”.
				//
				// This does NOT execute user-provided macro modules yet. It exists to prove the
				// request path used by later `--macro` support:
				// - hxhx (compiler core) decides to run a macro
				// - macro host receives the macro expression as an opaque string
				// - macro host responds deterministically
				final parsed = parseKV(tail);
				final expr = parsed.exists("e") ? parsed.get("e") : "";
				if (expr.length == 0) {
					replyErr(id, "missing expr");
					return;
				}
				replyOk(id, Protocol.encodeLen("v", "ran:" + expr));
			case _:
				replyErr(id, "unknown method: " + method);
		}
	}

	static function parseKV(tail:String):Map<String, String> {
		final m:Map<String, String> = [];
		if (tail == null || tail.length == 0) return m;
		final parts = tail.split(" ").filter(p -> p.length > 0);
		for (p in parts) {
			final eq = p.indexOf("=");
			if (eq <= 0) continue;
			final key = p.substr(0, eq);
			m.set(key, Protocol.decodeLenValue(p));
		}
		return m;
	}

	static function parseDecInt(s:String):Int {
		if (s == null) return -1;
		var i = 0;
		while (i < s.length && s.charCodeAt(i) == " ".code) i++;
		if (i >= s.length) return -1;
		var value = 0;
		var saw = false;
		while (i < s.length) {
			final c = s.charCodeAt(i);
			if (c < "0".code || c > "9".code) break;
			saw = true;
			value = value * 10 + (c - "0".code);
			i++;
		}
		return saw ? value : -1;
	}

	static function replyOk(id:Int, tail:String):Void {
		Sys.println("res " + id + " ok " + tail);
		flushStdout();
	}

	static function replyErr(id:Int, msg:String):Void {
		Sys.println("res " + id + " err " + Protocol.encodeLen("m", msg));
		flushStdout();
	}

	static function flushStdout():Void {
		// `Sys.stdout()` is not implemented yet in the portable OCaml stdlib surface.
		// We still need to flush when talking over pipes, so we use an OCaml escape hatch.
		untyped __ocaml__("flush stdout");
	}
}
