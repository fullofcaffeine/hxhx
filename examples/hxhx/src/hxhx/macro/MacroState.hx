package hxhx.macro;

/**
	Compiler-side macro state (Stage 4 bring-up).

	Why
	- The Stage 4 Model A macro host can call back into the compiler while the compiler is waiting
	  for a response (duplex RPC).
	- The first meaningful “macro effect” we support is `Compiler.define(name, value)`.
	- To be useful beyond a single RPC session, defines must live in a compiler-owned store that the
	  rest of the compilation pipeline can query *after* macros have run.

	What
	- A tiny, deterministic define store for bring-up:
	  - `setDefine(name, value)`
	  - `defined(name)` / `definedValue(name)`
	  - `reset()` between compilations/tests

	How
	- Implemented as a `StringMap<String>` so it compiles cleanly to OCaml without relying on target
	  runtime shims.
	- This is intentionally minimal and will eventually be replaced by the real compiler context that
	  also tracks classpaths, metadata, generated fields, etc.

	Gotchas
	- This is global state. Always call `reset()` at the start of any compilation entrypoint that may
	  execute macros (Stage 3 bring-up, Stage 4 selftests, upstream gate runners).
**/
class MacroState {
	static final defines:haxe.ds.StringMap<String> = new haxe.ds.StringMap();

	public static function reset():Void {
		defines.clear();
	}

	public static function setDefine(name:String, value:String):Void {
		if (name == null || name.length == 0) return;
		defines.set(name, value == null ? "" : value);
	}

	/**
		Seed defines from `-D` arguments.

		Why
		- Real compilations have an initial define set (CLI `-D`, target defaults, etc.).
		- Macros expect `Context.defined*` to reflect those defines.

		What
		- Accepts a list of raw `-D` strings in either form:
		  - `NAME`
		  - `NAME=VALUE`
		- Stores them as:
		  - `NAME → "1"` for the bare form
		  - `NAME → VALUE` for the `=` form
	**/
	public static function seedFromCliDefines(defines:Array<String>):Void {
		if (defines == null || defines.length == 0) return;
		for (raw in defines) {
			if (raw == null) continue;
			final s = StringTools.trim(raw);
			if (s.length == 0) continue;
			final eq = s.indexOf("=");
			if (eq == -1) {
				setDefine(s, "1");
			} else if (eq == 0) {
				// Ignore invalid `=VALUE` forms.
			} else {
				setDefine(s.substr(0, eq), s.substr(eq + 1));
			}
		}
	}

	public static function defined(name:String):Bool {
		if (name == null || name.length == 0) return false;
		return defines.exists(name);
	}

	public static function definedValue(name:String):String {
		if (name == null || name.length == 0) return "";
		final v = defines.get(name);
		return v == null ? "" : v;
	}

	/**
		Return define names in a stable order.

		Why
		- Useful for bring-up tests and diagnostics: we want deterministic output.

		What
		- Returns a sorted array of define keys.
	**/
	public static function listDefineNames():Array<String> {
		final out = new Array<String>();
		for (k in defines.keys()) out.push(k);
		out.sort((a, b) -> (a < b ? -1 : (a > b ? 1 : 0)));
		return out;
	}
}
