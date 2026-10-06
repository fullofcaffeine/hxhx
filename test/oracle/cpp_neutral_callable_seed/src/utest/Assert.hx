package utest;

/** Neutral bodies isolate signature adaptation from assertion semantics. */
class Assert {
	/** These assignable defaults deliberately do not invoke the supplied callback. */
	public static dynamic function createAsync(?int:Void->Void, ?int_:Int):Void->Void
		return function() {};

	public static dynamic function createEvent<EventArg>(int:EventArg->Void, ?int_:Int):EventArg->Void
		return function(event:EventArg) {};

	public static function observe(int:Dynamic, int_:String, ?position:haxe.PosInfos):Bool
		return false;

	public static function observeGeneric<T>(value:T, ?position:haxe.PosInfos):Bool
		return false;
}
