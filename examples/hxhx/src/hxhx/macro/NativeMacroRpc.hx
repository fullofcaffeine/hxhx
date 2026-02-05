package hxhx.macro;

/**
	OCaml runtime bridge for the Stage 4 macro host RPC selftest.

	Why
	- This keeps the first-rung macro-host bring-up small and robust:
	  - OCaml handles spawning + pipes (Unix)
	  - Haxe sees a single `selftest(hostExe)` call returning a stable summary

	What
	- `selftest(hostExe)`:
	  - spawns the macro host
	  - performs the v1 handshake
	  - issues a few stub calls over the protocol
	  - returns a newline-delimited report

	How
	- Implemented in `std/runtime/HxHxMacroRpc.ml`.
**/
@:native("HxHxMacroRpc")
extern class NativeMacroRpc {
	public static function selftest(hostExe:String):String;
}

