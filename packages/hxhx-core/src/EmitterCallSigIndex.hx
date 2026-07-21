/**
	Reads Stage3's table of declared function parameters.

	This focused module keeps the concrete `Map` operation outside the large
	`EmitterStage` compilation unit. The generic reflection helper used by older
	bootstrap paths cannot discover `Map.get` after hxhx is compiled to native
	OCaml, while expanding the concrete operation inside the mega-file makes the
	full bootstrap compilation materially slower and more memory-intensive.
**/
#if ocaml
/**
	Typed declaration for the native map lookup used by an OCaml-built hxhx.

	`EmitterStage` deliberately passes its optional context tables as `Dynamic`.
	This avoids generating many specialized copies of its already-large recursive
	expression functions. In generated OCaml, that `Dynamic` value is represented
	as `Obj.t`, meaning “a value whose concrete OCaml type is intentionally hidden.”
	Declaring the runtime function explicitly keeps that type hidden until `HxMap`
	performs the lookup, instead of asking OCaml to treat the caller's `Obj.t` value
	as an already-specialized hash table.
**/
@:native("HxMap")
private extern class EmitterCallSigNativeMap {
	@:native("get_string")
	public static function getString(index:Dynamic, key:String):Dynamic;
}
#end

class EmitterCallSigIndex {
	/**
		Return the recorded declaration for `callee`, or `null` when none exists.

		`EmitterStage` carries optional context tables through an erased compiler-internal
		boundary so the bootstrap emitter does not specialize its large recursive expression
		functions for every table shape. This helper restores the one known table type before
		using `Map.get`; it never casts or guesses a value from the compiled Haxe program.
	**/
	public static function get(index:Dynamic, callee:Null<String>):Null<EmitterCallSig> {
		if (index == null || callee == null)
			return null;
		#if ocaml
		return cast EmitterCallSigNativeMap.getString(index, callee);
		#else
		final signatures:Map<String, EmitterCallSig> = cast index;
		return signatures.get(callee);
		#end
	}
}
