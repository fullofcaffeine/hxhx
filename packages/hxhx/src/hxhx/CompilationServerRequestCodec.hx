package hxhx;

import haxe.io.Bytes;

/**
	Decodes Haxe compiler-server request payloads after transport framing.

	Stdio length prefixes and socket NUL terminators remain transport concerns.
	Once those bytes are removed, both routes use this codec and therefore create
	the same immutable request record.
**/
class CompilationServerRequestCodec {
	public static function decode(requestId:Int, baseArgs:Array<String>, payload:Bytes):CompilationServerRequest {
		var sep = -1;
		for (i in 0...payload.length) {
			if (payload.get(i) == 0x01) {
				sep = i;
				break;
			}
		}

		final argsBytes = sep == -1 ? payload : payload.sub(0, sep);
		final stdinBytes = sep == -1 ? null : payload.sub(sep + 1, payload.length - (sep + 1));
		final rawArgs = argsBytes.getString(0, argsBytes.length);
		final args = new Array<String>();
		for (line0 in rawArgs.split("\n")) {
			var line = line0;
			if (line.length == 0)
				continue;
			if (line.charCodeAt(line.length - 1) == 13)
				line = line.substr(0, line.length - 1);
			if (line.length > 0)
				args.push(line);
		}

		return new CompilationServerRequest(requestId, baseArgs, args, stdinBytes);
	}

	public static function decodeString(requestId:Int, baseArgs:Array<String>, payload:String):CompilationServerRequest {
		return decode(requestId, baseArgs, Bytes.ofString(payload));
	}

	public static function encodeSocketReply(reply:CompilationServerReply):String {
		if (reply.isError)
			return String.fromCharCode(0x02) + reply.payload;
		return reply.payload;
	}
}
