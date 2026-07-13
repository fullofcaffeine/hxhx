package hxhx;

import haxe.io.Bytes;
import haxe.io.Eof;

private typedef WaitStdioRequest = {
	final args:Array<String>;
	final stdinBytes:Null<Bytes>;
};

private typedef WaitStdioReply = {
	final payload:String;
	final isError:Bool;
};

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

	static function findSingleFlagValue(args:Array<String>, flag:String):Null<String> {
		var i = 0;
		while (i < args.length) {
			if (args[i] == flag && i + 1 < args.length)
				return args[i + 1];
			i += 1;
		}
		return null;
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

	static function decodeWaitStdioRequest(frame:Bytes):WaitStdioRequest {
		var sep = -1;
		for (i in 0...frame.length) {
			if (frame.get(i) == 0x01) {
				sep = i;
				break;
			}
		}

		final argsBytes = sep == -1 ? frame : frame.sub(0, sep);
		final stdinBytes = sep == -1 ? null : frame.sub(sep + 1, frame.length - (sep + 1));

		final rawArgs = argsBytes.getString(0, argsBytes.length);
		final args = new Array<String>();
		for (line0 in rawArgs.split("\n")) {
			var line = line0;
			if (line.length == 0)
				continue;
			if (line.charCodeAt(line.length - 1) == 13)
				line = line.substr(0, line.length - 1);
			if (line.length == 0)
				continue;
			args.push(line);
		}

		return {args: args, stdinBytes: stdinBytes};
	}

	#if !hxhx_stage0_no_display
	static function synthesizeDisplayResponse(displayRequest:String, displaySource:String):String {
		return DisplayResponseSynthesizer.synthesize(displayRequest, displaySource);
	}
	#end

	static function runWaitStdioRequest(baseArgs:Array<String>, request:WaitStdioRequest, runOne:Array<String>->Int):WaitStdioReply {
		final displayRequest = findSingleFlagValue(request.args, "--display");
		#if hxhx_stage0_no_display
		if (displayRequest != null)
			return {payload: "hxhx(stage3): display unavailable in stage0 no-display profiling lane", isError: true};
		#else
		if (displayRequest != null) {
			final displaySource = DisplayResponseSynthesizer.readDisplaySource(displayRequest, request.stdinBytes);
			return {payload: synthesizeDisplayResponse(displayRequest, displaySource), isError: false};
		}
		#end

		final invocation = baseArgs.concat(request.args);
		final code = runOne(invocation);
		if (code == 0)
			return {payload: "OK", isError: false};
		return {payload: "hxhx(stage3): wait stdio request failed", isError: true};
	}

	static function writeWaitStdioReply(reply:WaitStdioReply):Void {
		var payload = "";
		if (reply.isError)
			payload += String.fromCharCode(0x02);
		if (reply.payload != null && reply.payload.length > 0)
			payload += reply.payload;

		final out = Sys.stderr();
		final value = payload.length;
		out.writeByte(value & 0xFF);
		out.writeByte((value >> 8) & 0xFF);
		out.writeByte((value >> 16) & 0xFF);
		out.writeByte(value >>> 24);
		out.writeString(payload);
		out.flush();
	}

	public static function runWaitStdio(baseArgs:Array<String>, runOne:Array<String>->Int, error:String->Int):Int {
		final input = Sys.stdin();
		input.bigEndian = false;

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

			if (frameLen < 0)
				return error("wait-stdio received negative frame length: " + frameLen);

			final frame = try input.read(frameLen) catch (_:Eof) {
				return error("wait-stdio request frame truncated");
			};
			final request = decodeWaitStdioRequest(frame);
			final reply = runWaitStdioRequest(baseArgs, request, runOne);
			writeWaitStdioReply(reply);
		}
	}

	public static function runWaitSocket(mode:String, error:String->Int):Int {
		return try {
			NativeCompilerServer.waitSocket(mode);
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
		try {
			final response = NativeCompilerServer.connect(connectMode, payload);
			return processConnectResponse(response) ? 1 : 0;
		} catch (e:String) {
			return error("connect failed on " + connectMode + " (" + e + ")");
		}
	}
}
