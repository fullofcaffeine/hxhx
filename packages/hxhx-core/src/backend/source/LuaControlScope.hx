package backend.source;

/** The nearest loop remains in its original protected-call depth. */
typedef LuaLoopScope = {
	final depth:Int;
	final breakFlag:String;
};

/**
	Track Lua function boundaries introduced only to implement Haxe try/catch.
	Returns cross every protected call. Loop transfers cross only calls inside
	the destination loop. Child scopes are immutable and share no request-global state.
**/
class LuaControlScope {
	public final classPlan:LuaClassPlan;
	public final depth:Int;
	public final loop:Null<LuaLoopScope>;

	public function new(classPlan:LuaClassPlan, depth:Int = 0, ?loop:LuaLoopScope) {
		this.classPlan = classPlan;
		this.depth = depth;
		this.loop = loop;
	}

	public function protectedCall():LuaControlScope
		return new LuaControlScope(classPlan, depth + 1, loop);

	public function withinLoop(breakFlag:String):LuaControlScope
		return new LuaControlScope(classPlan, depth, {depth: depth, breakFlag: breakFlag});
}
