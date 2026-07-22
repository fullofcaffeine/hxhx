package hxhx;

import haxe.io.Bytes;
import haxe.io.Eof;

/**
	Wait/connect transport helpers for Stage3 compiler-server flows.

	Why
	- `Stage3Compiler` needs to stay focused on one-shot compiler orchestration.
	- The persistent compiler-server transports (`--wait`, `--connect`) have their
	  own framing and response rules that are easier to evolve in isolation.

	What
	- Parses `--wait` and `--connect` flags from raw argv.
	- Implements stdio request framing, socket wait dispatch, and one-shot connect
	  request encoding/response handling.

	How
	- `Stage3Compiler` stays the public entrypoint and passes the minimum callbacks
	  needed for one-shot compilation and standard Stage3 error shaping.
	- This module is the only production caller of the temporary native socket helper;
	  see `docs/00-project/BOOTSTRAP_BRIDGE_RETIREMENT.md` before expanding that boundary.
**/
class Stage3WaitServer {
	public static function parseWaitMode(args:Array<String>) {
		final rest = new Array<String>();
		var waitMode:Null<String> = null;
		var i = 0;
		while (i < args.length) {
			final a = args[i];
			if (a == "--wait") {
				if (i + 1 >= args.length)
					throw "missing value after --wait";
				if (waitMode != null)
					throw "duplicate --wait flags are not supported";
				waitMode = args[i + 1];
				i += 2;
				continue;
			}
			rest.push(a);
			i += 1;
		}
		return {waitMode: waitMode, rest: rest};
	}

	public static function parseConnectMode(args:Array<String>) {
		final rest = new Array<String>();
		var connectMode:Null<String> = null;
		var i = 0;
		while (i < args.length) {
			final a = args[i];
			if (a == "--connect") {
				if (i + 1 >= args.length)
					throw "missing value after --connect";
				if (connectMode != null)
					throw "duplicate --connect flags are not supported";
				connectMode = args[i + 1];
				i += 2;
				continue;
			}
			rest.push(a);
			i += 1;
		}
		return {connectMode: connectMode, rest: rest};
	}

	static function hasDefineFlag(args:Array<String>, name:String):Bool {
		var i = 0;
		while (i < args.length) {
			if (args[i] == "-D" && i + 1 < args.length) {
				final d = args[i + 1];
				if (d == name || StringTools.startsWith(d, name + "="))
					return true;
				i += 2;
				continue;
			}
			i += 1;
		}
		return false;
	}

	static function writeWaitStdioReply(reply:CompilationServerReply):Void {
		final payload = CompilationServerRequestCodec.encodeReply(reply);

		final out = Sys.stderr();
		final value = payload.length;
		out.writeByte(value & 0xFF);
		out.writeByte((value >> 8) & 0xFF);
		out.writeByte((value >> 16) & 0xFF);
		out.writeByte(value >>> 24);
		out.writeString(payload);
		out.flush();
	}

	public static function runWaitStdio(baseArgs:Array<String>, runOne:(args:Array<String>, context:CompilationRequestContext) -> Int, error:String->Int):Int {
		final input = Sys.stdin();
		input.bigEndian = false;
		var requestId = 0;

		while (true) {
			var frameLen = 0;
			try {
				frameLen = input.readInt32();
			} catch (_:Eof) {
				return 0;
			} catch (e:haxe.io.Error) {
				return error("wait-stdio failed to read frame length: " + Std.string(e));
			} catch (e:String) {
				return error("wait-stdio failed to read frame length: " + e);
			}

			final lengthProblem = CompilationServerProtocol.requestLengthProblem(frameLen);
			if (lengthProblem != null) {
				writeWaitStdioReply(CompilationServerReply.message("hxhx(stage3): wait-stdio rejected " + lengthProblem, true));
				return 2;
			}

			final frame = try input.read(frameLen) catch (_:Eof) {
				return error("wait-stdio request frame truncated");
			};
			requestId += 1;
			final request = CompilationServerRequestCodec.decode(requestId, baseArgs, frame);
			final reply = CompilationServerRequestDispatcher.dispatch(request, runOne);
			writeWaitStdioReply(reply);
			if (reply.stopServer)
				return 0;
		}
	}

