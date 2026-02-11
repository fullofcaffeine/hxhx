package hxhx;

/**
	OCaml runtime bridge for Stage3 compiler-server socket transport.

	Why
	- Stage3 currently runs on top of bootstrap codegen that does not fully support
	  `sys.net.Socket` property access (`input` / `output`) from Haxe source.
	- We still need non-delegating compiler-server socket compatibility (`--wait <host:port>`
	  and `--connect <host:port>`) for upstream-style workflows.

	What
	- `waitSocket(mode)` starts a socket server (`<port>` or `<host>:<port>`) and handles
	  compiler-server request frames.
	- `connect(mode, request)` sends one request frame to a socket server and returns the raw
	  response bytes as a string.

	How
	- Implemented in `std/runtime/HxHxCompilerServer.ml`.
	- This is a transport-only bridge: Stage3 still owns request shaping and response printing logic.

	Long-term note
	- Once socket IO is fully reliable in the Haxe layer for our bootstrap path, this bridge can be
	  replaced by a pure-Haxe transport without changing Stage3 CLI surface behavior.
**/
@:native("HxHxCompilerServer")
extern class NativeCompilerServer {
	public static function waitSocket(mode:String):Int;
	public static function connect(mode:String, request:String):String;
}
