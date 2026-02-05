package hxhxmacrohost;

import hxhxmacrohost.api.Compiler;
import hxhxmacrohost.api.Context;

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
					handleReq(trimmed);
					continue;
				}

			// Unknown line; respond with an error if it looks structured.
			replyErr(0, "unknown message");
		}
	}

	static function safeReadLine():Null<String> {
		try {
			return cast (untyped __ocaml__("(try input_line stdin with End_of_file -> Obj.magic (HxRuntime.hx_null))"));
		} catch (_:Dynamic) {
			return null;
		}
	}

	static function handleReq(line:String):Void {
		final parts = Protocol.splitN(line, 3); // ["req", id, method, tail]
		final id = parts.length > 1 ? parseDecInt(parts[1]) : -1;
		final method = parts.length > 2 ? parts[2] : "";
		final tail = parts.length > 3 ? parts[3] : "";

		if (id < 0) {
			replyErr(0, "missing id");
			return;
		}

		try {
			switch (method) {
				case "ping":
					replyOk(id, Protocol.encodeLen("v", "pong"));
				case "compiler.define":
					final parsed = parseKV(tail);
					final name = parsed.exists("n") ? parsed.get("n") : "";
					final value = parsed.exists("v") ? parsed.get("v") : "";
					if (name.length == 0) {
						replyErr(id, method + ": missing name");
						return;
					}
					Compiler.define(name, value);
					replyOk(id, Protocol.encodeLen("v", "ok"));
				case "context.defined":
					final parsed = parseKV(tail);
					final name = parsed.exists("n") ? parsed.get("n") : "";
					replyOk(id, Protocol.encodeLen("v", Context.defined(name) ? "1" : "0"));
				case "context.definedValue":
					final parsed = parseKV(tail);
					final name = parsed.exists("n") ? parsed.get("n") : "";
					replyOk(id, Protocol.encodeLen("v", Context.definedValue(name)));
				case "macro.run":
					// Stage 4 bring-up rung: invoke a builtin macro “entrypoint”.
					//
					// This does NOT execute arbitrary user-provided macro modules yet. Instead we:
					// - parse a very small allowlist of builtin macro expressions
					// - dispatch to a real Haxe function compiled into this macro host binary
					// - return a deterministic summary string
					final parsed = parseKV(tail);
					final expr = parsed.exists("e") ? parsed.get("e") : "";
					if (expr.length == 0) {
						replyErr(id, method + ": missing expr");
						return;
					}
					replyOk(id, Protocol.encodeLen("v", runMacroExpr(expr)));
				case "context.getType":
					// Stage 4 bring-up rung: a minimal `Context.getType`-shaped call.
					// Upstream returns a typed representation; for bring-up we return a deterministic descriptor.
					final parsed = parseKV(tail);
					final name = parsed.exists("n") ? parsed.get("n") : "";
					if (name.length == 0) {
						replyErr(id, method + ": missing name");
						return;
					}
					replyOk(id, Protocol.encodeLen("v", Context.getType(name)));
				case _:
					replyErr(id, "unknown method: " + method);
			}
		} catch (e:Dynamic) {
			// Prefer structured macro-host errors (with a position payload) when available.
			final tag = Std.string(Reflect.field(e, "__hxhx_tag"));
			if (tag == MacroError.TAG) {
				final msg = Std.string(Reflect.field(e, "message"));
				final p:Dynamic = Reflect.field(e, "pos"); // `{fileName, lineNumber, ...}` (PosInfos)
				replyErr(id, method + ": " + msg, cast p);
				return;
			}
			replyErr(id, method + ": exception: " + Std.string(e));
		}
	}

	static function runMacroExpr(expr:String):String {
		final e = expr == null ? "" : StringTools.trim(expr);
		return switch (e) {
			case "hxhxmacrohost.BuiltinMacros.smoke()", "BuiltinMacros.smoke()":
				BuiltinMacros.smoke();
			case "hxhxmacrohost.BuiltinMacros.readFlag()", "BuiltinMacros.readFlag()":
				BuiltinMacros.readFlag();
			case "hxhxmacrohost.BuiltinMacros.fail()", "BuiltinMacros.fail()":
				BuiltinMacros.fail();
			case _:
				"ran:" + e;
		}
	}

	static function parseKV(tail:String):Map<String, String> {
		return Protocol.kvParse(tail);
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

	static function replyErr(id:Int, msg:String, ?pos:haxe.PosInfos):Void {
		// Include a `p` (“position”) field so the client can surface where the error originated.
		//
		// Today this is a macro-host *Haxe source* position (`file:line`), not a macro-user source position.
		// Later stages will attach typed/macro AST positions over the protocol.
		final p = pos == null ? "" : (pos.fileName + ":" + pos.lineNumber);
		Sys.println("res " + id + " err " + Protocol.encodeLen("m", msg) + " " + Protocol.encodeLen("p", p));
		flushStdout();
	}

	static function flushStdout():Void {
		// Flush after writing to stdout when talking over pipes.
		Sys.stdout().flush();
	}
}
