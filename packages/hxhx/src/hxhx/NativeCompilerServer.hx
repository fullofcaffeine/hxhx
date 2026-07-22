package hxhx;

/**
	OCaml runtime bridge for Stage3 compiler-server socket transport.

	Why
	- Stage3 currently runs on top of bootstrap codegen that does not fully support
	  `sys.net.Socket` property access (`input` / `output`) from Haxe source.
	- We still need non-delegating compiler-server socket compatibility (`--wait <host:port>`
	  and `--connect <host:port>`) for upstream-style workflows.

	What
	- `waitSocket(mode, handleRequest)` starts a socket server (`<port>` or
	  `<host>:<port>`), reads compiler-server request frames, and passes each decoded
	  payload to the Haxe-owned shared dispatcher callback.
	- `connect(mode, request)` sends one request frame to a socket server and returns the raw
	  response bytes as a string.

	How
	- Implemented in `std/runtime/HxHxCompilerServer.ml`.
	- This is a transport-only bridge: Stage3 still owns request shaping and response printing logic.
	- `Stage3WaitServer` is the only production caller. Do not add socket behavior to other
	  compiler modules through this extern.

	Exit
	- Replace this bridge only after a pure-Haxe `sys.net.Socket` transport preserves framing,
	  connection failures, shutdown behavior, and the existing wait/connect roundtrip.
	- The complete exit evidence is recorded in
	  `docs/00-project/BOOTSTRAP_BRIDGE_RETIREMENT.md`.
**/
// `--interp` tests can import Stage3Compiler without linking the OCaml runtime bridge.
// Real socket transport still requires the native implementation below.
#if interp
class NativeCompilerServer {
	public static function waitSocket(_mode:String, _handleRequest:String->String):Int {
		throw "NativeCompilerServer.waitSocket is only available in the native hxhx runtime";
	}

	public static function connect(_mode:String, _request:String):String {
		throw "NativeCompilerServer.connect is only available in the native hxhx runtime";
	}
}
#else
@:native("HxHxCompilerServer")
extern class NativeCompilerServer {
	public static function waitSocket(mode:String, handleRequest:String->String):Int;
	public static function connect(mode:String, request:String):String;
}
#end
