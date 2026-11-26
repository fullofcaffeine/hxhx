package hxhx.macro;

/**
	The type handles of one compilation.

	A `Ref` in a plugin is one of these handles (`hxhxmacrohost.MacroTypeWire`). The same
	declaration gets the same handle for the whole compilation (it is interned by name), but a
	handle is valid only in the macro call that last received it: `beginCall` makes every older
	handle stale, and a stale or unknown handle is an `invalid` request.
**/
class MacroTypeHandles {
	static var entries:Array<MacroTypeEntry> = [];
	static var issuedIn:Array<Int> = [];
	static var interned = new haxe.ds.StringMap<Int>();
	static var call = 0;

	/** A macro call starts: handles given to earlier calls become stale. */
	public static function beginCall():Void
		call++;

	/** The handle of `entry`; with a `key`, the same handle as earlier entries with that key. */
	public static function issue(key:Null<String>, entry:MacroTypeEntry):Int {
		if (key != null && interned.exists(key)) {
			final handle = interned.get(key);
			// The index may have been rebuilt since; keep this call's facts.
			entries[handle] = entry;
			issuedIn[handle] = call;
			return handle;
		}
		final handle = entries.length;
		entries.push(entry);
		issuedIn.push(call);
		if (key != null)
			interned.set(key, handle);
		return handle;
	}

	public static function get(handle:Int):MacroTypeEntry {
		if (handle < 0 || handle >= entries.length)
			throw "unknown type handle " + handle;
		if (issuedIn[handle] != call)
			throw "type handle " + handle + " is stale: an earlier macro call received it";
		return entries[handle];
	}

	public static function reset():Void {
		entries = [];
		issuedIn = [];
		interned = new haxe.ds.StringMap<Int>();
		call = 0;
	}
}
