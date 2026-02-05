package hxhxmacrohost.api;

import hxhxmacrohost.HostToCompilerRpc;
import hxhxmacrohost.Protocol;

/**
	Minimal “Compiler-like” API surface for Stage 4 macro bring-up.

	Why
	- Real Haxe macros talk to `haxe.macro.Compiler` to affect compilation (defines, classpaths, etc.).
	- Stage 4 begins by proving that we can run *some* macro code in-process and make observable
	  changes to macro-host state, without delegating to stage0.

	What
	- Today this only supports `define(name, value)` as the smallest meaningful macro “effect”.

	How
	- Implemented as a **reverse RPC** to the compiler:
	  - macros call `Compiler.define(...)` inside the macro host
	  - the macro host sends `req ... compiler.define ...` back to the compiler
	  - the compiler owns the define store and replies with `res ... ok ...`
**/
class Compiler {
	public static function define(name:String, value:String):Void {
		if (name == null || name.length == 0) return;
		final tail = Protocol.encodeLen("n", name) + " " + Protocol.encodeLen("v", value == null ? "" : value);
		// Ignore return payload; errors propagate as exceptions.
		HostToCompilerRpc.call("compiler.define", tail);
	}

	/**
		Request the compiler to emit an additional OCaml module.

		Why
		- This is the smallest “generate code” effect we can prove early:
		  macros can ask the compiler to create extra target files.
		- Later stages will replace this with real AST/field generation, but the
		  artifact plumbing (macro → compiler → output) is the same.

		What
		- Sends a reverse RPC `compiler.emitOcamlModule` with:
		  - `n` (module name)
		  - `s` (raw `.ml` source)
	**/
	public static function emitOcamlModule(name:String, source:String):Void {
		if (name == null || name.length == 0) return;
		final tail = Protocol.encodeLen("n", name) + " " + Protocol.encodeLen("s", source == null ? "" : source);
		HostToCompilerRpc.call("compiler.emitOcamlModule", tail);
	}
}
