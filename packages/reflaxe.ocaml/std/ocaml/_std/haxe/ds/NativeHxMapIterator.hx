package haxe.ds;

/**
	Converts a runtime array into the target's structural Iterator carrier.

	The operation is separate from Map storage so runtime reports explain both
	the Map primitive and the iterator adapter at each iterator-producing method.
**/
@:noCompletion
@:ocamlRuntime("haxe-iterator")
@:native("HxIterator")
extern class NativeHxMapIterator {
	static function of_array<T>(items:Array<T>):Iterator<T>;
}
