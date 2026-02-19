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
	/**
		Get a compiler define value.

		Why
		- Upstream has `haxe.macro.Compiler.getDefine`, which is a macro expanding to
		  `Context.definedValue`. In practice, macro code still needs a “read define” primitive.
		- Exposing this as a bring-up rung lets us validate the reverse RPC path without pulling in
		  full `haxe.macro.*` emulation yet.

		What
		- Returns `null` if the flag is not defined.
		- Returns the define value otherwise (including `"1"` for bare `-D KEY`).

		How
		- Reverse RPC `compiler.getDefine` returns a JSON object `{ defined:Bool, value:String }`
		  in the `v=` payload.
	**/
	public static function getDefine(key:String):Null<String> {
		if (key == null || key.length == 0)
			return null;
		final payload = HostToCompilerRpc.call("compiler.getDefine", Protocol.encodeLen("n", key));
		if (payload == null || payload.length == 0)
			return null;
		final m = Protocol.kvParse(payload);
		final defined = m.exists("d") && m.get("d") == "1";
		if (!defined)
			return null;
		return m.exists("v") ? m.get("v") : "";
	}

	public static function define(name:String, value:String):Void {
		if (name == null || name.length == 0)
			return;
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
		if (name == null || name.length == 0)
			return;
		final tail = Protocol.encodeLen("n", name) + " " + Protocol.encodeLen("s", source == null ? "" : source);
		HostToCompilerRpc.call("compiler.emitOcamlModule", tail);
	}

	/**
		Add a compiler classpath (macro-time configuration).

		Why
		- Real-world macros (and targets/plugins like Reflaxe backends) often add classpaths
		  during `--macro` initialization.
		- This is also a useful early “macro influences compilation” effect that does not
		  require typed AST transforms yet: it changes which modules can be resolved.

		What
		- Sends a reverse RPC `compiler.addClassPath` with `cp=<...>`.
	**/
	public static function addClassPath(path:String):Void {
		if (path == null || path.length == 0)
			return;
		final tail = Protocol.encodeLen("cp", path);
		HostToCompilerRpc.call("compiler.addClassPath", tail);
	}

	/**
		Force-include a module in the compilation universe (bring-up rung).

		Why
		- Upstream supports `--macro include(\"pack.Mod\")` as a way to force types/modules
		  into the compilation even when nothing imports them directly.
		- This matters for some upstream unit fixtures and for plugin/backends that rely on
		  include-driven reachability.

		What
		- Sends reverse RPC `compiler.includeModule` with:
		  - `m`: module path (e.g. `unit.TestInt64`)
	**/
	public static function includeModule(modulePath:String):Void {
		if (modulePath == null || modulePath.length == 0)
			return;
		final tail = Protocol.encodeLen("m", modulePath);
		HostToCompilerRpc.call("compiler.includeModule", tail);
	}

	/**
		Emit a Haxe module (bootstrap rung).

		Why
		- Real macros eventually generate fields/types in the compiler’s typed AST.
		- Before we implement that, we can still prove the “macro generates code that affects resolution”
		  loop by emitting a `.hx` module into a compiler-managed generated directory that is part of the
		  classpath for the current compilation.

		What
		- Sends reverse RPC `compiler.emitHxModule` with:
		  - `n`: module name (simple identifier; bring-up rung)
		  - `s`: `.hx` source text
	**/
	public static function emitHxModule(name:String, source:String):Void {
		if (name == null || name.length == 0)
			return;
		final tail = Protocol.encodeLen("n", name) + " " + Protocol.encodeLen("s", source == null ? "" : source);
		HostToCompilerRpc.call("compiler.emitHxModule", tail);
	}

	/**
		Stage4 bring-up: emit build fields as raw Haxe class-member source text.

		Why
		- Real Haxe build macros return `Array<haxe.macro.Expr.Field>` and require a full macro
		  interpreter + typed AST integration.
		- Before that exists, we still want a deterministic rung that proves `@:build(...)` can
		  trigger a macro-host call and produce *new typed members* in the compiled output.

		What
		- Sends reverse RPC `compiler.emitBuildFields` with:
		  - `m`: module path (e.g. `demo.Main`)
		  - `s`: Haxe class-member snippet(s) to merge into that module's main class

		Gotchas
		- The snippet is parsed by the bootstrap parser, so keep it within the Stage3 subset
		  (simple `public static function ...` patterns).
	**/
	public static function emitBuildFields(modulePath:String, membersSource:String):Void {
		if (modulePath == null || modulePath.length == 0)
			return;
		final tail = Protocol.encodeLen("m", modulePath) + " " + Protocol.encodeLen("s", membersSource == null ? "" : membersSource);
		HostToCompilerRpc.call("compiler.emitBuildFields", tail);
	}
}
