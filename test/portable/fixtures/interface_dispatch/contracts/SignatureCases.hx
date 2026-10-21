/** Aliases and parameter names do not change a method's calling contract. */
typedef Count = Int;

/** Independently authored declarations used only by the signature observer. */
interface First {
	function convert(left:Int):String;
}

/** The same method shape with an alias and a different parameter name. */
interface Second {
	function convert(right:Count):String;
}

/** Deliberately different declarations must not share a method contract key. */
interface Different {
	function convert(value:Bool):String;
	function renamed(value:Int):String;
	function nullable(value:Null<Int>):String;
	function optional(?value:Int):String;
	function generic<T>(value:T):T;
	function unresolved(value:Dynamic):String;
}

/** A named type verifies local and qualified native names have one identity. */
class Payload {
	public function new() {}
}

/** Ordinary named result types do not depend on the current emission module. */
interface Nominal {
	function payload():Payload;
}

/** A closed ordinary method view remains eligible for checked class dispatch. */
typedef ClosedView = {
	function read():Int;
}

/** A real class source remains eligible after cheap impossible-source rejection. */
class ViewSource {
	public function new() {}

	public function read():Int
		return 7;
}

/** Specialized iterator representations must retain their existing runtime owner. */
typedef IteratorView = Iterator<Int>;

/** Iterable factories return the specialized iterator representation too. */
typedef IterableView = Iterable<Int>;

/** Mirrors the macro host's map iterator without depending on compiler types. */
typedef PairIteratorView = Iterator<{key:String, value:Array<Payload>}>;
