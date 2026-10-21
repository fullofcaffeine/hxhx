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
