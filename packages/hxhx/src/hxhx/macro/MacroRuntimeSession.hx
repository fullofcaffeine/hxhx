package hxhx.macro;

/**
	Shared macro-runtime session contract for Stage4 bring-up.

	Why
	- Stage3 currently runs macros through an external host process.
	- bxlg.9.1 introduces dual runtime modes (`external-host`, `inproc`) and needs one
	  call surface so Stage3 orchestration does not care which backend is active.
**/
interface MacroRuntimeSession {
	public function run(expr:String):String;
	public function runHook(kind:String, id:Int):Void;
	public function expandExpr(expr:String):String;
	public function close():Void;
}
