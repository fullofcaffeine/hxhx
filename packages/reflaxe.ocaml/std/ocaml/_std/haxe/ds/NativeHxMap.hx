package haxe.ds;

/**
	Typed access to the OCaml target's checked mutable-map primitive.

	Public Map specializations select these functions in Haxe. The native
	boundary therefore exposes only storage operations; it does not decide which
	key representation or Haxe API method is in use.
**/
@:noCompletion
@:ocamlRuntime("haxe-map")
@:native("HxMap")
extern class NativeHxMap {
	static function create_string<V>():StringMap<V>;
	static function create_int<V>():IntMap<V>;
	static function create_object<K:{}, V>():ObjectMap<K, V>;

	static function set_string<V>(map:StringMap<V>, key:String, value:V):Void;
	static function set_int<V>(map:IntMap<V>, key:Int, value:V):Void;
	static function set_object<K:{}, V>(map:ObjectMap<K, V>, key:K, value:V):Void;

	static function get_string<V>(map:StringMap<V>, key:String):Null<V>;
	static function get_int<V>(map:IntMap<V>, key:Int):Null<V>;
	static function get_object<K:{}, V>(map:ObjectMap<K, V>, key:K):Null<V>;

	static function exists_string<V>(map:StringMap<V>, key:String):Bool;
	static function exists_int<V>(map:IntMap<V>, key:Int):Bool;
	static function exists_object<K:{}, V>(map:ObjectMap<K, V>, key:K):Bool;

	static function remove_string<V>(map:StringMap<V>, key:String):Bool;
	static function remove_int<V>(map:IntMap<V>, key:Int):Bool;
	static function remove_object<K:{}, V>(map:ObjectMap<K, V>, key:K):Bool;

	static function clear_string<V>(map:StringMap<V>):Void;
	static function clear_int<V>(map:IntMap<V>):Void;
	static function clear_object<K:{}, V>(map:ObjectMap<K, V>):Void;

	static function copy_string<V>(map:StringMap<V>):StringMap<V>;
	static function copy_int<V>(map:IntMap<V>):IntMap<V>;
	static function copy_object<K:{}, V>(map:ObjectMap<K, V>):ObjectMap<K, V>;

	static function keys_string<V>(map:StringMap<V>):Array<String>;
	static function keys_int<V>(map:IntMap<V>):Array<Int>;
	static function keys_object<K:{}, V>(map:ObjectMap<K, V>):Array<K>;

	static function values_string<V>(map:StringMap<V>):Array<V>;
	static function values_int<V>(map:IntMap<V>):Array<V>;
	static function values_object<K:{}, V>(map:ObjectMap<K, V>):Array<V>;

	static function pairs_string<V>(map:StringMap<V>):Array<{key:String, value:V}>;
	static function pairs_int<V>(map:IntMap<V>):Array<{key:Int, value:V}>;
	static function pairs_object<K:{}, V>(map:ObjectMap<K, V>):Array<{key:K, value:V}>;
}
