package hxhx.macro;

/**
	Shared macro-runtime session contract for Stage4 bring-up.

	Why
	- Stage3 orchestration needs one call surface regardless of whether macros run
	  in-process or via the external host.
	- On the OCaml backend, structural typedefs lower to `HxAnon` access, which is
	  safe for session wrappers. Using an interface here produced unsafe record
	  casts once a concrete session carried extra instance fields.

	What
	- Defines the exact callable surface Stage3 and expr-macro expansion need:
	  run, hook dispatch, expr expansion, and close.

	How
	- Runtime factories return exact-shape anonymous objects matching this typedef.
	- Concrete implementations can keep private state internally without exposing a
	  backend-sensitive object layout through the public session contract.
**/
typedef MacroRuntimeSession = {
	function run(expr:String):String;
	function runHook(kind:String, id:Int):Void;
	function runTypeNotFoundHook(id:Int, typePath:String):Bool;
	function expandExpr(expr:String):String;
	function close():Void;
}
