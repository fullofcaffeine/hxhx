package hxhx.macro;

/**
	Macro host RPC client (Stage 4, Model A).

	Why
	- Stage 4 starts executing macros natively.
	- Model A runs macros out-of-process and communicates via a versioned protocol.
	- This bead’s objective is **not** to run real user macros yet; it is to prove
	  the ABI boundary exists and is testable:
	  - spawn a macro host process
	  - complete a handshake
	  - invoke a couple of stubbed `Context.*` / `Compiler.*`-shaped calls

	What
	- `selftest()` is a deterministic acceptance probe used by CI:
	  - launches `hxhx-macro-host`
	  - performs the handshake
	  - runs stub calls (`ping`, `compiler.define`, `context.defined`, `context.definedValue`)
	  - returns a stable multi-line summary for grep-based assertions

	How
	- The protocol encoding lives in `MacroProtocol` (pure Haxe).
	- The transport uses `sys.io.Process` to spawn the macro host and communicate
	  via stdin/stdout.
	- On the OCaml target, `sys.io.Process` is provided by an override in
	  `std/_std/sys/io/Process.hx` backed by the small OCaml runtime shim
	  `std/runtime/HxProcess.ml`.
	- This keeps the compiler + protocol logic in Haxe while allowing early
	  bring-up on OCaml with strict dune warning/error settings.
**/
class MacroHostClient {
	public static function selftest():String {
		final client = connect();
		var out = "";
		try {
			final lines = new Array<String>();
			lines.push("macro_host=ok");
			lines.push("macro_ping=" + client.call("ping", ""));
			lines.push("macro_define=" + client.call("compiler.define", MacroProtocol.encodeLen("n", "foo") + " " + MacroProtocol.encodeLen("v", "bar")));
			lines.push("macro_defined=" + (client.call("context.defined", MacroProtocol.encodeLen("n", "foo")) == "1" ? "yes" : "no"));
			lines.push("macro_definedValue=" + client.call("context.definedValue", MacroProtocol.encodeLen("n", "foo")));
			out = lines.join("\n");
		} catch (e:Dynamic) {
			client.close();
			throw e;
		}
		client.close();
		return out;
	}

	public static function run(expr:String):String {
		final client = connect();
		var out = "";
		try {
			out = client.call("macro.run", MacroProtocol.encodeLen("e", expr));
		} catch (e:Dynamic) {
			client.close();
			throw e;
		}
		client.close();
		return out;
	}

	public static function getType(name:String):String {
		final client = connect();
		var out = "";
		try {
			out = client.call("context.getType", MacroProtocol.encodeLen("n", name));
		} catch (e:Dynamic) {
			client.close();
			throw e;
		}
		client.close();
		return out;
	}

	static function resolveMacroHostExe():String {
		final env = Sys.getEnv("HXHX_MACRO_HOST_EXE");
		if (env != null && env.length > 0) return env;
		return "";
	}

	static function connect():MacroClient {
		final exe = resolveMacroHostExe();
		if (exe == null || exe.length == 0) {
			throw "missing macro host exe (set HXHX_MACRO_HOST_EXE)";
		}
		return MacroClient.connect(exe);
	}
}

/**
	One macro-host client session (one process).

	Why
	- The Stage 4 Model A transport is line-based and stateful: the server prints a banner,
	  then expects a hello handshake, and then serves requests until `quit`.
	- Keeping a dedicated session type makes it easy to evolve toward:
	  - batching,
	  - request IDs,
	  - macro server reuse / caching.

	How
	- Uses `sys.io.Process`, which is implemented for the OCaml target via a small runtime shim
	  (`std/runtime/HxProcess.ml`) and the override in `std/_std/sys/io/Process.hx`.
**/
private class MacroClient {
	final proc:sys.io.Process;
	var nextId:Int = 1;

	function new(proc:sys.io.Process) {
		this.proc = proc;
	}

	public static function connect(exe:String):MacroClient {
		final p = new sys.io.Process(exe, []);
		final banner = p.stdout.readLine();
		if (banner != "hxhx_macro_rpc_v=1") {
			p.close();
			throw "macro host: unsupported banner: " + banner;
		}
		p.stdin.writeString("hello proto=1\n", null);
		p.stdin.flush();
		final ok = p.stdout.readLine();
		if (ok != "ok") {
			p.close();
			throw "macro host: handshake failed: " + ok;
		}
		return new MacroClient(p);
	}

	public function call(method:String, tail:String):String {
		final id = nextId++;
		final msg = tail == null || tail.length == 0
			? ("req " + id + " " + method + "\n")
			: ("req " + id + " " + method + " " + tail + "\n");
		proc.stdin.writeString(msg, null);
		proc.stdin.flush();

		final line = proc.stdout.readLine();
		final parts = MacroProtocol.splitN(line, 3);
		final rid = Std.parseInt(parts[1]);
		if (rid == null || rid != id) throw "macro host: response id mismatch: " + line;
		final status = parts[2];
		final respTail = parts[3];
		return if (status == "ok") {
			MacroProtocol.kvGet(respTail, "v");
		} else {
			throw "macro host: " + MacroProtocol.kvGet(respTail, "m");
		}
	}

	public function close():Void {
		try {
			proc.stdin.writeString("quit\n", null);
			proc.stdin.flush();
		} catch (_:Dynamic) {}
		proc.close();
	}
}
