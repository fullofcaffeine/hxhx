package hxhx.macro;

/**
	OCaml runtime bridge for the Stage 4 macro host RPC selftest (legacy).

	Why
	- This originally kept the first-rung macro-host bring-up small and robust:
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
	- Newer code should prefer the pure-Haxe client in `MacroHostClient`, which uses `sys.io.Process`
	  (overridden for the OCaml target via `std/_std/sys/io/Process.hx` + `std/runtime/HxProcess.ml`).

	Portability note
	- This bridge is OCaml-target-specific: it links a small OCaml module that uses `Unix` to spawn
	  the macro host and talk over stdin/stdout pipes.
	- This is a deliberate bootstrap seam while the OCaml-target portable stdlib/process APIs mature.
	- Long-term we want the compiler core to stay ~99% Haxe; once a stable process API exists, the
	  Haxe-side macro client can be implemented purely in Haxe.
	- For non-OCaml builds of `hxhx` (e.g. if we compile `hxhx` to Rust/C++ in the future), this
	  OCaml bridge cannot be used; those builds must provide an equivalent transport implementation.
**/
@:native("HxHxMacroRpc")
extern class NativeMacroRpc {
	public static function selftest(hostExe:String):String;
	public static function run(hostExe:String, expr:String):String;
	public static function get_type(hostExe:String, name:String):String;
}
