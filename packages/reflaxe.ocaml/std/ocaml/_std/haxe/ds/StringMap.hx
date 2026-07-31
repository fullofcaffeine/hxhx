package haxe.ds;

/**
	OCaml-target implementation of Haxe's String-keyed mutable Map.

	The public API remains the Haxe 4.3.7 `StringMap` contract. Inline methods
	select typed `HxMap` operations before OCaml syntax is generated.
**/
@:coreApi
@:ocamlRuntime("haxe-map")
@:native("HxMap")
extern class StringMap<T> implements haxe.Constraints.IMap<String, T> {
	@:native("create_string")
	function new():Void;

	public inline function set(key:String, value:T):Void {
		NativeHxMap.set_string(this, key, value);
	}

	public inline function get(key:String):Null<T> {
		return NativeHxMap.get_string(this, key);
	}

	public inline function exists(key:String):Bool {
		return NativeHxMap.exists_string(this, key);
	}

	public inline function remove(key:String):Bool {
		return NativeHxMap.remove_string(this, key);
	}

	public inline function keys():Iterator<String> {
		return NativeHxMapIterator.of_array(NativeHxMap.keys_string(this));
	}

	public inline function iterator():Iterator<T> {
		return NativeHxMapIterator.of_array(NativeHxMap.values_string(this));
	}

	public inline function keyValueIterator():KeyValueIterator<String, T> {
		return NativeHxMapIterator.of_array(NativeHxMap.pairs_string(this));
	}

	public inline function copy():StringMap<T> {
		return NativeHxMap.copy_string(this);
	}

	public inline function toString():String {
		final entries = new Array<String>();
		final iterator = keyValueIterator();
		while (iterator.hasNext()) {
			final entry = iterator.next();
			entries.push(Std.string(entry.key) + " => " + Std.string(entry.value));
		}
		return "[" + entries.join(", ") + "]";
	}

	public inline function clear():Void {
		NativeHxMap.clear_string(this);
	}
}
