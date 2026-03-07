package hxhx.macro;

private enum MacroHostReadResult {
	ReadLine(line:String);
	ReadEof;
	ReadError(message:String);
}

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
	static function withClient<T>(run:MacroClient->T):T {
		final client = connect();
		try {
			final out = run(client);
			client.close();
			return out;
		} catch (e:String) {
			client.close();
			throw e;
		}
	}

	static function withSession<T>(run:MacroHostSession->T):T {
		final session = openSession();
		try {
			final out = run(session);
			session.close();
			return out;
		} catch (e:String) {
			session.close();
			throw e;
		}
	}

	/**
		Resolve the macro host executable path as `hxhx` sees it.

		Why
		- Stage 4 macro execution is an out-of-process model (RPC macro host).
		- For distribution, we want `hxhx` to “just work” when a sibling `hxhx-macro-host`
		  executable exists next to the `hxhx` binary.
		- For development/CI, we still allow overriding with `HXHX_MACRO_HOST_EXE`.

		What
		- Returns an absolute path when possible.
		- Returns `""` if no macro host can be resolved.

		Gotchas
		- This is a best-effort heuristic; callers should treat `""` as “not available”.
	**/
	public static function resolveMacroHostExePath():String {
		return resolveMacroHostExe();
	}

	public static function selftest():String {
		return withClient(function(client) {
			final lines = new Array<String>();
			lines.push("macro_host=ok");
			lines.push("macro_ping=" + client.call("ping", ""));
			lines.push("macro_define=" + client.call("compiler.define", MacroProtocol.encodeLen("n", "foo") + " " + MacroProtocol.encodeLen("v", "bar")));
			lines.push("macro_defined=" + (client.call("context.defined", MacroProtocol.encodeLen("n", "foo")) == "1" ? "yes" : "no"));
			lines.push("macro_definedValue=" + client.call("context.definedValue", MacroProtocol.encodeLen("n", "foo")));
			return lines.join("\n");
		});
	}

	public static function run(expr:String):String {
		return withClient(function(client) {
			return client.call("macro.run", MacroProtocol.encodeLen("e", expr));
		});
	}

	public static function loadNativeModule(modulePath:String, pluginId:String):Array<String> {
		return withSession(function(session) {
			return session.loadNativeModule(modulePath, pluginId);
		});
	}

	public static function runNativeModuleExpr(modulePath:String, pluginId:String, expr:String):String {
		return withSession(function(session) {
			session.loadNativeModule(modulePath, pluginId);
			return session.runNativeExpr(expr);
		});
	}

	/**
		Open a macro host session for a full compilation.

		Why
		- Hook registration (`Context.onAfterTyping`, `Context.onGenerate`) stores closures inside
		  the macro host process, so the session must remain alive until those hooks are invoked.
	**/
	public static function openSession():MacroHostSession {
		return new MacroHostSession(connect());
	}

	/**
		Run multiple macro expressions in a single macro-host session.

		Why
		- Even the earliest Stage 4 rungs need to exercise “real CLI macro” behavior (`--macro`),
		  which may include multiple macro expressions.
		- Spawning a macro host per expression is slow and makes ordering/state harder to reason about.
		- A single session also better matches the long-term “macro server” behavior upstream uses.

		What
		- Spawns one macro host process
		- Executes `macro.run` for each expression in order
		- Returns the list of `v=` payload strings (same as `run(expr)`)

		Gotchas
		- This is still a bring-up API: expressions are currently allowlisted on the server side.
		- The macro host is currently expected to be a fresh process per compilation; later stages
		  may add reuse/caching.
	**/
	public static function runAll(exprs:Array<String>):Array<String> {
		return withSession(function(session) {
			final out = new Array<String>();
			for (expr in exprs)
				out.push(session.run(expr));
			return out;
		});
	}

	public static function getType(name:String):String {
		return withClient(function(client) {
			return client.call("context.getType", MacroProtocol.encodeLen("n", name));
		});
	}

	public static function decodeNativeExprListPayload(payload:String):Array<String> {
		final parts = MacroProtocol.kvParse(payload == null ? "" : payload);
		final countStr = parts.exists("c") ? parts.get("c") : "0";
		final count = Std.parseInt(countStr);
		if (count == null || count < 0)
			throw "macro host: invalid native module expr count payload: " + countStr;
		final out = new Array<String>();
		for (i in 0...count) {
			final key = "e" + i;
			if (!parts.exists(key))
				throw "macro host: missing native module expr payload key: " + key;
			out.push(parts.get(key));
		}
		return out;
	}

	static function resolveMacroHostExe():String {
		final env = Sys.getEnv("HXHX_MACRO_HOST_EXE");
		if (env != null && env.length > 0)
			return env;

		// Distribution-friendly default: if `hxhx-macro-host` is shipped next to the `hxhx` binary,
		// discover it automatically so users don't have to set `HXHX_MACRO_HOST_EXE`.
		//
		// This is a best-effort heuristic:
		// - If `Sys.programPath()` is unavailable or points somewhere unexpected, we fall back to "".
		// - The env var always wins (useful for local dev or non-standard layouts).
		final prog = Sys.programPath();
		if (prog == null || prog.length == 0)
			return "";

		final abs = try sys.FileSystem.fullPath(prog) catch (_:String) prog;
		final dir = try haxe.io.Path.directory(abs) catch (_:String) "";
		if (dir == null || dir.length == 0)
			return "";

		final candidates = ["hxhx-macro-host", "hxhx-macro-host.exe", "hxhx-macro", "hxhx-macro.exe",];
		for (name in candidates) {
			final p = haxe.io.Path.join([dir, name]);
			try {
				if (sys.FileSystem.exists(p) && !sys.FileSystem.isDirectory(p))
					return p;
			} catch (_:String) {}
		}

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
	final hostIdleTimeoutSecs:Int;
	final hostTotalTimeoutSecs:Int;
	var nextId:Int = 1;
	var timeoutTriggered:Bool = false;

	static final TRACE:Bool = {
		final v = Sys.getEnv("HXHX_MACRO_TRACE");
		v == "1"
		|| v == "true"
		|| v == "yes";
	};
	static final TRACE_HOST:Bool = {
		final v = Sys.getEnv("HXHX_MACRO_HOST_TRACE");
		v == "1"
		|| v == "true"
		|| v == "yes";
	};
	static inline var HOST_POLL_INTERVAL_SECS:Float = 0.05;

	function new(proc:sys.io.Process) {
		this.proc = proc;
		this.hostIdleTimeoutSecs = parseTimeoutSeconds("HXHX_MACRO_HOST_IDLE_SECS", 90);
		this.hostTotalTimeoutSecs = parseTimeoutSeconds("HXHX_MACRO_HOST_TOTAL_SECS", 300);
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
		final callStart = haxe.Timer.stamp();
		var lastProgress = callStart;
		if (TRACE) {
			try
				Sys.stderr().writeString("[hxhx macro rpc] -> " + method + "\n")
			catch (_:haxe.io.Error) {} catch (_:String) {}
		}
		final msg = tail == null
			|| tail.length == 0 ? ("req " + id + " " + method + "\n") : ("req " + id + " " + method + " " + tail + "\n");
		try {
			proc.stdin.writeString(msg, null);
			proc.stdin.flush();
		} catch (e:haxe.io.Error) {
			throw "macro host: failed to write request: " + Std.string(e);
		} catch (e:String) {
			throw "macro host: failed to write request: " + e;
		}

		while (true) {
			final line = readLineForPhase(method, "response", callStart, lastProgress);
			lastProgress = haxe.Timer.stamp();
			final trimmed = StringTools.trim(line);
			if (trimmed.length == 0)
				continue;

			// Duplex bring-up: while we are waiting for a response, the macro host may send its own request
			// back to the compiler (this process).
			if (StringTools.startsWith(trimmed, "req ")) {
				handleInboundReq(trimmed);
				continue;
			}

			final parts = MacroProtocol.splitN(trimmed, 3);
			final rid = Std.parseInt(parts[1]);
			if (rid == null || rid != id)
				throw "macro host: response id mismatch: " + trimmed;
			final status = parts[2];
			final respTail = parts[3];
			if (status == "ok")
				return MacroProtocol.kvGet(respTail, "v");

			final msg = MacroProtocol.kvGet(respTail, "m");
			final pos = MacroProtocol.kvGet(respTail, "p");
			throw(pos != null && pos.length > 0) ? ("macro host: " + msg + " (" + pos + ")") : ("macro host: " + msg);
		}

		return "";
	}

	static function parseTimeoutSeconds(name:String, defaultValue:Int):Int {
		final raw = Sys.getEnv(name);
		if (raw == null)
			return defaultValue;
		final text = StringTools.trim(raw);
		if (text.length == 0)
			return defaultValue;
		final parsed = Std.parseInt(text);
		if (parsed == null || parsed < 0) {
			try
				Sys.stderr().writeString('hxhx: invalid ${name}=${raw}; expected non-negative integer, using ${defaultValue}.\n')
			catch (_:haxe.io.Error) {} catch (_:String) {}
			return defaultValue;
		}
		return parsed;
	}

	function readLineForPhase(method:String, phase:String, callStart:Float, lastProgress:Float):String {
		final lineResult = readLineWithTimeout(method, phase, callStart, lastProgress);
		return switch (lineResult) {
			case ReadLine(line):
				line;
			case ReadEof:
				final hostStderr = drainStderr(60);
				final exitCode = try proc.exitCode() catch (_:String) -1;
				throw "macro host: unexpected EOF during "
					+ phase
					+ " (method="
					+ method
					+ ", exit="
					+ exitCode
					+ ")"
					+ (hostStderr.length == 0 ? "" : ("\nmacro host stderr:\n" + hostStderr));
			case ReadError(message):
				throw "macro host: failed to read " + phase + " line: " + message;
		}
	}

	function readLineWithTimeout(method:String, phase:String, callStart:Float, lastProgress:Float):MacroHostReadResult {
		#if eval
		try {
			return ReadLine(proc.stdout.readLine());
		} catch (_:haxe.io.Eof) {
			return ReadEof;
		} catch (e:haxe.io.Error) {
			return ReadError(Std.string(e));
		} catch (e:String) {
			return ReadError(e);
		}
		#else
		var result:MacroHostReadResult = ReadError("uninitialized");
		var done = false;
		sys.thread.Thread.create(function() {
			try {
				result = ReadLine(proc.stdout.readLine());
			} catch (_:haxe.io.Eof) {
				result = ReadEof;
			} catch (e:haxe.io.Error) {
				result = ReadError(Std.string(e));
			} catch (e:String) {
				result = ReadError(e);
			}
			done = true;
		});
		while (!done) {
			ensureNoTimeout(method, phase, callStart, lastProgress);
			Sys.sleep(HOST_POLL_INTERVAL_SECS);
		}
		return result;
		#end
	}

	function ensureNoTimeout(method:String, phase:String, callStart:Float, lastProgress:Float):Void {
		final now = haxe.Timer.stamp();
		final totalElapsed = now - callStart;
		final idleElapsed = now - lastProgress;

		if (hostTotalTimeoutSecs > 0 && totalElapsed >= hostTotalTimeoutSecs) {
			failTimeout("total", method, phase, totalElapsed, idleElapsed);
		}

		if (hostIdleTimeoutSecs > 0 && idleElapsed >= hostIdleTimeoutSecs) {
			failTimeout("idle", method, phase, totalElapsed, idleElapsed);
		}
	}

	function failTimeout(reason:String, method:String, phase:String, totalElapsed:Float, idleElapsed:Float):Void {
		timeoutTriggered = true;
		final marker = "MACRO_HOST_STALL_DETECTED=1" + " reason=" + reason + " method=" + method + " phase=" + phase;
		try
			Sys.stderr().writeString(marker + "\n")
		catch (_:haxe.io.Error) {} catch (_:String) {}

		#if !eval
		sys.thread.Thread.create(function() {
			try
				proc.kill()
			catch (_:haxe.io.Error) {} catch (_:String) {}
			try
				proc.close()
			catch (_:haxe.io.Error) {} catch (_:String) {}
		});
		#end

		throw "macro host timeout (reason=" + reason + ", method=" + method + ", phase=" + phase + ", total=" + Std.int(totalElapsed) + "s, idle="
			+ Std.int(idleElapsed) + "s)\n" + marker;
	}

	function drainStderr(maxLines:Int):String {
		if (maxLines <= 0)
			return "";
		final lines = new Array<String>();
		try {
			while (lines.length < maxLines) {
				lines.push(proc.stderr.readLine());
			}
		} catch (_:haxe.io.Eof) {
			// ok
		} catch (_:haxe.io.Error) {} catch (_:String) {}
		return lines.join("\n");
	}

	function handleInboundReq(line:String):Void {
		final parts = MacroProtocol.splitN(line, 3); // ["req", id, method, tail]
		final id = Std.parseInt(parts[1]);
		final method = parts[2];
		final tail = parts[3];
		if (TRACE) {
			try
				Sys.stderr().writeString("[hxhx macro rpc] <- " + method + "\n")
			catch (_:haxe.io.Error) {} catch (_:String) {}
		}
		if (id == null) {
			replyErr(0, "missing id");
			return;
		}

		try {
			switch (method) {
				case "compiler.define":
					final name = MacroProtocol.kvGet(tail, "n");
					final value = MacroProtocol.kvGet(tail, "v");
					if (name == null || name.length == 0) {
						replyErr(id, method + ": missing name");
						return;
					}
					MacroState.setDefine(name, value);
					replyOk(id, MacroProtocol.encodeLen("v", "ok"));
				case "compiler.getDefine":
					final name = MacroProtocol.kvGet(tail, "n");
					if (name == null || name.length == 0) {
						replyErr(id, method + ": missing name");
						return;
					}
					final payload = MacroProtocol.encodeLen("d", MacroState.defined(name) ? "1" : "0")
						+ " "
						+ MacroProtocol.encodeLen("v", MacroState.definedValue(name));
					replyOk(id, MacroProtocol.encodeLen("v", payload));
				case "compiler.getConfiguration":
					final config = MacroState.getCompilerConfigurationSnapshot();
					final parts = new Array<String>();
					parts.push(MacroProtocol.encodeLen("ver", Std.string(config.version)));
					parts.push(MacroProtocol.encodeLen("dbg", config.debug ? "1" : "0"));
					parts.push(MacroProtocol.encodeLen("vrb", config.verbose ? "1" : "0"));
					parts.push(MacroProtocol.encodeLen("opt", config.foptimize ? "1" : "0"));
					parts.push(MacroProtocol.encodeLen("uni", config.supportsUnicode ? "1" : "0"));
					parts.push(MacroProtocol.encodeLen("target", config.targetName));
					parts.push(MacroProtocol.encodeLen("ac", Std.string(config.args.length)));
					for (i in 0...config.args.length)
						parts.push(MacroProtocol.encodeLen("a" + i, config.args[i]));
					parts.push(MacroProtocol.encodeLen("sc", Std.string(config.stdPath.length)));
					for (i in 0...config.stdPath.length)
						parts.push(MacroProtocol.encodeLen("s" + i, config.stdPath[i]));
					replyOk(id, MacroProtocol.encodeLen("v", parts.join(" ")));
				case "compiler.registerHook":
					final kind = MacroProtocol.kvGet(tail, "k");
					final idStr = MacroProtocol.kvGet(tail, "i");
					final hid = Std.parseInt(idStr);
					if (kind == null || kind.length == 0) {
						replyErr(id, method + ": missing kind");
						return;
					}
					if (hid == null) {
						replyErr(id, method + ": invalid hook id");
						return;
					}
					MacroState.registerHook(kind, hid);
					replyOk(id, MacroProtocol.encodeLen("v", "ok"));
				case "compiler.emitOcamlModule":
					final name = MacroProtocol.kvGet(tail, "n");
					final source = MacroProtocol.kvGet(tail, "s");
					if (name == null || name.length == 0) {
						replyErr(id, method + ": missing module name");
						return;
					}
					MacroState.emitOcamlModule(name, source);
					replyOk(id, MacroProtocol.encodeLen("v", "ok"));
				case "compiler.addClassPath":
					final cp = MacroProtocol.kvGet(tail, "cp");
					if (cp == null || cp.length == 0) {
						replyErr(id, method + ": missing classpath");
						return;
					}
					MacroState.addClassPath(cp);
					replyOk(id, MacroProtocol.encodeLen("v", "ok"));
				case "compiler.includeModule":
					final modulePath = MacroProtocol.kvGet(tail, "m");
					if (modulePath == null || modulePath.length == 0) {
						replyErr(id, method + ": missing module path");
						return;
					}
					MacroState.includeModule(modulePath);
					replyOk(id, MacroProtocol.encodeLen("v", "ok"));
				case "compiler.emitHxModule":
					final name = MacroProtocol.kvGet(tail, "n");
					final source = MacroProtocol.kvGet(tail, "s");
					if (name == null || name.length == 0) {
						replyErr(id, method + ": missing module name");
						return;
					}
					MacroState.emitHxModule(name, source);
					replyOk(id, MacroProtocol.encodeLen("v", "ok"));
				case "compiler.emitBuildFields":
					final modulePath = MacroProtocol.kvGet(tail, "m");
					final source = MacroProtocol.kvGet(tail, "s");
					if (modulePath == null || modulePath.length == 0) {
						replyErr(id, method + ": missing module path");
						return;
					}
					MacroState.emitBuildFields(modulePath, source);
					replyOk(id, MacroProtocol.encodeLen("v", "ok"));
				case "context.defined":
					final name = MacroProtocol.kvGet(tail, "n");
					replyOk(id, MacroProtocol.encodeLen("v", MacroState.defined(name) ? "1" : "0"));
				case "context.definedValue":
					final name = MacroProtocol.kvGet(tail, "n");
					replyOk(id, MacroProtocol.encodeLen("v", MacroState.definedValue(name)));
				case "context.currentPos":
					final pos = MacroState.getCurrentPos();
					final payload = MacroProtocol.encodeLen("f", pos.file) + " " + MacroProtocol.encodeLen("mi", Std.string(pos.min)) + " "
						+ MacroProtocol.encodeLen("ma", Std.string(pos.max));
					replyOk(id, MacroProtocol.encodeLen("v", payload));
				case "context.getExpectedType":
					replyOk(id, MacroProtocol.encodeLen("v", optionalText(MacroState.getExpectedTypeText())));
				case "context.getLocalModule":
					replyOk(id, MacroProtocol.encodeLen("v", MacroState.getLocalModule()));
				case "context.getLocalType":
					replyOk(id, MacroProtocol.encodeLen("v", optionalText(MacroState.getLocalTypeText())));
				case "context.getLocalMethod":
					replyOk(id, MacroProtocol.encodeLen("v", optionalText(MacroState.getLocalMethod())));
				case "context.getBuildFields":
					// Stage4 bring-up: expose the compiler-side build-field snapshot for the current
					// `@:build(...)` expansion context.
					//
					// Payload is a length-prefixed fragment list stored in `MacroState` (bring-up only).
					final payload = MacroState.getBuildFieldsPayload();
					replyOk(id, MacroProtocol.encodeLen("v", payload == null ? "" : payload));
				case "context.getDefines":
					final pairs = MacroState.listDefinesPairsSorted();
					final parts = new Array<String>();
					parts.push(MacroProtocol.encodeLen("c", Std.string(pairs.length)));
					for (i in 0...pairs.length) {
						final kv = pairs[i];
						parts.push(MacroProtocol.encodeLen("k" + i, kv[0]));
						parts.push(MacroProtocol.encodeLen("v" + i, kv[1]));
					}
					replyOk(id, MacroProtocol.encodeLen("v", parts.join(" ")));
				case _:
					replyErr(id, "unknown method: " + method);
			}
		} catch (e:haxe.io.Error) {
			replyErr(id, method + ": exception: " + Std.string(e));
		} catch (e:String) {
			replyErr(id, method + ": exception: " + e);
		}
	}

	inline function replyOk(id:Int, tail:String):Void {
		proc.stdin.writeString("res " + id + " ok " + tail + "\n", null);
		proc.stdin.flush();
	}

	static inline function optionalText(value:Null<String>):String {
		return value == null ? "" : value;
	}

	inline function replyErr(id:Int, msg:String):Void {
		proc.stdin.writeString("res " + id + " err " + MacroProtocol.encodeLen("m", msg) + " " + MacroProtocol.encodeLen("p", "") + "\n", null);
		proc.stdin.flush();
	}

	public function close():Void {
		if (timeoutTriggered)
			return;

		try {
			proc.stdin.writeString("quit\n", null);
			proc.stdin.flush();
		} catch (_:haxe.io.Error) {} catch (_:String) {}

		// Optional bring-up diagnostics: if the macro host logs to stderr (e.g. reverse-RPC tracing),
		// drain it after requesting shutdown so the output is visible in CI logs.
		if (TRACE_HOST) {
			try {
				while (true) {
					final line = proc.stderr.readLine();
					Sys.stderr().writeString(line + "\n");
				}
			} catch (_:haxe.io.Eof) {
				// expected
			} catch (_:haxe.io.Error) {} catch (_:String) {}
		}

		proc.close();
	}
}

