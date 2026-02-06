package hxhxmacrohost;

/**
	Stage 4 macro host runtime state (bring-up).

	Why
	- In the Model A design, the macro host is a long-running process that serves RPC requests.
	- Even in the earliest rungs, we need a single place to store “macro runtime” state:
	  - a define store (for `Compiler.define` and `Context.defined*`)
	  - small builtin type tables (for `Context.getType` bring-up)
	- Keeping this state centralized makes it possible to evolve toward:
	  - per-compilation reset,
	  - macro server reuse,
	  - structured protocol messages carrying typed data.

	What
	- `defines`: a name → string map that models compiler defines at macro-time.
	- `builtinTypes`: a tiny allowlist used by `Context.getType` during bring-up.

	How
	- Initialized once at macro host startup by `hxhxmacrohost.Main`.
	- Accessed by the OCaml-native “macro API” shims under `hxhxmacrohost.api.*`.

	Portability note
	- This is macro-host-internal code (Haxe compiled to OCaml). It intentionally does not rely
	  on host-specific shims beyond basic stdin/stdout transport, so later non-OCaml builds of
	  `hxhx` can keep the same structure and swap transport implementations.
**/
class MacroRuntime {
	/**
		Define store for macro-time `Compiler.define` and `Context.defined*` behavior.

		Note: this is intentionally initialized once per macro host process. The early Stage 4 runner
		spawns a fresh macro host per call, so per-compilation reset is implicitly covered.
	**/
	public static final defines:Map<String, String> = [];

	/**
		Hook callbacks registered via `Context.onAfterTyping`.

		Why
		- Upstream macros can register callbacks to run at later compilation phases.
		- Even in the out-of-process Model A macro host, we want to preserve the *shape* of that
		  API: macro code registers a closure, and the compiler later asks the macro host to run it.

		How
		- The macro host stores the closure in-process and returns an integer ID.
		- It then notifies the compiler of that ID via reverse RPC so the compiler can invoke it later.
	**/
	static final afterTypingHooks:Array<Array<Dynamic>->Void> = [];

	/**
		Hook callbacks registered via `Context.onGenerate`.

		See `afterTypingHooks` for the bring-up rationale.
	**/
	static final onGenerateHooks:Array<Array<Dynamic>->Void> = [];

	/**
		Field names for the current `Context.getBuildFields()` snapshot.

		Why
		- In upstream semantics, build macros often return the *entire* field array (old + new).
		- Our bring-up rung transports only *new* members as raw Haxe snippets back to the compiler
		  (`compiler.emitBuildFields`).
		- Keeping the original field name set in macro-host state allows us to compute a shallow delta:
		  emit only fields that weren't present in the original snapshot.

		Gotchas
		- Delta is by field name only; modifications to existing fields are ignored.
		- If a build macro doesn't call `Context.getBuildFields()` at all, we consider the snapshot absent.
	**/
	static var currentBuildFieldNames:Array<String> = [];
	static var hasBuildFieldSnapshot:Bool = false;

	public static function setCurrentBuildFieldNames(names:Array<String>):Void {
		currentBuildFieldNames = (names == null) ? [] : names.copy();
		hasBuildFieldSnapshot = true;
	}

	public static function clearCurrentBuildFieldSnapshot():Void {
		currentBuildFieldNames = [];
		hasBuildFieldSnapshot = false;
	}

	public static function hasCurrentBuildFieldSnapshot():Bool {
		return hasBuildFieldSnapshot;
	}

	public static function hasCurrentBuildFieldName(name:String):Bool {
		if (name == null || name.length == 0) return false;
		return currentBuildFieldNames.indexOf(name) != -1;
	}

	public static function registerAfterTyping(cb:Array<Dynamic>->Void):Int {
		afterTypingHooks.push(cb);
		return afterTypingHooks.length - 1;
	}

	public static function registerOnGenerate(cb:Array<Dynamic>->Void):Int {
		onGenerateHooks.push(cb);
		return onGenerateHooks.length - 1;
	}

	public static function runHook(kind:String, id:Int):Void {
		if (kind == null) throw "MacroRuntime.runHook: missing kind";
		if (id < 0) throw "MacroRuntime.runHook: invalid hook id: " + id;
		switch (kind) {
			case "afterTyping":
				if (id >= afterTypingHooks.length) throw "MacroRuntime.runHook: unknown afterTyping hook id: " + id;
				afterTypingHooks[id]([]);
			case "onGenerate":
				if (id >= onGenerateHooks.length) throw "MacroRuntime.runHook: unknown onGenerate hook id: " + id;
				onGenerateHooks[id]([]);
			case _:
				throw "MacroRuntime.runHook: unknown kind: " + kind;
		}
	}

	public static function builtinTypeDesc(name:String):String {
		return switch (name) {
			case "Int", "Float", "Bool", "String", "Void":
				"builtin:" + name;
			case _:
				"unknown:" + name;
		}
	}
}
