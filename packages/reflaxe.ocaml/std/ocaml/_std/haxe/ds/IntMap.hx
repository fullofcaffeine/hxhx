package haxe.ds;

/**
	OCaml-target implementation of Haxe's Int-keyed mutable Map.
**/
@:coreApi
@:ocamlRuntime("haxe-map")
@:native("HxMap")
extern class IntMap<T> implements haxe.Constraints.IMap<Int, T> {
	@:native("create_int")
	function new():Void;

	public inline function set(key:Int, value:T):Void {
		NativeHxMap.set_int(this, key, value);
	}

	public inline function get(key:Int):Null<T> {
		return NativeHxMap.get_int(this, key);
	}

	public inline function exists(key:Int):Bool {
		return NativeHxMap.exists_int(this, key);
	}

	public inline function remove(key:Int):Bool {
		return NativeHxMap.remove_int(this, key);
	}

	public inline function keys():Iterator<Int> {
		return NativeHxMapIterator.of_array(NativeHxMap.keys_int(this));
	}

	public inline function iterator():Iterator<T> {
		return NativeHxMapIterator.of_array(NativeHxMap.values_int(this));
	}

	public inline function keyValueIterator():KeyValueIterator<Int, T> {
		return NativeHxMapIterator.of_array(NativeHxMap.pairs_int(this));
	}

	public inline function copy():IntMap<T> {
		return NativeHxMap.copy_int(this);
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
		NativeHxMap.clear_int(this);
	}
}