	public static function runWaitSocket(mode:String, baseArgs:Array<String>, runOne:(args:Array<String>, context:CompilationRequestContext) -> Int,
			error:String->Int):Int {
		var requestId = 0;
		final stopAfterReply = new CompilationServerStopSignal();
		final handleRequest = function(payload:String):String {
			requestId += 1;
			final request = CompilationServerRequestCodec.decodeString(requestId, baseArgs, payload);
			final reply = CompilationServerRequestDispatcher.dispatch(request, runOne);
			stopAfterReply.record(reply.stopServer);
			return CompilationServerRequestCodec.encodeSocketReply(reply);
		};
		final shouldStop = () -> stopAfterReply.take();
		return try {
			NativeCompilerServer.waitSocket(mode, CompilationServerProtocol.MAX_REQUEST_BYTES, handleRequest, shouldStop);
		} catch (e:String) {
			error("wait socket failed: " + e);
		}
	}

	#if hxhx_stage0_no_display
	static function readConnectDisplayStdin(_args:Array<String>):Null<Bytes> {
		return null;
	}
	#else
	static function readConnectDisplayStdin(args:Array<String>):Null<Bytes> {
		if (!hasDefineFlag(args, "display-stdin"))
			return null;

		final input = Sys.stdin();
		input.bigEndian = false;

		final frameLen = try {
			input.readInt32();
		} catch (_:Eof) {
			return null;
		} catch (e:haxe.io.Error) {
			throw "connect failed to read display-stdin frame length: " + Std.string(e);
		} catch (e:String) {
			throw "connect failed to read display-stdin frame length: " + e;
		}

		if (frameLen <= 0)
			return null;
		final lengthProblem = CompilationServerProtocol.requestLengthProblem(frameLen);
		if (lengthProblem != null)
			throw "connect rejected display-stdin " + lengthProblem;
		final frame = try {
			input.read(frameLen);
		} catch (_:Eof) {
			throw "connect display-stdin frame truncated";
		}
		if (frame.length == 0)
			return null;
		if (frame.get(0) == 0x01)
			return frame.sub(1, frame.length - 1);
		return frame;
	}
	#end

	static function encodeConnectRequest(args:Array<String>, stdinBytes:Null<Bytes>):String {
		final out = new StringBuf();
		for (arg in args) {
			out.add(arg);
			out.add("\n");
		}
		if (stdinBytes != null) {
			out.addChar(0x01);
			out.add(stdinBytes.getString(0, stdinBytes.length));
		}
		return out.toString();
	}

	static function processConnectResponse(response:String):Bool {
		if (response == null || response.length == 0)
			return false;
		final text = response;
		var hasError = false;
		for (line in text.split("\n")) {
			if (line.length == 0)
				continue;
			switch (line.charCodeAt(0)) {
				case 0x01:
					final parts = line.split(String.fromCharCode(0x01));
					if (parts.length > 1) {
						final printed = parts.slice(1).join("\n");
						if (printed.length > 0) {
							Sys.print(printed);
							if (!StringTools.endsWith(printed, "\n"))
								Sys.print("\n");
						}
					}
				case 0x02:
					hasError = true;
				case _:
					Sys.stderr().writeString(line + "\n");
			}
		}
		Sys.stdout().flush();
		Sys.stderr().flush();
		return hasError;
	}

	public static function runConnect(connectMode:String, requestArgs:Array<String>, error:String->Int):Int {
		final stdinBytes = try {
			readConnectDisplayStdin(requestArgs);
		} catch (e:String) {
			return error(e);
		}

		final argsWithCwd = new Array<String>();
		argsWithCwd.push("--cwd");
		argsWithCwd.push(Sys.getCwd());
		for (arg in requestArgs)
			argsWithCwd.push(arg);

		final payload = encodeConnectRequest(argsWithCwd, stdinBytes);
		final payloadBytes = Bytes.ofString(payload).length;
		final lengthProblem = CompilationServerProtocol.requestLengthProblem(payloadBytes);
		if (lengthProblem != null)
			return error("connect rejected " + lengthProblem);
		try {
			final response = NativeCompilerServer.connect(connectMode, payload);
			return processConnectResponse(response) ? 1 : 0;
		} catch (e:String) {
			return error("connect failed on " + connectMode + " (" + e + ")");
		}
	}
}
