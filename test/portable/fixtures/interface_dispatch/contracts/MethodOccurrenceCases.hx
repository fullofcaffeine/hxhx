/** Named interface methods remain eligible for checked dispatch and capture. */
interface NamedView {
	public function read():Int;
}

/** Structural methods use the same operation classification as named interfaces. */
typedef StructuralView = {
	function read():Int;
}

/** A callable data field is not a declared structural method. */
typedef CallbackRecord = {
	var read:Void->Int;
}

/** Ordinary data fields never select method dispatch. */
typedef DataRecord = {
	var read:Int;
}

/** Concrete and static method calls retain their existing direct-call owner. */
class Source implements NamedView {
	public function new() {}

	public function read():Int
		return 7;

	public static function staticRead():Int
		return 9;
}
