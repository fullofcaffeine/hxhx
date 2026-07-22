package hxhx;

import haxe.io.Bytes;

/**
	One decoded compiler-server request, independent of stdio or socket framing.

	The arrays and optional input bytes are copied on entry and when returned.
	This keeps transport buffers and callers from changing a request after the
	shared dispatcher has accepted it. The request is intentionally small: later
	incremental-cache identities belong to the server context, not this transport
	record.
**/
class CompilationServerRequest {
	public final requestId:Int;

	final baseArgsValue:Array<String>;
	final requestArgsValue:Array<String>;
	final stdinBytesValue:Null<Bytes>;

	public function new(requestId:Int, baseArgs:Array<String>, requestArgs:Array<String>, stdinBytes:Null<Bytes>) {
		this.requestId = requestId;
		this.baseArgsValue = baseArgs.copy();
		this.requestArgsValue = requestArgs.copy();
		this.stdinBytesValue = copyBytes(stdinBytes);
	}

	public function requestArgs():Array<String> {
		return requestArgsValue.copy();
	}

	public function invocationArgs():Array<String> {
		return baseArgsValue.concat(requestArgsValue);
	}

	public function stdinBytes():Null<Bytes> {
		return copyBytes(stdinBytesValue);
	}

	public function findFlagValue(flag:String):Null<String> {
		var i = 0;
		while (i < requestArgsValue.length) {
			if (requestArgsValue[i] == flag && i + 1 < requestArgsValue.length)
				return requestArgsValue[i + 1];
			i += 1;
		}
		return null;
	}

	public function hasInvocationFlag(flag:String):Bool {
		return baseArgsValue.indexOf(flag) >= 0 || requestArgsValue.indexOf(flag) >= 0;
	}

	public function hasRequestFlag(flag:String):Bool {
		return requestArgsValue.indexOf(flag) >= 0;
	}

	static function copyBytes(value:Null<Bytes>):Null<Bytes> {
		if (value == null)
			return null;
		return value.sub(0, value.length);
	}
}
