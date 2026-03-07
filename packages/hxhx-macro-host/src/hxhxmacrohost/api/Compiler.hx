package hxhxmacrohost.api;

import hxhxmacrohost.HostToCompilerRpc;
import hxhxmacrohost.Protocol;

typedef RuntimeCompilerConfiguration = {
	final version:Int;
	final args:Array<String>;
	final debug:Bool;
	final verbose:Bool;
	final foptimize:Bool;
	final platformConfig:haxe.macro.PlatformConfig;
	final stdPath:Array<String>;
	@:optional final platform:Dynamic;
}

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
	static inline final DEFAULT_COMPILER_VERSION:Int = 40307;

	static function parseNonNegativeInt(raw:String, fallback:Int):Int {
		final parsed = Std.parseInt(raw);
		return parsed == null || parsed < 0 ? fallback : parsed;
	}

	static function defaultPlatformConfig():haxe.macro.PlatformConfig {
		return {
			staticTypeSystem: true,
			sys: true,
			capturePolicy: haxe.macro.PlatformConfig.CapturePolicy.None,
			padNulls: false,
			addFinalReturn: false,
			overloadFunctions: false,
			canSkipNonNullableArgument: false,
			reservedTypePaths: [],
			supportsFunctionEquality: true,
			usesUtf16: false,
			thisBeforeSuper: false,
			supportsThreads: true,
			supportsUnicode: true,
			supportsRestArgs: true,
			exceptions: {
				nativeThrows: [],
				nativeCatches: [],
				avoidWrapping: false,
				wildcardCatch: null,
				baseThrow: null
			},
			scoping: {
				scope: haxe.macro.PlatformConfig.VarScope.FunctionScope,
				flags: []
			},
			supportsAtomics: false
		};
	}

	static function defaultConfiguration():RuntimeCompilerConfiguration {
		return {
			version: DEFAULT_COMPILER_VERSION,
			args: [],
			debug: false,
			verbose: false,
			foptimize: true,
			platformConfig: defaultPlatformConfig(),
			stdPath: []
		};
	}

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
		Return a conservative compiler-configuration snapshot.

		Why
		- Real initialization macros and parity probes read `Compiler.getConfiguration()` to decide
		  which target/runtime assumptions are active.
		- The external macro host therefore needs a compiler-owned snapshot instead of a host-local guess.

		What
		- Returns the bring-up subset we currently model:
		  - version
		  - raw args
		  - debug/verbose/no-opt flags
		  - std roots
		  - a conservative `PlatformConfig`

		Gotchas
		- This is not upstream's full internal configuration object yet.
		  Typed backend/display internals remain outside the current ABI slice.
	**/
	public static function getConfiguration():RuntimeCompilerConfiguration {
		final payload = HostToCompilerRpc.call("compiler.getConfiguration", "");
		if (payload == null || payload.length == 0)
			return defaultConfiguration();

		final parts = Protocol.kvParse(payload);
		final args = new Array<String>();
		final argsCount = parseNonNegativeInt(parts.exists("ac") ? parts.get("ac") : "", 0);
		for (i in 0...argsCount) {
			final key = "a" + i;
			if (parts.exists(key))
				args.push(parts.get(key));
		}

		final stdPath = new Array<String>();
		final stdCount = parseNonNegativeInt(parts.exists("sc") ? parts.get("sc") : "", 0);
		for (i in 0...stdCount) {
			final key = "s" + i;
			if (parts.exists(key))
				stdPath.push(parts.get(key));
		}

		final supportsUnicode = !parts.exists("uni") || parts.get("uni") == "1";
		final platformConfig:haxe.macro.PlatformConfig = {
			staticTypeSystem: true,
			sys: true,
			capturePolicy: haxe.macro.PlatformConfig.CapturePolicy.None,
			padNulls: false,
			addFinalReturn: false,
			overloadFunctions: false,
			canSkipNonNullableArgument: false,
			reservedTypePaths: [],
			supportsFunctionEquality: true,
			usesUtf16: false,
			thisBeforeSuper: false,
			supportsThreads: true,
			supportsUnicode: supportsUnicode,
			supportsRestArgs: true,
			exceptions: {
				nativeThrows: [],
				nativeCatches: [],
				avoidWrapping: false,
				wildcardCatch: null,
				baseThrow: null
			},
			scoping: {
				scope: haxe.macro.PlatformConfig.VarScope.FunctionScope,
				flags: []
			},
			supportsAtomics: false
		};

		return {
			version: parseNonNegativeInt(parts.exists("ver") ? parts.get("ver") : "", DEFAULT_COMPILER_VERSION),
			args: args,
			debug: parts.exists("dbg") && parts.get("dbg") == "1",
			verbose: parts.exists("vrb") && parts.get("vrb") == "1",
			foptimize: !parts.exists("opt") || parts.get("opt") == "1",
			platformConfig: platformConfig,
			stdPath: stdPath
		};
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
