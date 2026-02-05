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
	- We implement the process/piping logic in OCaml (`std/runtime/HxHxMacroRpc.ml`)
	  and expose it via a tiny extern (`NativeMacroRpc`).
	- Rationale: our OCaml emission uses dune builds with strict settings; relying
	  on `sys.io.Process` from the Haxe stdlib is not stable yet for this target.
	  Keeping the low-level IO in one OCaml module lets us validate the protocol
	  now without committing to a full `sys.io.Process` port.
**/
class MacroHostClient {
	public static function selftest():String {
		final exe = resolveMacroHostExe();
		if (exe == null || exe.length == 0) {
			throw "missing macro host exe (set HXHX_MACRO_HOST_EXE)";
		}
		return NativeMacroRpc.selftest(exe);
	}

	static function resolveMacroHostExe():String {
		final env = Sys.getEnv("HXHX_MACRO_HOST_EXE");
		if (env != null && env.length > 0) return env;
		return "";
	}
}

