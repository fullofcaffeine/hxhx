package hxhx.macro;

import hxhx.macro.ExprMacroDispatch;

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
	  run, hook dispatch, string expr expansion, selected-declaration dispatch,
	  project-macro plugin loading, and close.
	- `expandExpr` is the exact-text route used by builtin and registered
	  no-argument expressions. `expandSelected` is the structured route for a call
	  whose declaration was selected before typing; it carries authored argument
	  syntax and returns syntax or an explicit `Unavailable` reason.

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
	function expandSelected(request:ExprMacroDispatchRequest):ExprMacroDispatchResult;

	/**
		Load one validated project-macro plugin into this session and return the declarations it
		registered, in order. A session accepts at most one plugin; only the in-process runtime can
		load one (the external host has no structured dispatch method yet).
	**/
	function loadProjectMacroPlugin(artifactPath:String, pluginId:String):Array<String>;

	function close():Void;
}
