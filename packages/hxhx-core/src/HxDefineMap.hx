/**
	Compilation define store (bootstrap utility).

	Why
	- Conditional compilation (`#if ...`) needs a single, explicit source of truth for which
	  identifiers are considered “defined”, and what their values are.
	- `hxhx` Stage 1/3 parse upstream-ish `.hxml` files where defines can come from multiple
	  CLI surfaces:
	  - `-D name` / `-D name=value`
	  - permissive flags we treat as defines (e.g. `--interp`, `--dce full`)
	  - macro-time `Compiler.define(...)` calls (Stage 4 bring-up)

	What
	- Represents defines as a `Map<String,String>`.
	- `parseDefine("foo")` => `{name:"foo", value:"1"}`
	- `parseDefine("foo=bar")` => `{name:"foo", value:"bar"}`

	How
	- Keep parsing deliberately small and deterministic.
	- Treat empty/invalid names as “ignore”.
**/
class HxDefineMap {
	/**
		Add one raw define string to a define map.

		Why
		- Keeps parsing logic in one place so both CLI parsing and macro-time define merging are consistent.
	**/
	public static function addRawDefine(dst:haxe.ds.StringMap<String>, raw:String):Void {
		if (dst == null || raw == null)
			return;
		final s = StringTools.trim(raw);
		if (s.length == 0)
			return;

		final eq = s.indexOf("=");
		if (eq == -1) {
			dst.set(s, "1");
			return;
		}

		final name = StringTools.trim(s.substr(0, eq));
		if (name.length == 0)
			return;
		final value = s.substr(eq + 1); // preserve spaces; callers can trim if desired
		dst.set(name, value);
	}

	public static function fromRawDefines(rawDefines:Array<String>):haxe.ds.StringMap<String> {
		final out = new haxe.ds.StringMap<String>();
		if (rawDefines == null)
			return out;
		for (raw in rawDefines)
			addRawDefine(out, raw);
		return out;
	}

	public static function mergeInto(dst:haxe.ds.StringMap<String>, src:haxe.ds.StringMap<String>):Void {
		if (dst == null || src == null)
			return;
		for (k in src.keys())
			dst.set(k, src.get(k));
	}
}