/**
	Public wrapper around a single macro host process.

	Why
	- Stage3 needs to keep the macro host alive across phases so registered hook closures can run.

	What
	- `run(expr)`: calls `macro.run` and returns the `v=` payload.
	- `runHook(kind,id)`: calls `macro.runHook` to execute a previously-registered hook closure.
**/
class MacroHostSession implements MacroRuntimeSession {
	final client:MacroClient;

	public function new(client:MacroClient) {
		this.client = client;
	}

	public function run(expr:String):String {
		return client.call("macro.run", MacroProtocol.encodeLen("e", expr));
	}

	public function loadNativeModule(modulePath:String, pluginId:String):Array<String> {
		final payload = client.call("macro.loadNativeModule", MacroProtocol.encodeLen("p", modulePath) + " " + MacroProtocol.encodeLen("i", pluginId));
		final parts = MacroProtocol.kvParse(payload == null ? "" : payload);
		final countStr = parts.exists("c") ? parts.get("c") : "0";
		final count = Std.parseInt(countStr);
		if (count == null || count < 0)
			throw "macro host: invalid native module expr count payload: " + countStr;
		final out = new Array<String>();
		for (i in 0...count) {
			final key = "e" + i;
			if (!parts.exists(key))
				throw "macro host: missing native module expr payload key: " + key;
			out.push(parts.get(key));
		}
		return out;
	}

