package hxhx.macro;

/**
	Runtime effect sink used by in-process generated macro entrypoints.

	Why
	- The inproc macro runtime needs to mirror the observable effects of the current
	  exact-string entrypoint registry without pulling in the external-host RPC layer.
	- Keeping those effects behind a tiny interface lets the registry stay deterministic
	  while the concrete session owns hook storage and `MacroState` mutation.

	What
	- Defines the compiler-side effects generated entrypoints are allowed to perform in
	  the current bring-up rung: defines, classpaths, emitted OCaml modules, build-field
	  snippets, and hook registration.

	How
	- `InProcMacroSession` implements this interface and forwards each effect into
	  `MacroState` or its local hook arrays.
	- `InProcGeneratedEntrypoints` depends only on this interface, so its dispatch logic
	  stays small and easy to audit.
**/
interface InProcMacroEffectSink {
	public function setDefine(name:String, value:String):Void;
	public function definedValue(name:String):String;
	public function addClassPath(path:String):Void;
	public function emitOcamlModule(name:String, source:String):Void;
	public function emitBuildFields(modulePath:String, membersSource:String):Void;
	public function registerAfterTypingHook(cb:Void->Void):Void;
	public function registerOnGenerateHook(cb:Void->Void):Void;
	public function registerAfterGenerateHook(cb:Void->Void):Void;
}
