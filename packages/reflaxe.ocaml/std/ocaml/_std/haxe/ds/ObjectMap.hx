package haxe.ds;

/**
	OCaml-target implementation of Haxe's identity-keyed mutable Map.

	The target primitive compares object keys by physical identity, preserving the
	static-target `ObjectMap` contract without target-syntax method rewrites.
**/
@:coreApi
@:ocamlRuntime("haxe-map")
@:native("HxMap")
extern class ObjectMap<K:{}, V> implements haxe.Constraints.IMap<K, V> {
	@:native("create_object")
	function new():Void;

	public inline function set(key:K, value:V):Void {
		NativeHxMap.set_object(this, key, value);
	}

	public inline function get(key:K):Null<V> {
		return NativeHxMap.get_object(this, key);
	}

	public inline function exists(key:K):Bool {
		return NativeHxMap.exists_object(this, key);
	}

	public inline function remove(key:K):Bool {
		return NativeHxMap.remove_object(this, key);
	}

	public inline function keys():Iterator<K> {
		return NativeHxMapIterator.of_array(NativeHxMap.keys_object(this));
	}

	public inline function iterator():Iterator<V> {
		return NativeHxMapIterator.of_array(NativeHxMap.values_object(this));
	}

	public inline function keyValueIterator():KeyValueIterator<K, V> {
		return NativeHxMapIterator.of_array(NativeHxMap.pairs_object(this));
	}

	public inline function copy():ObjectMap<K, V> {
		return NativeHxMap.copy_object(this);
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
		NativeHxMap.clear_object(this);
	}
}
