/**
	Reads Stage3's table of declared function parameters.

	This focused module keeps the concrete `Map` operation outside the large
	`EmitterStage` compilation unit. The generic reflection helper used by older
	bootstrap paths cannot discover `Map.get` after hxhx is compiled to native
	OCaml, while expanding the concrete operation inside the mega-file makes the
	full bootstrap compilation materially slower and more memory-intensive.
**/
class EmitterCallSigIndex {
	/** Return the recorded declaration for `callee`, or `null` when none exists. */
	public static function get(index:Null<Map<String, EmitterCallSig>>, callee:Null<String>):Null<EmitterCallSig> {
		if (index == null || callee == null)
			return null;
		return index.get(callee);
	}
}
