/**
	Keeps a generated Void entrypoint call inside a static initializer.

	Generated entrypoint dispatch stores unknown return types as Dynamic. The
	untyped boundary must run init once and store Haxe null, with a call plan
	owned by this initializer rather than an unrelated method.
**/
class StaticEntrypoint {
	static final result:Dynamic = untyped GeneratedEntrypoint.init();

	public static function status():String {
		return result == null ? "static=null" : "static=value";
	}
}