	public function runNativeExpr(expr:String):String {
		return client.call("macro.runNativeExpr", MacroProtocol.encodeLen("e", expr));
	}

	/**
		Expand an allowlisted “expression macro” call.

		Why
		- Expression macros are a core upstream feature: a call in normal code is executed at compile time
		  and replaced with the returned expression.
		- Stage4 bring-up models this by executing the call out-of-process (macro host) and returning
		  a Haxe expression text snippet for the compiler to parse into the bootstrap AST.

		What
		- Calls RPC `macro.expandExpr` with:
		  - `e`: the *exact* call text (e.g. `pack.Mod.meth()`).
		- Returns a Haxe expression text snippet (e.g. `"hello"` or `0`).

		Gotchas
		- This is a bring-up ABI. Today it is:
		  - allowlist-only (exact expression match),
		  - limited to a small expression grammar on the compiler side.
	**/
	public function expandExpr(expr:String):String {
		return client.call("macro.expandExpr", MacroProtocol.encodeLen("e", expr));
	}

	public function runHook(kind:String, id:Int):Void {
		final tail = MacroProtocol.encodeLen("k", kind == null ? "" : kind) + " " + MacroProtocol.encodeLen("i", Std.string(id));
		client.call("macro.runHook", tail);
	}

	public function close():Void {
		client.close();
	}
}
